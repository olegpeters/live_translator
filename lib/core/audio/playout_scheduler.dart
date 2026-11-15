import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';

import '../logging/app_logger.dart';
import 'pcm_stream_player.dart';
import 'pcm_utils.dart';

/// How a TTS segment (stream) ends; controls the pause inserted after it.
enum SegmentBoundary {
  /// Sentence end (. ! ? …): natural longer pause.
  sentence,

  /// Clause end (, ; :): short pause.
  clause,

  /// Forced split without punctuation (e.g. idle timeout): minimal pause.
  soft,
}

/// A chunk of translated audio with sequence tracking for ordering.
class SequencedAudioDelta {
  final Uint8List bytes;
  final int sampleRate;

  /// `streamIndex * 1000000 + chunkIndex`, assigned on receipt.
  final int sequenceNumber;
  final String streamId;
  final DateTime receivedAt;
  final bool isLastInStream;

  /// Boundary type of the segment; only meaningful on the last chunk / end marker.
  final SegmentBoundary? boundary;

  SequencedAudioDelta({
    required this.bytes,
    this.sampleRate = 24000,
    required this.sequenceNumber,
    required this.streamId,
    DateTime? receivedAt,
    this.isLastInStream = false,
    this.boundary,
  }) : receivedAt = receivedAt ?? clock.now();

  int get streamIndex => sequenceNumber ~/ 1000000;
  double get durationSeconds => bytes.length / (sampleRate * 2.0);
}

/// Playout health for the UI.
class AdaptiveBufferStatus {
  /// Predicted waiting time per segment needed to avoid mid-sentence starvation.
  final double targetDelaySeconds;

  /// Audio not yet played (scheduler queue + output device buffer).
  final double currentBufferDurationSeconds;
  final double currentPlaybackSpeed;
  final int outOfOrderEvents;

  /// Waiting for the current segment to build up enough audio before it starts.
  final bool isPreRolling;
  final double ttsLatencySeconds;
  final bool hasRecentOutOfOrderEvent;
  final double lastLateFragmentDelaySeconds;
  final int underruns;

  /// 1.0 = natural pauses, 0.0 = pauses removed (catch-up).
  final double pauseScale;

  const AdaptiveBufferStatus({
    required this.targetDelaySeconds,
    required this.currentBufferDurationSeconds,
    required this.currentPlaybackSpeed,
    required this.outOfOrderEvents,
    required this.isPreRolling,
    this.ttsLatencySeconds = 0.0,
    this.hasRecentOutOfOrderEvent = false,
    this.lastLateFragmentDelaySeconds = 0.0,
    this.underruns = 0,
    this.pauseScale = 1.0,
  });
}

class _Segment {
  final String id;
  final int index;
  final List<SequencedAudioDelta> pending = [];

  /// Arrival time and audio seconds received before that chunk (for the need estimate).
  final List<(DateTime, double)> arrivals = [];
  int lastReceivedSeq = 0;
  int lastEmittedSeq = 0;
  bool ended = false;
  DateTime? firstArrival;
  DateTime? lastArrival;
  double received = 0, emitted = 0, dropped = 0;
  bool started = false;
  bool speechStarted = false;
  bool starving = false;
  Uint8List? heldSilence;
  SegmentBoundary boundary = SegmentBoundary.sentence;

  _Segment(this.id, this.index);

  double get pendingSeconds => pending.fold(0.0, (s, c) => s + c.durationSeconds);
}

/// Playout scheduler for streamed TTS audio ("talkspurt"-style jitter buffer).
///
/// - **Ordering:** segments (TTS streams) play strictly in stream-index order, chunks by sequence.
/// - **Adaptive start delay:** a segment starts once it has waited long enough that, judging by
///   the arrival curves of recent segments, it won't starve mid-sentence (p90 + margin), or when
///   it is complete. Starvation is only allowed *between* segments, where it is a natural pause.
/// - **Pause shaping:** leading/trailing silence of TTS output is trimmed and replaced by a
///   defined pause depending on the segment boundary (sentence / clause / soft).
/// - **Catch-up:** with growing backlog, pauses are shortened first, then speech is played
///   slightly faster (pitch-preserving, via [PcmOutput.setSpeed]).
/// - Feeds a [PcmOutput] with a small lookahead, so ordering and timing decisions stay here.
class PlayoutScheduler {
  // --- start delay estimation
  static const double initialTargetDelay = 2.5;
  static const double minTargetDelay = 0.5;
  static const double maxTargetDelay = 8.0;
  static const double targetMargin = 0.3;
  static const int historySize = 10;
  static const double targetDecay = 0.85;

