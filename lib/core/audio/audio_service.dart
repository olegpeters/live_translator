import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../logging/app_logger.dart';
import 'adaptive_tts_buffer.dart';

/// Converts raw 16-bit PCM mono bytes into a valid WAV format with a 44-byte RIFF header.
Uint8List pcmToWav(
  Uint8List pcmBytes, {
  int sampleRate = 24000,
  int numChannels = 1,
  int bitsPerSample = 16,
}) {
  final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final int blockAlign = numChannels * (bitsPerSample ~/ 8);
  final int dataSize = pcmBytes.length;
  final int chunkSize = 36 + dataSize;

  final ByteData header = ByteData(44);
  // "RIFF"
  header.setUint8(0, 0x52); // 'R'
  header.setUint8(1, 0x49); // 'I'
  header.setUint8(2, 0x46); // 'F'
  header.setUint8(3, 0x46); // 'F'
  // ChunkSize (little-endian)
  header.setUint32(4, chunkSize, Endian.little);
  // "WAVE"
  header.setUint8(8, 0x57); // 'W'
  header.setUint8(9, 0x41); // 'A'
  header.setUint8(10, 0x56); // 'V'
  header.setUint8(11, 0x45); // 'E'
  // "fmt "
  header.setUint8(12, 0x66); // 'f'
  header.setUint8(13, 0x6D); // 'm'
  header.setUint8(14, 0x74); // 't'
  header.setUint8(15, 0x20); // ' '
  // Subchunk1Size (16 for PCM)
  header.setUint32(16, 16, Endian.little);
  // AudioFormat (1 = PCM)
  header.setUint16(20, 1, Endian.little);
  // NumChannels
  header.setUint16(22, numChannels, Endian.little);
  // SampleRate
  header.setUint32(24, sampleRate, Endian.little);
  // ByteRate
  header.setUint32(28, byteRate, Endian.little);
  // BlockAlign
  header.setUint16(32, blockAlign, Endian.little);
  // BitsPerSample
  header.setUint16(34, bitsPerSample, Endian.little);
  // "data"
  header.setUint8(36, 0x64); // 'd'
  header.setUint8(37, 0x61); // 'a'
  header.setUint8(38, 0x74); // 't'
  header.setUint8(39, 0x61); // 'a'
  // Subchunk2Size
  header.setUint32(40, dataSize, Endian.little);

  final Uint8List wavBytes = Uint8List(44 + dataSize);
  wavBytes.setRange(0, 44, header.buffer.asUint8List());
  wavBytes.setRange(44, 44 + dataSize, pcmBytes);
  return wavBytes;
}

/// Amplifies 16-bit PCM mono bytes by a factor of [gain].
/// Values are clamped between -32768 and 32767 to prevent digital clipping overflow.
Uint8List amplifyPcm16(Uint8List pcmBytes, double gain) {
  if (gain == 1.0 || pcmBytes.isEmpty) return pcmBytes;

  final ByteData byteData = ByteData.sublistView(pcmBytes);
  final Uint8List amplifiedBytes = Uint8List(pcmBytes.length);
  final ByteData outData = ByteData.sublistView(amplifiedBytes);

  final int sampleCount = pcmBytes.length ~/ 2;
  for (int i = 0; i < sampleCount; i++) {
    final int sample = byteData.getInt16(i * 2, Endian.little);
    final int amplified = (sample * gain).round().clamp(-32768, 32767);
    outData.setInt16(i * 2, amplified, Endian.little);
  }

  return amplifiedBytes;
}

