package de.jetapps.live_translator

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.PlaybackParams
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Gapless PCM16 mono player on top of AudioTrack (MODE_STREAM).
 *
 * Dart keeps the playout logic (ordering, pauses, catch-up) and only feeds a small lookahead
 * (~0.3–0.5 s). This class writes the PCM continuously into one AudioTrack, so there are no
 * gaps between chunks, and reports the real playback position back to Dart.
 *
 * Method channel `live_translator/pcm_player`:
 *   start({sampleRate}), write({bytes, segmentId}), setSpeed({speed}), flush(), stop()
 * Event channel `live_translator/pcm_player/events` (every ~50 ms while started):
 *   {type: "status", playedFrames, writtenFrames, queuedFrames, speed, segmentId, idle}
 */
class PcmStreamPlayer(messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private class Item(val bytes: ByteArray, val segmentId: String)

    private val methodChannel = MethodChannel(messenger, "live_translator/pcm_player")
    private val eventChannel = EventChannel(messenger, "live_translator/pcm_player/events")
    private val mainHandler = Handler(Looper.getMainLooper())

    private val queue = LinkedBlockingQueue<Item>()
    private var track: AudioTrack? = null
    private var writerThread: Thread? = null
    private var events: EventChannel.EventSink? = null
    private var sampleRate = 24000
    private var speed = 1.0f

    @Volatile private var running = false
    /** Frames handed to the AudioTrack so far (writer thread). */
    @Volatile private var writtenFrames = 0L
    /** Frames waiting in [queue] (not yet handed to the AudioTrack). */
    @Volatile private var queuedFramesInQueue = 0L

    /** Segment boundaries in written-frame coordinates: (startFrame, segmentId). */
    private val segmentStarts = ArrayDeque<Pair<Long, String>>()
    private val segmentLock = Any()

    private var lastHead = 0L
    private var headWraps = 0L

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    start(call.argument<Int>("sampleRate") ?: 24000)
                    result.success(null)
                }
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val segmentId = call.argument<String>("segmentId") ?: ""
                    if (bytes != null && bytes.isNotEmpty()) {
                        queuedFramesInQueue += bytes.size / 2
                        queue.offer(Item(bytes, segmentId))
                    }
                    result.success(null)
                }
                "setSpeed" -> {
                    setSpeed((call.argument<Double>("speed") ?: 1.0).toFloat())
                    result.success(null)
                }
                "flush" -> {
                    flush()
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "pcm_player ${call.method} failed", e)
            result.error("pcm_player_error", e.message, null)
        }
    }

    private fun start(rate: Int) {
        if (running && rate == sampleRate) return
        stop()
        sampleRate = rate
        val minBuf = AudioTrack.getMinBufferSize(
            rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        // Small hardware buffer (~120 ms) keeps latency low; Dart's lookahead absorbs jitter.
        val bufferBytes = maxOf(minBuf, rate * 2 * 120 / 1000)
        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferBytes)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track = t
        writtenFrames = 0L
        queuedFramesInQueue = 0L
        lastHead = 0L
        headWraps = 0L
        synchronized(segmentLock) { segmentStarts.clear() }
        applySpeed(t)
        t.play()
        running = true
        writerThread = Thread({ writerLoop(t) }, "PcmStreamPlayer-writer").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        scheduleStatus()
        Log.i(TAG, "started (sampleRate=$rate, buffer=$bufferBytes bytes)")
    }

    private fun writerLoop(t: AudioTrack) {
        var currentSegment: String? = null
        while (running) {
            val item = try {
                queue.poll(20, TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                null
            } ?: continue
            queuedFramesInQueue -= item.bytes.size / 2
            if (item.segmentId != currentSegment) {
                currentSegment = item.segmentId
                synchronized(segmentLock) { segmentStarts.addLast(writtenFrames to item.segmentId) }
            }
            var offset = 0
            while (running && offset < item.bytes.size) {
                // Blocking write: returns once the data fits into the AudioTrack buffer.
                val n = t.write(item.bytes, offset, item.bytes.size - offset)
                if (n <= 0) {
                    Log.w(TAG, "AudioTrack.write returned $n")
                    break
                }
                offset += n
                writtenFrames += n / 2
            }
        }
    }

    /** Playback head in frames, unwrapped (AudioTrack reports an unsigned 32-bit counter). */
    private fun playedFrames(t: AudioTrack): Long {
        val raw = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
        if (raw < lastHead) headWraps++
        lastHead = raw
        return minOf(raw + (headWraps shl 32), writtenFrames)
    }

    private fun scheduleStatus() {
        mainHandler.postDelayed(object : Runnable {
            override fun run() {
                val t = track ?: return
                if (!running) return
                val played = playedFrames(t)
                val written = writtenFrames
                var segmentId: String? = null
                synchronized(segmentLock) {
                    while (segmentStarts.size > 1 && segmentStarts.elementAt(1).first <= played) {
                        segmentStarts.removeFirst()
                    }
                    segmentId = segmentStarts.firstOrNull()?.second
                }
                val queued = (written - played) + queuedFramesInQueue
                events?.success(
                    mapOf(
                        "type" to "status",
                        "playedFrames" to played,
                        "writtenFrames" to written,
                        "queuedFrames" to queued,
                        "speed" to speed.toDouble(),
                        "segmentId" to segmentId,
                        "idle" to (queued <= 0L),
                    )
                )
                mainHandler.postDelayed(this, STATUS_INTERVAL_MS)
            }
        }, STATUS_INTERVAL_MS)
    }

    private fun setSpeed(value: Float) {
        speed = value.coerceIn(0.5f, 2.0f)
        track?.let { applySpeed(it) }
    }

    private fun applySpeed(t: AudioTrack) {
        try {
            // Time-stretch with constant pitch (Sonic-based in the Android framework).
            t.playbackParams = PlaybackParams().setSpeed(speed).setPitch(1.0f)
        } catch (e: Exception) {
            Log.w(TAG, "setPlaybackParams failed: ${e.message}")
        }
    }

    /** Drops all audio not yet played. */
    private fun flush() {
        queue.clear()
        queuedFramesInQueue = 0L
        val t = track ?: return
        t.pause()
        t.flush()
        writtenFrames = playedFrames(t)
        t.play()
    }

    private fun stop() {
        running = false
        writerThread?.interrupt()
        writerThread?.join(200)
        writerThread = null
        queue.clear()
        queuedFramesInQueue = 0L
        track?.let {
            try {
                it.pause()
                it.flush()
                it.release()
            } catch (_: Exception) {
            }
        }
        track = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    fun dispose() {
        stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    companion object {
        private const val TAG = "PcmStreamPlayer"
        private const val STATUS_INTERVAL_MS = 50L
    }
}