  // --- ordering
  /// Wait for a missing / stalled previous segment before moving on.
  static const int maxStreamTransitionWaitMs = 1000;

  // --- pause shaping
  static const int sentencePauseMs = 350;
  static const int clausePauseMs = 150;
  static const int softPauseMs = 80;
  static const int maxInternalPauseMs = 400;
  static const int minInternalPauseMs = 60;
  static const double silenceThresholdDbfs = -45.0;
  static const int analysisFrameMs = 10;
  static const int silenceKeepMs = 30;

  // --- catch-up
  static const double maxCatchUpSpeed = 1.25;
  static const double emergencySpeed = 1.3;
  static const double emergencyBacklogSeconds = 12.0;
  static const double speedRampStep = 0.05;

  /// Audio handed to the output ahead of playback.
  static const double outputLookaheadSeconds = 0.4;

  final int sampleRate;
  PcmOutput? _output;
  StreamSubscription<PcmOutputStatus>? _outputSub;

  double outputGain = 1.0;

  final SplayTreeMap<int, _Segment> _segments = SplayTreeMap();
  final Map<String, _Segment> _segmentsById = {};
  final List<double> _needHistory = [];
  int? _lastFinishedIndex;
  SegmentBoundary? _pendingPauseBoundary;
  bool _flushAll = false;

  double _targetDelaySeconds = initialTargetDelay;
  double _speed = 1.0;
  double _pauseScale = 1.0;
  int _outOfOrderEvents = 0;
  int _underruns = 0;
  double _ttsLatencySeconds = 0.0;
  double _lastLateFragmentSeconds = 0.0;
  bool _hasRecentOutOfOrderEvent = false;
  Timer? _outOfOrderFlashTimer;
  Timer? _wakeTimer;
  DateTime? _wakeAt;
  bool _feeding = false;
  bool _waitingForStart = false;
  int? _catchUpEvaluatedFor;

  final _statusController = StreamController<AdaptiveBufferStatus>.broadcast();
  Stream<AdaptiveBufferStatus> get onStatusChanged => _statusController.stream;

  PlayoutScheduler({PcmOutput? output, this.sampleRate = 24000}) {
    if (output != null) attachOutput(output);
  }

  void attachOutput(PcmOutput output) {
    _outputSub?.cancel();
    _output = output;
    _outputSub = output.status.listen(_onOutputStatus);
  }

  // ------------------------------------------------------------------ getters

  double get targetDelaySeconds => _targetDelaySeconds;
  double get currentPlaybackSpeed => _speed;
  int get outOfOrderEvents => _outOfOrderEvents;
  int get underruns => _underruns;
  double get pauseScale => _pauseScale;
  bool get isPreRolling => _waitingForStart;
  double get ttsLatencySeconds => _ttsLatencySeconds;
  bool get hasRecentOutOfOrderEvent => _hasRecentOutOfOrderEvent;
  double get lastLateFragmentDelaySeconds => _lastLateFragmentSeconds;

  /// Audio waiting in the scheduler (not yet handed to the output).
  double get queuedSeconds => _segments.values.fold(0.0, (s, seg) => s + seg.pendingSeconds);

  /// Total backlog: scheduler queue + output buffer.
  double get backlogSeconds => queuedSeconds + (_output?.queuedSeconds ?? 0.0);

  AdaptiveBufferStatus get currentStatus => AdaptiveBufferStatus(
        targetDelaySeconds: _targetDelaySeconds,
        currentBufferDurationSeconds: backlogSeconds,
        currentPlaybackSpeed: _speed,
        outOfOrderEvents: _outOfOrderEvents,
        isPreRolling: _waitingForStart,
        ttsLatencySeconds: _ttsLatencySeconds,
        hasRecentOutOfOrderEvent: _hasRecentOutOfOrderEvent,
        lastLateFragmentDelaySeconds: _lastLateFragmentSeconds,
        underruns: _underruns,
        pauseScale: _pauseScale,
      );

  void _notifyStatus() {
    if (!_statusController.isClosed) _statusController.add(currentStatus);
  }

  // ------------------------------------------------------------------ lifecycle

  Future<void> start() async {
    await _output?.start(sampleRate: sampleRate);
    await _output?.setSpeed(1.0);
  }

