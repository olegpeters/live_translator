import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../logging/app_logger.dart';

/// A chunk of translated audio with sequence tracking for reordering and jitter buffering.
class SequencedAudioDelta {
  final Uint8List bytes;
  final int sampleRate;
  final int sequenceNumber;
  final String streamId;
  final DateTime receivedAt;
  final bool isLastInStream;

  SequencedAudioDelta({
    required this.bytes,
    this.sampleRate = 24000,
    required this.sequenceNumber,
    required this.streamId,
    DateTime? receivedAt,
    this.isLastInStream = false,
  }) : receivedAt = receivedAt ?? DateTime.now();

  /// Calculates duration of this 16-bit PCM mono chunk in seconds.
  double get durationSeconds => bytes.length / (sampleRate * 2.0);
}

/// Buffer health & status report for UI display.
class AdaptiveBufferStatus {
  final double targetDelaySeconds;
  final double currentBufferDurationSeconds;
  final double currentPlaybackSpeed;
  final int outOfOrderEvents;
  final bool isPreRolling;
  final double ttsLatencySeconds;
  final bool hasRecentOutOfOrderEvent;
  final double lastLateFragmentDelaySeconds;

  const AdaptiveBufferStatus({
    required this.targetDelaySeconds,
    required this.currentBufferDurationSeconds,
    required this.currentPlaybackSpeed,
    required this.outOfOrderEvents,
    required this.isPreRolling,
    this.ttsLatencySeconds = 0.0,
    this.hasRecentOutOfOrderEvent = false,
    this.lastLateFragmentDelaySeconds = 0.0,
  });
}

/// Adaptive TTS Jitter & Reordering Buffer.
///
/// Features:
/// 1. Pre-rolls the target delay (initially 3s) before playback starts and after real underruns.
/// 2. Sorts incoming audio deltas by sequence number to fix out-of-order deliveries.
/// 3. Adjusts target delay pessimistically (up to 10s) based on section latency and out-of-order fragments.
/// 4. Slowly decays target delay (holding adapted delay for at least 30s) to maintain stability across utterances.
class AdaptiveTtsBuffer {
  static const double minTargetDelay = 3.0;      // minimum base delay
  static const double initialTargetDelay = 3.0;  // initial pre-roll buffer
  static const double maxTargetDelay = 10.0;     // 10s upper limit for real-time translation
  static const double minPlaybackSpeed = 1.0;
  static const double maxPlaybackSpeed = 2.0;    // Allow higher catch-up rate for large buffers
  static const double maxBufferCapSeconds = 30.0; // Emergency cap to prevent runaway buffer lag
  static const double speedStep = 0.05;

  /// Maximum duration (ms) to wait for a missing sequence chunk before skipping gap
  static const int maxGapWaitMs = 150;

  /// Maximum duration (ms) without new audio from the previous (not yet ended) stream
  /// before playback moves on to the next stream. Measured from the last chunk *received*
  /// for the previous stream (not from the last pop, which happens ahead of real playback).
  static const int maxStreamTransitionWaitMs = 1000;

  double _targetDelaySeconds = initialTargetDelay;
  double _currentPlaybackSpeed = minPlaybackSpeed;
  int _outOfOrderEvents = 0;
  bool _isPreRolling = true;
  bool _flushRequested = false;
  double _ttsLatencySeconds = 0.0;
  bool _hasRecentOutOfOrderEvent = false;
  double _lastLateFragmentDelaySeconds = 0.0;
  Timer? _outOfOrderFlashTimer;
  Timer? _wakeTimer;
  DateTime? _wakeAt;
  int _lastPlayedSequenceNumber = 0;
  String? _lastPlayedStreamId;
  DateTime? _lastOutOfOrderTime;

  final List<SequencedAudioDelta> _queue = [];

  /// Streams for which the final chunk (`isLastInStream`) has been received.
  final Set<String> _endedStreams = {};

  /// Highest sequence number received per stream (for per-stream gap / reorder detection).
  final Map<String, int> _lastReceivedSeq = {};

  /// Arrival time of the most recent chunk per stream.
  final Map<String, DateTime> _lastReceivedAt = {};

  /// Per-stream audio accounting (seconds) for diagnostics: [received, played, dropped].
  final Map<String, List<double>> _streamStats = {};

  List<double> _stats(String streamId) => _streamStats.putIfAbsent(streamId, () => [0.0, 0.0, 0.0]);