/// Applies a smooth linear fade-in and/or fade-out to 16-bit PCM mono bytes.
/// Micro fade-in/out (default 32 samples = ~1.3ms at 24kHz) is applied only at the
/// start/end of a stream to prevent DC-offset step pops, while keeping inner
/// batch boundaries bit-exact continuous to prevent stuttering/volume dips.
Uint8List applyPcm16EdgeSmoothing(
  Uint8List pcmBytes, {
  bool fadeIn = false,
  bool fadeOut = false,
  int fadeSamples = 32,
}) {
  if ((!fadeIn && !fadeOut) || pcmBytes.length < 4) return pcmBytes;

  final int totalSamples = pcmBytes.length ~/ 2;
  final int actualFadeSamples = min(fadeSamples, totalSamples ~/ 2);
  if (actualFadeSamples <= 0) return pcmBytes;

  final Uint8List smoothedBytes = Uint8List.fromList(pcmBytes);
  final ByteData byteData = ByteData.sublistView(smoothedBytes);

  if (fadeIn) {
    for (int i = 0; i < actualFadeSamples; i++) {
      final double factor = i / actualFadeSamples;
      final int sample = byteData.getInt16(i * 2, Endian.little);
      final int smoothed = (sample * factor).round().clamp(-32768, 32767);
      byteData.setInt16(i * 2, smoothed, Endian.little);
    }
  }

  if (fadeOut) {
    for (int i = 0; i < actualFadeSamples; i++) {
      final int sampleIndex = totalSamples - actualFadeSamples + i;
      final double factor = (actualFadeSamples - 1 - i) / actualFadeSamples;
      final int sample = byteData.getInt16(sampleIndex * 2, Endian.little);
      final int smoothed = (sample * factor).round().clamp(-32768, 32767);
      byteData.setInt16(sampleIndex * 2, smoothed, Endian.little);
    }
  }

  return smoothedBytes;
}

class _PcmChunk {
  final Uint8List bytes;
  final int sampleRate;
  final String? streamId;

  const _PcmChunk(this.bytes, this.sampleRate, [this.streamId]);
}

class AudioService {
  final AudioRecorder _recorder;
  final AudioPlayer _audioPlayer;

  /// Digital gain multiplier for output audio playback (e.g. 1.0 = 100%, 2.0 = 200%).
  double outputGain = 2.0;

  /// Playback speed rate multiplier (1.0 = normal, 1.3 = 30% faster).
  double currentPlaybackRate = 1.0;

  Future<void> setPlaybackRate(double rate) async {
    final clampedRate = rate.clamp(1.0, 1.3);
    if ((currentPlaybackRate - clampedRate).abs() > 0.01) {
      currentPlaybackRate = clampedRate;
      try {
        await _audioPlayer.setPlaybackRate(currentPlaybackRate);
      } catch (e) {
        AppLogger.warning('Failed to set playback rate: $e', tag: 'AudioService');
      }
    }
  }

  StreamSubscription<Uint8List>? _recordSubscription;
  final _audioStreamController = StreamController<Uint8List>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();

  List<_PcmChunk>? _pcmChunkQueue;
  List<_PcmChunk> get _queue => _pcmChunkQueue ??= <_PcmChunk>[];
  bool? _isPlaying;
  bool get _playing => _isPlaying ?? false;
  set _playing(bool value) => _isPlaying = value;
  Completer<void>? _currentPlaybackCompleter;
  bool? _isRecording;
  bool _flushRequested = false;

  /// Target minimum bytes buffered before starting a batch playback (~200ms at 24kHz PCM16 mono)
  static const int minBatchBytes = 9600;

  /// Maximum bytes to batch in a single play() call (~3.0s at 24kHz PCM16 mono)
  static const int maxBatchBytes = 144000;

  AudioService({AudioRecorder? recorder, AudioPlayer? audioPlayer})
      : _recorder = recorder ?? AudioRecorder(),
        _audioPlayer = audioPlayer ?? AudioPlayer() {
    _configureAudioContext();
  }

  void _configureAudioContext() {
    try {
      AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            audioMode: AndroidAudioMode.normal,
            isSpeakerphoneOn: true,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
      _audioPlayer.setVolume(1.0);
    } catch (e) {
      AppLogger.warning('Failed to set audio context: $e', tag: 'AudioService');
    }
  }

  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  bool get isRecording => _isRecording ?? false;

  Future<bool> checkAndRequestPermissions() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<void> prepareAudioForPlayback() async {
    try {
      if (kIsWeb) {
        await _audioPlayer.resume();
      }
    } catch (_) {}
  }

  /// The OpenAI realtime translation API requires 24 kHz PCM16 mono input.
  static const int inputSampleRate = 24000;