  /// Stops playback immediately and clears all state.
  Future<void> stop() async {
    reset();
    await _output?.flush();
    await _output?.stop();
  }

  /// Plays everything queued without further start delays (e.g. translation stopping).
  void flushPreRoll() {
    _flushAll = true;
    _feed();
  }

  void reset() {
    for (final seg in _segments.values) {
      _logSummary(seg);
    }
    _segments.clear();
    _segmentsById.clear();
    _needHistory.clear();
    _lastFinishedIndex = null;
    _pendingPauseBoundary = null;
    _flushAll = false;
    _targetDelaySeconds = initialTargetDelay;
    _speed = 1.0;
    _pauseScale = 1.0;
    _outOfOrderEvents = 0;
    _underruns = 0;
    _ttsLatencySeconds = 0.0;
    _lastLateFragmentSeconds = 0.0;
    _hasRecentOutOfOrderEvent = false;
    _outOfOrderFlashTimer?.cancel();
    _cancelWake();
    _waitingForStart = false;
    _catchUpEvaluatedFor = null;
    _notifyStatus();
  }

  void dispose() {
    _outOfOrderFlashTimer?.cancel();
    _cancelWake();
    _outputSub?.cancel();
    _statusController.close();
  }

  // ------------------------------------------------------------------ input

  /// Prior from the measured TTS latency (first text -> first audio) of a stream.
  void reportSectionLatency(double latencySeconds) {
    if (latencySeconds <= 0) return;
    _ttsLatencySeconds = latencySeconds;
    _notifyStatus();
  }

  void addChunk(SequencedAudioDelta delta) {
    final index = delta.streamIndex;
    final finished = _lastFinishedIndex;
    if (finished != null && index <= finished && !_segmentsById.containsKey(delta.streamId)) {
      if (delta.bytes.isNotEmpty) {
        _registerAnomaly(delta, 'late chunk for already finished segment ${delta.streamId}; dropped');
      }
      return;
    }

    final seg = _segmentsById[delta.streamId] ??= _createSegment(delta.streamId, index);
    final now = clock.now();

    if (delta.isLastInStream) {
      seg.ended = true;
      if (delta.boundary != null) seg.boundary = delta.boundary!;
    }

    if (delta.bytes.isNotEmpty) {
      if (delta.sequenceNumber <= seg.lastEmittedSeq) {
        seg.received += delta.durationSeconds;
        seg.dropped += delta.durationSeconds;
        _registerAnomaly(delta, 'chunk ${delta.sequenceNumber} after its position was played; dropped');
      } else {
        if (seg.lastReceivedSeq != 0 && delta.sequenceNumber != seg.lastReceivedSeq + 1) {
          _registerAnomaly(delta, 'out-of-order chunk ${delta.sequenceNumber} (last ${seg.lastReceivedSeq})');
        }
        seg.lastReceivedSeq = math.max(seg.lastReceivedSeq, delta.sequenceNumber);
        seg.firstArrival ??= delta.receivedAt;
        seg.lastArrival = delta.receivedAt;
        seg.arrivals.add((delta.receivedAt, seg.received));
        seg.received += delta.durationSeconds;
        var i = seg.pending.length;
        while (i > 0 && seg.pending[i - 1].sequenceNumber > delta.sequenceNumber) {
          i--;
        }
        seg.pending.insert(i, delta);
      }
    } else if (seg.firstArrival == null) {
      seg.lastArrival = now;
    }

    _feed();
  }

  _Segment _createSegment(String id, int index) {
    final seg = _Segment(id, index);
    _segments[index] = seg;
    return seg;
  }

  void _registerAnomaly(SequencedAudioDelta delta, String message) {
    _outOfOrderEvents++;
    _lastLateFragmentSeconds = delta.durationSeconds;
    _hasRecentOutOfOrderEvent = true;
    _outOfOrderFlashTimer?.cancel();
    _outOfOrderFlashTimer = Timer(const Duration(milliseconds: 500), () {
      _hasRecentOutOfOrderEvent = false;
      _notifyStatus();
    });
    AppLogger.warning('PlayoutScheduler $message', tag: 'PlayoutScheduler');
  }

  // ------------------------------------------------------------------ output feedback