  void _logStreamStats(String streamId) {
    final st = _streamStats.remove(streamId);
    if (st == null) return;
    final missing = st[0] - st[1] - st[2];
    AppLogger.info(
      'AdaptiveTtsBuffer stream summary $streamId: received ${st[0].toStringAsFixed(2)}s, '
      'played ${st[1].toStringAsFixed(2)}s, dropped ${st[2].toStringAsFixed(2)}s'
      '${missing.abs() > 0.001 ? ', still queued ${missing.toStringAsFixed(2)}s' : ''}',
      tag: 'AdaptiveTtsBuffer',
    );
  }

  final _statusController = StreamController<AdaptiveBufferStatus>.broadcast();
  Stream<AdaptiveBufferStatus> get onStatusChanged => _statusController.stream;

  double get targetDelaySeconds => _targetDelaySeconds;
  double get currentPlaybackSpeed => _currentPlaybackSpeed;
  int get outOfOrderEvents => _outOfOrderEvents;
  bool get isPreRolling => _isPreRolling;
  double get ttsLatencySeconds => _ttsLatencySeconds;
  bool get hasRecentOutOfOrderEvent => _hasRecentOutOfOrderEvent;
  double get lastLateFragmentDelaySeconds => _lastLateFragmentDelaySeconds;

  /// True if any audio is queued (regardless of pre-roll or transition holds).
  bool get hasQueuedAudio => _queue.isNotEmpty;

  /// True when waiting longer cannot yield more audio for the queued content:
  /// a flush was requested, or every stream that has audio queued has already ended.
  bool get isStreamEnding =>
      _flushRequested ||
      (_queue.isNotEmpty && _queue.every((c) => _endedStreams.contains(c.streamId)));

  /// Returns total duration in seconds of currently buffered PCM audio.
  double get currentBufferDurationSeconds {
    if (_queue.isEmpty) return 0.0;
    return _queue.fold(0.0, (sum, delta) => sum + delta.durationSeconds);
  }

  AdaptiveBufferStatus get currentStatus => AdaptiveBufferStatus(
        targetDelaySeconds: _targetDelaySeconds,
        currentBufferDurationSeconds: currentBufferDurationSeconds,
        currentPlaybackSpeed: _currentPlaybackSpeed,
        outOfOrderEvents: _outOfOrderEvents,
        isPreRolling: _isPreRolling,
        ttsLatencySeconds: _ttsLatencySeconds,
        hasRecentOutOfOrderEvent: _hasRecentOutOfOrderEvent,
        lastLateFragmentDelaySeconds: _lastLateFragmentDelaySeconds,
      );