  Future<void> startRecording() async {
    if (isRecording) return;

    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    _isRecording = true;
    await _startStreamInternal();
  }

  Future<void> _startStreamInternal() async {
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: inputSampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
      androidConfig: const AndroidRecordConfig(
        audioSource: AndroidAudioSource.mic,
        audioManagerMode: AudioManagerMode.modeNormal,
        speakerphone: true,
      ),
      audioInterruption: AudioInterruptionMode.none,
    );

    try {
      final stream = await _recorder.startStream(config);

      await _recordSubscription?.cancel();
      _recordSubscription = stream.listen(
        (data) {
          if (!_audioStreamController.isClosed) {
            _audioStreamController.add(data);
            _calculateAudioLevel(data);
          }
        },
        onError: (error, stackTrace) {
          AppLogger.error('Recording stream error: $error', tag: 'AudioService', stackTrace: stackTrace);
          _handleRecordingError();
        },
        onDone: () {
          AppLogger.warning('Recording stream done', tag: 'AudioService');
          _handleRecordingError();
        },
      );
    } catch (e) {
      AppLogger.error('Failed to start recording stream: $e', tag: 'AudioService');
      _handleRecordingError();
      rethrow;
    }
  }

  void _handleRecordingError() {
    if (isRecording) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (isRecording) {
          _startStreamInternal().catchError((e) {
            AppLogger.error('Error restarting recording stream: $e', tag: 'AudioService');
          });
        }
      });
    }
  }

  void _calculateAudioLevel(Uint8List pcmBytes) {
    if (pcmBytes.length < 2) return;

    // Interpret bytes as 16-bit signed integers
    double sum = 0;
    int count = pcmBytes.length ~/ 2;

    for (int i = 0; i < pcmBytes.length - 1; i += 2) {
      // Little-endian 16-bit integer
      int sample = (pcmBytes[i + 1] << 8) | pcmBytes[i];
      if (sample > 32767) sample -= 65536; // Sign extension
      sum += sample * sample;
    }

    double rms = sqrt(sum / count);
    
    // Logarithmic (dBFS) scaling for realistic volume level meter
    double level = 0.0;
    if (rms > 0) {
      double db = 20 * log(rms / 32768.0) / ln10; // dBFS range: -inf .. 0 dB
      // Map -50 dBFS .. 0 dBFS to 0.0 .. 1.0
      level = ((db + 50) / 50).clamp(0.0, 1.0);
    }

    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(level);
    }
  }

  Future<void> pumpFromBuffer(AdaptiveTtsBuffer buffer) async {
    if (_playing) return;
    _playing = true;
    _runPlaybackLoop(buffer);
  }

  void _replenishQueueFromBuffer(AdaptiveTtsBuffer buffer) {
    int currentBytes = _queue.fold(0, (sum, c) => sum + c.bytes.length);
    // Replenish all available chunks in the jitter buffer up to maxBatchBytes
    while (currentBytes < maxBatchBytes && buffer.hasAudioToPlay) {
      final chunk = buffer.popNextChunk();
      if (chunk == null) break;
      setPlaybackRate(buffer.currentPlaybackSpeed);
      final processedBytes = outputGain != 1.0
          ? amplifyPcm16(chunk.bytes, outputGain)
          : chunk.bytes;
      _queue.add(_PcmChunk(processedBytes, chunk.sampleRate, chunk.streamId));
      currentBytes += processedBytes.length;
    }
  }

  Future<void> playAudioDelta(Uint8List pcmBytes,
      {int sampleRate = inputSampleRate}) async {
    if (pcmBytes.isEmpty) {
      _flushRequested = true;
      _startPlaybackLoop();
      return;
    }
    final processedBytes = outputGain != 1.0
        ? amplifyPcm16(pcmBytes, outputGain)
        : pcmBytes;
    _queue.add(_PcmChunk(processedBytes, sampleRate));
    _startPlaybackLoop();
  }

  void _startPlaybackLoop([AdaptiveTtsBuffer? buffer]) {
    if (_playing) return;
    _playing = true;
    _runPlaybackLoop(buffer);
  }

  Future<void> _runPlaybackLoop([AdaptiveTtsBuffer? buffer]) async {
    bool isStreamStart = true;

    while (_playing) {
      if (buffer != null) {
        _replenishQueueFromBuffer(buffer);
      }

      if (_queue.isEmpty) {
        break;
      }

      final int sampleRate = _queue.first.sampleRate;
      final String? currentStreamId = _queue.first.streamId;

      _flushRequested = false;

      // Batch consecutive chunks that share the same sample rate and stream ID up to maxBatchBytes.
      final chunks = <Uint8List>[];
      int batchedBytes = 0;
      while (_queue.isNotEmpty &&
          _queue.first.sampleRate == sampleRate &&
          (currentStreamId == null || _queue.first.streamId == currentStreamId) &&
          batchedBytes < maxBatchBytes) {
        final chunk = _queue.removeAt(0);
        chunks.add(chunk.bytes);
        batchedBytes += chunk.bytes.length;
      }

      final int totalLength = chunks.fold(0, (sum, c) => sum + c.length);
      if (totalLength == 0) continue;

      final Uint8List rawPcm = Uint8List(totalLength);
      int offset = 0;
      for (final chunk in chunks) {
        rawPcm.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      if (buffer != null) {
        _replenishQueueFromBuffer(buffer);
      }

  static const double maxPlaybackSpeed = 1.3;
  static const double speedStep = 0.05;
      final bool hasMoreAudio = _queue.isNotEmpty || (buffer != null && buffer.hasAudioToPlay);
      final bool shouldFadeIn = isStreamStart;
      final bool shouldFadeOut = !hasMoreAudio;
      isStreamStart = false;

      // Smooth micro fade-in/out only at outer stream boundaries (start/end of speech)
      final Uint8List pcmBytes = applyPcm16EdgeSmoothing(
        rawPcm,
        fadeIn: shouldFadeIn,
        fadeOut: shouldFadeOut,
        fadeSamples: 32,
      );

      final wavBytes = pcmToWav(pcmBytes, sampleRate: sampleRate);
      final completer = Completer<void>();
      _currentPlaybackCompleter = completer;

      final durationMs = (pcmBytes.length * 1000 / (sampleRate * 2 * currentPlaybackRate)).ceil();
      AppLogger.debug(
        'AudioService starting playback batch ($batchedBytes bytes, ${chunks.length} chunks, ~$durationMs ms, speed ${currentPlaybackRate.toStringAsFixed(2)}x)',
        tag: 'AudioService',
      );

      StreamSubscription? completeSub;
      try {
        completeSub = _audioPlayer.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });

        await _audioPlayer.play(BytesSource(wavBytes, mimeType: 'audio/wav'));

        await completer.future.timeout(
          Duration(milliseconds: durationMs + 300),
          onTimeout: () {
            AppLogger.warning(
              'Playback timeout reached after ${durationMs + 300} ms; completing batch completer',
              tag: 'AudioService',
            );
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        );
      } catch (e, st) {
        AppLogger.error('Playback error: $e', tag: 'AudioService', stackTrace: st);
        if (!completer.isCompleted) {
          completer.complete();
        }
      } finally {
        await completeSub?.cancel();
        _currentPlaybackCompleter = null;
      }
    }

    _playing = false;
    _flushRequested = false;

    if (buffer != null && buffer.hasAudioToPlay) {
      pumpFromBuffer(buffer);
    } else if (_queue.isNotEmpty) {
      _startPlaybackLoop();
    } else if (buffer != null) {
      buffer.rearmPreRoll();
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording) return;
    await _recordSubscription?.cancel();
    _recordSubscription = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _isRecording = false;
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(0.0);
    }
  }

  Future<void> stopPlayback() async {
    _playing = false;
    _flushRequested = false;
    _queue.clear();
    if (_currentPlaybackCompleter != null &&
        !_currentPlaybackCompleter!.isCompleted) {
      _currentPlaybackCompleter!.complete();
    }
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopRecording();
    await stopPlayback();
    _recorder.dispose();
    await _audioPlayer.dispose();
    await _audioStreamController.close();
    await _audioLevelController.close();
  }
}