  void _onOutputStatus(PcmOutputStatus status) {
    final current = _currentSegment();
    if (status.isIdle && current != null && current.started && !current.ended && current.pending.isEmpty) {
      if (!current.starving) {
        current.starving = true;
        _underruns++;
        AppLogger.warning(
          'PlayoutScheduler underrun: segment ${current.id} starved mid-segment '
          '(start delay ${_targetDelaySeconds.toStringAsFixed(2)}s too short)',
          tag: 'PlayoutScheduler',
        );
        // React immediately for the next segments; the exact need is learned at segment end.
        _targetDelaySeconds = math.min(maxTargetDelay, _targetDelaySeconds + 0.5);
      }
    }
    _feed();
  }

  // ------------------------------------------------------------------ playout

  _Segment? _currentSegment() => _segments.isEmpty ? null : _segments[_segments.firstKey()];

  void _feed() {
    if (_feeding) return;
    _feeding = true;
    try {
      final output = _output;
      if (output != null) {
        while (output.queuedSeconds < outputLookaheadSeconds) {
          final item = _nextItem(clock.now());
          if (item == null) break;
          output.write(item.$1, segmentId: item.$2).catchError((Object e) {
            AppLogger.warning('PcmOutput write failed: $e', tag: 'PlayoutScheduler');
          });
        }
      }
    } finally {
      _feeding = false;
    }
    _notifyStatus();
  }

  /// Next piece of audio to hand to the output: (pcm bytes, segmentId), or null if nothing is ready.
  (Uint8List, String)? _nextItem(DateTime now) {
    while (true) {
      final seg = _currentSegment();
      if (seg == null) {
        _waitingForStart = false;
        return null;
      }

      // Ordering: don't skip a missing earlier segment too eagerly.
      final finished = _lastFinishedIndex;
      if (!seg.started && finished != null && seg.index > finished + 1 && !_flushAll) {
        final since = seg.firstArrival ?? seg.lastArrival ?? now;
        final waited = now.difference(since).inMilliseconds;
        if (waited < maxStreamTransitionWaitMs) {
          _scheduleWake(Duration(milliseconds: maxStreamTransitionWaitMs - waited));
          return null;
        }
        AppLogger.warning(
          'PlayoutScheduler segment(s) ${finished + 1}..${seg.index - 1} missing; continuing with ${seg.id}',
          tag: 'PlayoutScheduler',
        );
      }

      if (!seg.started) {
        if (seg.pending.isEmpty) {
          if (seg.ended) {
            _finishSegment(seg); // stream without audio
            continue;
          }
          _waitingForStart = seg.firstArrival != null;
          return null;
        }
        if (!_canStart(seg, now)) {
          _waitingForStart = true;
          return null;
        }
        _waitingForStart = false;
        if (_catchUpEvaluatedFor != seg.index) {
          _catchUpEvaluatedFor = seg.index;
          _updateCatchUp();
        }

        // Defined pause after the previous segment (shortened when behind).
        final pauseBoundary = _pendingPauseBoundary;
        if (pauseBoundary != null) {
          _pendingPauseBoundary = null;
          final pauseMs = (_basePauseMs(pauseBoundary) * _pauseScale).round();
          if (pauseMs > 0) return (_silence(pauseMs), seg.id);
        }
        _startSegment(seg, now);
      }

      if (seg.pending.isNotEmpty) {
        final chunk = seg.pending.removeAt(0);
        seg.emitted += chunk.durationSeconds;
        seg.lastEmittedSeq = chunk.sequenceNumber;
        seg.starving = false;
        final pcm = _shape(seg, chunk.bytes);
        if (pcm.isEmpty) continue;
        return (outputGain != 1.0 ? amplifyPcm16(pcm, outputGain) : pcm, seg.id);
      }

      if (seg.ended) {
        _finishSegment(seg);
        continue;
      }

      // Started, not ended, nothing queued: starving or the stream stalled.
      final last = seg.lastArrival ?? now;
      final idleMs = now.difference(last).inMilliseconds;
      final hasNext = _segments.length > 1;
      if (hasNext && (idleMs >= maxStreamTransitionWaitMs || _flushAll)) {
        AppLogger.warning(
          'PlayoutScheduler segment ${seg.id} stalled ${idleMs}ms without end; moving on',
          tag: 'PlayoutScheduler',
        );
        _finishSegment(seg);
        continue;
      }
      if (hasNext) _scheduleWake(Duration(milliseconds: maxStreamTransitionWaitMs - idleMs));
      return null;
    }
  }