  void _notifyStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(currentStatus);
    }
  }

  /// Reset buffer state for a new translation session.
  void reset() {
    _outOfOrderFlashTimer?.cancel();
    _outOfOrderFlashTimer = null;
    _cancelWake();
    _hasRecentOutOfOrderEvent = false;
    _lastLateFragmentDelaySeconds = 0.0;
    for (final id in _streamStats.keys.toList()) {
      _logStreamStats(id);
    }
    _queue.clear();
    _endedStreams.clear();
    _lastReceivedSeq.clear();
    _lastReceivedAt.clear();
    _targetDelaySeconds = initialTargetDelay;
    _currentPlaybackSpeed = minPlaybackSpeed;
    _outOfOrderEvents = 0;
    _isPreRolling = true;
    _flushRequested = false;
    _ttsLatencySeconds = 0.0;
    _lastPlayedSequenceNumber = 0;
    _lastPlayedStreamId = null;
    _lastOutOfOrderTime = null;
    _notifyStatus();
  }

  /// Pessimistically adapts target delay to the measured latency of the last audio section/utterance.
  void reportSectionLatency(double latencySeconds) {
    if (latencySeconds <= 0) return;
    _ttsLatencySeconds = latencySeconds;
    // Add small safety margin (+0.2s) above measured section latency
    final proposedTarget = math.min(
      maxTargetDelay,
      math.max(minTargetDelay, latencySeconds + 0.2),
    );
    if (proposedTarget > _targetDelaySeconds) {
      _targetDelaySeconds = proposedTarget;
    }
    _notifyStatus();
  }

  /// Adds a new audio delta chunk to the adaptive buffer.
  /// Reorders out-of-order chunks and adapts buffer delay or speed.
  void addChunk(SequencedAudioDelta delta) {
    // Drop audio whose position was already played (or whose stream playback already left).
    // Inserting it would play past audio out-of-order ("time-warp" glitch).
    if (delta.bytes.isNotEmpty &&
        _lastPlayedSequenceNumber > 0 &&
        delta.sequenceNumber <= _lastPlayedSequenceNumber) {
      _stats(delta.streamId)[0] += delta.durationSeconds;
      _stats(delta.streamId)[2] += delta.durationSeconds;
      _handleOutOfOrderEvent(delta);
      AppLogger.warning(
        'AdaptiveTtsBuffer dropping stale late chunk seq=${delta.sequenceNumber} <= lastPlayed=$_lastPlayedSequenceNumber (stream=${delta.streamId})',
        tag: 'AdaptiveTtsBuffer',
      );
      _notifyStatus();
      return;
    }

    if (delta.isLastInStream) {
      _endedStreams.add(delta.streamId);
    }

    if (delta.bytes.isNotEmpty) {
      _stats(delta.streamId)[0] += delta.durationSeconds;
      // Out-of-order / gap detection is done per stream. Chunks of different streams
      // legitimately interleave (stream N tail overlaps stream N+1 head) and are not anomalies.
      final lastSeq = _lastReceivedSeq[delta.streamId];
      if (lastSeq != null) {
        if (delta.sequenceNumber <= lastSeq || delta.sequenceNumber > lastSeq + 1) {
          _handleOutOfOrderEvent(delta);
        }
      }
      if (lastSeq == null || delta.sequenceNumber > lastSeq) {
        _lastReceivedSeq[delta.streamId] = delta.sequenceNumber;
      }
      _lastReceivedAt[delta.streamId] = delta.receivedAt;

      // Insert in sorted order by sequenceNumber (search from tail: in-order arrival is the common case)
      int insertIndex = _queue.length;
      while (insertIndex > 0 && _queue[insertIndex - 1].sequenceNumber > delta.sequenceNumber) {
        insertIndex--;
      }
      _queue.insert(insertIndex, delta);
    }

    _updatePreRoll();
    _evaluateSpeedAndPacing();
    _notifyStatus();
  }

  /// Ends pre-roll once enough audio is buffered, or once waiting cannot help anymore.
  ///
  /// Pre-roll completes when:
  /// - buffered audio >= target delay, or
  /// - a flush was requested (translation stopping), or
  /// - all queued streams have ended AND the oldest queued chunk already waited the target delay
  ///   (keeps the configured latency, giving the next utterance time to build up buffer), or
  /// - the oldest queued chunk waited [maxTargetDelay] (safety net, e.g. lost end marker).
  void _updatePreRoll() {
    if (!_isPreRolling) return;
    if (_queue.isEmpty) {
      if (_flushRequested) _isPreRolling = false;
      return;
    }

    final buffered = currentBufferDurationSeconds;
    final waitedSeconds = DateTime.now().difference(_oldestReceivedAt()).inMilliseconds / 1000.0;

    String? reason;
    if (buffered >= _targetDelaySeconds) {
      reason = 'buffered ${buffered.toStringAsFixed(2)}s >= target ${_targetDelaySeconds.toStringAsFixed(2)}s';
    } else if (_flushRequested) {
      reason = 'flush requested';
    } else if (isStreamEnding && waitedSeconds >= _targetDelaySeconds) {
      reason = 'all queued streams ended, waited ${waitedSeconds.toStringAsFixed(2)}s';
    } else if (waitedSeconds >= maxTargetDelay) {
      reason = 'max wait ${maxTargetDelay}s exceeded';
    }

    if (reason != null) {
      _isPreRolling = false;
      AppLogger.info('AdaptiveTtsBuffer pre-roll complete ($reason)', tag: 'AdaptiveTtsBuffer');
      return;
    }

    // Wake up later so the time-based conditions are re-evaluated even if no new chunk arrives.
    final waitTarget = isStreamEnding ? _targetDelaySeconds : maxTargetDelay;
    final remainingMs = ((waitTarget - waitedSeconds) * 1000).ceil();
    _scheduleWake(Duration(milliseconds: math.max(1, remainingMs)));
  }

  DateTime _oldestReceivedAt() {
    var oldest = _queue.first.receivedAt;
    for (final c in _queue) {
      if (c.receivedAt.isBefore(oldest)) oldest = c.receivedAt;
    }
    return oldest;
  }

  void _scheduleWake(Duration after) {
    final at = DateTime.now().add(after);
    if (_wakeTimer != null && _wakeAt != null && !_wakeAt!.isAfter(at)) return;
    _wakeTimer?.cancel();
    _wakeAt = at;
    _wakeTimer = Timer(after, () {
      _wakeTimer = null;
      _wakeAt = null;
      _updatePreRoll();
      _notifyStatus();
    });
  }

  void _cancelWake() {
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _wakeAt = null;
  }

  /// Immediately adjusts safety buffer delay upon out-of-order or late fragment detection.
  void _handleOutOfOrderEvent(SequencedAudioDelta delta) {
    _outOfOrderEvents++;
    _lastOutOfOrderTime = DateTime.now();
    _hasRecentOutOfOrderEvent = true;

    _outOfOrderFlashTimer?.cancel();
    _outOfOrderFlashTimer = Timer(const Duration(milliseconds: 500), () {
      _hasRecentOutOfOrderEvent = false;
      _notifyStatus();
    });

    // Immediately reset playback rate to 1.0x to avoid skipping audio during delay spike
    _currentPlaybackSpeed = minPlaybackSpeed;

    _lastLateFragmentDelaySeconds = delta.durationSeconds;

    // Estimate the size of the anomaly from the per-stream sequence distance
    final lastSeq = _lastReceivedSeq[delta.streamId];
    final int seqGap = lastSeq == null ? 1 : math.max(1, (lastSeq - delta.sequenceNumber).abs());
    double estimatedGapDuration = math.min(seqGap, 20) * 0.1; // ~100ms per missing frame estimate
    double newTarget = math.min(
      maxTargetDelay,
      math.max(_targetDelaySeconds + 0.1, _targetDelaySeconds + estimatedGapDuration),
    );

    AppLogger.warning(
      'AdaptiveTtsBuffer out-of-order chunk seq=${delta.sequenceNumber} stream=${delta.streamId} (gap=$seqGap); target delay adapted ${_targetDelaySeconds.toStringAsFixed(2)}s -> ${newTarget.toStringAsFixed(2)}s',
      tag: 'AdaptiveTtsBuffer',
    );

    _targetDelaySeconds = newTarget;
  }

  /// Re-arms pre-roll after a real playback underrun (player idle and buffer drained),
  /// so playback resumes only once the target delay is buffered again.
  void rearmPreRoll() {
    if (_flushRequested || _isPreRolling) return;
    if (currentBufferDurationSeconds < _targetDelaySeconds) {
      _isPreRolling = true;
      AppLogger.info(
        'AdaptiveTtsBuffer playback underrun (${currentBufferDurationSeconds.toStringAsFixed(2)}s < ${_targetDelaySeconds.toStringAsFixed(2)}s); re-arming pre-roll',
        tag: 'AdaptiveTtsBuffer',
      );
      _updatePreRoll();
      _notifyStatus();
    }
  }

  /// Force flush pre-roll (e.g. when translation is stopping); stays active until [reset].
  void flushPreRoll() {
    _flushRequested = true;
    if (_isPreRolling) {
      _isPreRolling = false;
      AppLogger.info('AdaptiveTtsBuffer pre-roll force flushed', tag: 'AdaptiveTtsBuffer');
    }
    _notifyStatus();
  }

  /// Returns how long popping must still be held for the current queue head, or null if it may pop now.
  Duration? _remainingHold(DateTime now) {
    final candidate = _queue.first;

    // 1. Sequence gap within the same stream: give the missing chunk a moment to arrive
    if (_lastPlayedStreamId == candidate.streamId &&
        candidate.sequenceNumber > _lastPlayedSequenceNumber + 1) {
      final waitedMs = now.difference(candidate.receivedAt).inMilliseconds;
      if (waitedMs < maxGapWaitMs) {
        return Duration(milliseconds: maxGapWaitMs - waitedMs);
      }
    }

    // 2. Stream transition: don't start stream N+1 while stream N is still delivering audio
    final prev = _lastPlayedStreamId;
    if (prev != null && prev != candidate.streamId && !_endedStreams.contains(prev)) {
      final lastPrevAt = _lastReceivedAt[prev];
      if (lastPrevAt != null) {
        final idleMs = now.difference(lastPrevAt).inMilliseconds;
        if (idleMs < maxStreamTransitionWaitMs) {
          return Duration(milliseconds: maxStreamTransitionWaitMs - idleMs);
        }
      }
    }
    return null;
  }

  /// Determines whether audio is ready to be popped for playback.
  bool get hasAudioToPlay {
    if (_queue.isEmpty || _isPreRolling) return false;
    final hold = _remainingHold(DateTime.now());
    if (hold != null) {
      // Make sure a status event fires when the hold expires, so the pump is restarted.
      _scheduleWake(hold + const Duration(milliseconds: 1));
      return false;
    }
    return true;
  }

  /// Retrieves next audio chunk to play, updating tracking metadata.
  SequencedAudioDelta? popNextChunk() {
    if (!hasAudioToPlay) return null;

    final chunk = _queue.removeAt(0);
    _stats(chunk.streamId)[1] += chunk.durationSeconds;

    if (_lastPlayedStreamId == chunk.streamId &&
        chunk.sequenceNumber > _lastPlayedSequenceNumber + 1) {
      AppLogger.warning(
        'AdaptiveTtsBuffer sequence gap timeout ($maxGapWaitMs ms); skipping ${chunk.sequenceNumber - _lastPlayedSequenceNumber - 1} missing chunk(s)',
        tag: 'AdaptiveTtsBuffer',
      );
    }

    if (_lastPlayedStreamId != null && _lastPlayedStreamId != chunk.streamId) {
      _pruneStreamState(keep: chunk.streamId);
    }
    if (chunk.sequenceNumber > _lastPlayedSequenceNumber) {
      _lastPlayedSequenceNumber = chunk.sequenceNumber;
    }
    _lastPlayedStreamId = chunk.streamId;

    _evaluateSpeedAndPacing();
    _notifyStatus();

    return chunk;
  }

  /// Drops bookkeeping for streams that playback has moved past.
  void _pruneStreamState({required String keep}) {
    final live = {keep, ..._queue.map((c) => c.streamId)};
    for (final id in _streamStats.keys.where((id) => !live.contains(id)).toList()) {
      _logStreamStats(id);
    }
    _lastReceivedSeq.removeWhere((id, _) => !live.contains(id));
    _lastReceivedAt.removeWhere((id, _) => !live.contains(id));
    _endedStreams.removeWhere((id) => !live.contains(id));
  }

  /// Evaluates and adjusts playback speed based on buffer depth and sequence stability.
  void _evaluateSpeedAndPacing() {
    if (_isPreRolling || _queue.isEmpty) {
      _currentPlaybackSpeed = minPlaybackSpeed;
      return;
    }


    // Decay _targetDelaySeconds back toward minTargetDelay when no recent out-of-order event
    if (_lastOutOfOrderTime != null) {
      final elapsedSinceAnomaly = DateTime.now().difference(_lastOutOfOrderTime!);
      if (elapsedSinceAnomaly >= const Duration(seconds: 1)) {
        if (_targetDelaySeconds > minTargetDelay) {
          _targetDelaySeconds = math.max(
            minTargetDelay,
            _targetDelaySeconds - 0.01,
          );
        }
      } else {
        // Hold speed at 1.0x briefly (< 1s) during active out-of-order gap recovery
        // unless buffer is significantly above target delay (+2.0s)
        if (currentBufferDurationSeconds <= _targetDelaySeconds + 2.0) {
          _currentPlaybackSpeed = minPlaybackSpeed;
          return;
        }
      }
    } else if (_targetDelaySeconds > minTargetDelay) {
      _targetDelaySeconds = math.max(
        minTargetDelay,
        _targetDelaySeconds - 0.01,
      );
    }

    final double bufferedDuration = currentBufferDurationSeconds;
    final double excessBuffer = bufferedDuration - _targetDelaySeconds;

    if (excessBuffer <= 0.2) {
      _currentPlaybackSpeed = minPlaybackSpeed;
    } else {
      // Proportional speed scaling based on excess buffer duration above target delay:
      // excess 0.2s .. 2.0s -> 1.05x .. 1.25x
      // excess 2.0s .. 5.0s -> 1.25x .. 1.50x
      // excess 5.0s .. 15.0s -> 1.50x .. 2.00x
      if (excessBuffer <= 2.0) {
        _currentPlaybackSpeed = 1.0 + (excessBuffer / 2.0) * 0.25;
      } else if (excessBuffer <= 5.0) {
        _currentPlaybackSpeed = 1.25 + ((excessBuffer - 2.0) / 3.0) * 0.25;
      } else {
        _currentPlaybackSpeed = math.min(
          maxPlaybackSpeed,
          1.50 + ((excessBuffer - 5.0) / 10.0) * 0.50,
        );
      }
    }
  }


  void dispose() {
    _outOfOrderFlashTimer?.cancel();
    _cancelWake();
    _queue.clear();
    _statusController.close();
  }
}