  bool _canStart(_Segment seg, DateTime now) {
    if (_flushAll || seg.ended) return true;
    final first = seg.firstArrival!;
    final waitedSeconds = now.difference(first).inMilliseconds / 1000.0;
    if (waitedSeconds >= _targetDelaySeconds) return true;
    _scheduleWake(Duration(milliseconds: ((_targetDelaySeconds - waitedSeconds) * 1000).ceil() + 1));
    return false;
  }

  void _startSegment(_Segment seg, DateTime now) {
    seg.started = true;
    final waited = now.difference(seg.firstArrival ?? now).inMilliseconds / 1000.0;
    AppLogger.info(
      'PlayoutScheduler start ${seg.id} (waited ${waited.toStringAsFixed(2)}s, '
      'buffered ${seg.pendingSeconds.toStringAsFixed(2)}s, ended=${seg.ended}, '
      'target ${_targetDelaySeconds.toStringAsFixed(2)}s, backlog ${backlogSeconds.toStringAsFixed(2)}s, '
      'speed ${_speed.toStringAsFixed(2)}x, pauses ${(_pauseScale * 100).round()}%)',
      tag: 'PlayoutScheduler',
    );
  }

  void _finishSegment(_Segment seg) {
    _segments.remove(seg.index);
    _segmentsById.remove(seg.id);
    _lastFinishedIndex = math.max(_lastFinishedIndex ?? seg.index, seg.index);
    if (seg.started) {
      _pendingPauseBoundary = seg.boundary;
      _learnNeed(seg);
    }
    _logSummary(seg);
  }

  /// Minimum start delay that would have avoided starvation for [seg] at 1.0x.
  void _learnNeed(_Segment seg) {
    final first = seg.firstArrival;
    if (first == null || seg.arrivals.isEmpty) return;
    double need = 0.0;
    for (final (at, before) in seg.arrivals) {
      final lag = at.difference(first).inMilliseconds / 1000.0 - before;
      if (lag > need) need = lag;
    }
    _needHistory.add(need);
    if (_needHistory.length > historySize) _needHistory.removeAt(0);
    final sorted = [..._needHistory]..sort();
    final p90 = sorted[((sorted.length - 1) * 0.9).round()];
    final previous = _targetDelaySeconds;
    final computed = (p90 + targetMargin).clamp(minTargetDelay, maxTargetDelay);
    // Asymmetric adaptation: raise immediately, lower gradually (max 15% per segment).
    _targetDelaySeconds = computed >= previous ? computed : math.max(computed, previous * targetDecay);
    AppLogger.info(
      'PlayoutScheduler ${seg.id} needed ${need.toStringAsFixed(2)}s start delay; '
      'target ${previous.toStringAsFixed(2)}s -> ${_targetDelaySeconds.toStringAsFixed(2)}s',
      tag: 'PlayoutScheduler',
    );
  }

  // ------------------------------------------------------------------ catch-up

  void _updateCatchUp() {
    final excess = backlogSeconds - _targetDelaySeconds;
    double pauseScale;
    double targetSpeed;
    if (backlogSeconds >= emergencyBacklogSeconds) {
      pauseScale = 0.0;
      targetSpeed = emergencySpeed;
    } else {
      pauseScale = excess <= 0.5 ? 1.0 : (excess >= 2.0 ? 0.2 : 1.0 - (excess - 0.5) / 1.5 * 0.8);
      targetSpeed = excess <= 2.0
          ? 1.0
          : math.min(maxCatchUpSpeed, 1.0 + (excess - 2.0) / 4.0 * (maxCatchUpSpeed - 1.0));
    }
    _pauseScale = pauseScale;

    // Gentle ramp, applied at segment boundaries only.
    double next = _speed;
    if (targetSpeed > _speed) {
      next = math.min(targetSpeed, _speed + speedRampStep);
    } else if (targetSpeed < _speed) {
      next = math.max(targetSpeed, _speed - speedRampStep);
    }
    if ((next - _speed).abs() > 0.001) {
      _speed = double.parse(next.toStringAsFixed(2));
      _output?.setSpeed(_speed);
    }
  }

  int _basePauseMs(SegmentBoundary b) => switch (b) {
        SegmentBoundary.sentence => sentencePauseMs,
        SegmentBoundary.clause => clausePauseMs,
        SegmentBoundary.soft => softPauseMs,
      };

  // ------------------------------------------------------------------ silence shaping

  int get _frameBytes => sampleRate * analysisFrameMs ~/ 1000 * 2;

  late final double _silenceAmplitude = 32768.0 * math.pow(10, silenceThresholdDbfs / 20);

  bool _isSilentFrame(Uint8List pcm, int start, int end) {
    final data = ByteData.sublistView(pcm, start, end);
    final n = (end - start) ~/ 2;
    if (n == 0) return true;
    double sum = 0;
    for (var i = 0; i < n; i++) {
      final s = data.getInt16(i * 2, Endian.little).toDouble();
      sum += s * s;
    }
    return math.sqrt(sum / n) < _silenceAmplitude;
  }

  Uint8List _silence(int ms) => Uint8List(sampleRate * ms ~/ 1000 * 2);

  /// Trims leading silence of a segment and holds trailing silence back. Held silence is only
  /// emitted (capped) if more speech follows in the same segment; at segment end it is replaced
  /// by the boundary pause.
  Uint8List _shape(_Segment seg, Uint8List pcm) {
    final fb = _frameBytes;
    final frames = (pcm.length + fb - 1) ~/ fb;
    int firstSpeech = -1, lastSpeech = -1;
    for (var f = 0; f < frames; f++) {
      final start = f * fb;
      final end = math.min(pcm.length, start + fb);
      if (!_isSilentFrame(pcm, start, end)) {
        if (firstSpeech < 0) firstSpeech = f;
        lastSpeech = f;
      }
    }

    if (firstSpeech < 0) {
      // Entire chunk is silence.
      if (seg.speechStarted) seg.heldSilence = _concat(seg.heldSilence, pcm);
      return Uint8List(0);
    }

    final keepFrames = silenceKeepMs ~/ analysisFrameMs;
    int from = 0;
    bool fadeIn = false;
    final out = BytesBuilder(copy: false);
    if (!seg.speechStarted) {
      from = math.max(0, firstSpeech - keepFrames) * fb;
      seg.speechStarted = true;
      fadeIn = true;
    } else if (seg.heldSilence != null) {
      out.add(_capInternalPause(seg.heldSilence!));
    }
    seg.heldSilence = null;

    final speechEnd = math.min(pcm.length, (lastSpeech + 1 + keepFrames) * fb);
    out.add(Uint8List.sublistView(pcm, from, speechEnd));
    if (speechEnd < pcm.length) {
      seg.heldSilence = Uint8List.fromList(Uint8List.sublistView(pcm, speechEnd));
    }

    final result = out.takeBytes();
    if (fadeIn) {
      return applyPcm16EdgeSmoothing(result, fadeIn: true, fadeOut: false, fadeSamples: 48);
    }
    return result;
  }

  Uint8List _capInternalPause(Uint8List silence) {
    final capMs = math.max(minInternalPauseMs, (maxInternalPauseMs * _pauseScale).round());
    final capBytes = sampleRate * capMs ~/ 1000 * 2;
    if (silence.length <= capBytes) return silence;
    return Uint8List.sublistView(silence, 0, capBytes);
  }

  Uint8List _concat(Uint8List? a, Uint8List b) {
    if (a == null || a.isEmpty) return Uint8List.fromList(b);
    final r = Uint8List(a.length + b.length);
    r.setRange(0, a.length, a);
    r.setRange(a.length, r.length, b);
    return r;
  }

  // ------------------------------------------------------------------ timers / logging

  void _scheduleWake(Duration after) {
    final at = clock.now().add(after);
    if (_wakeTimer != null && _wakeAt != null && !_wakeAt!.isAfter(at)) return;
    _wakeTimer?.cancel();
    _wakeAt = at;
    _wakeTimer = Timer(after, () {
      _wakeTimer = null;
      _wakeAt = null;
      _feed();
    });
  }

  void _cancelWake() {
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _wakeAt = null;
  }

  void _logSummary(_Segment seg) {
    if (seg.received == 0 && seg.dropped == 0) return;
    final unplayed = seg.received - seg.emitted - seg.dropped;
    AppLogger.info(
      'PlayoutScheduler stream summary ${seg.id}: received ${seg.received.toStringAsFixed(2)}s, '
      'played ${seg.emitted.toStringAsFixed(2)}s, dropped ${seg.dropped.toStringAsFixed(2)}s'
      '${unplayed.abs() > 0.001 ? ', unplayed ${unplayed.toStringAsFixed(2)}s' : ''}',
      tag: 'PlayoutScheduler',
    );
  }
}
