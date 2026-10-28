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
/// 1. Pre-rolls initial target buffer (0.8s) for smooth low-latency live audio streaming.
/// 2. Sorts incoming audio deltas by sequence number to fix out-of-order deliveries.
/// 3. Adjusts target delay pessimistically (up to 10s) based on section latency and out-of-order fragments.
/// 4. Slowly decays target delay (holding adapted delay for at least 30s) to maintain stability across utterances.
class AdaptiveTtsBuffer {
  static const double minTargetDelay = 2;      // minimum base delay
  static const double initialTargetDelay = 3;  // initial pre-roll buffer
  static const double maxTargetDelay = 10.0;     // 10s upper limit for real-time translation
  static const double rearmTargetDelay = 0.25;   // 0.25s light buffer for mid-stream recovery
  static const double minPlaybackSpeed = 1.0;
  static const double maxPlaybackSpeed = 1.3;
  static const double speedStep = 0.05;

  double _targetDelaySeconds = initialTargetDelay;
  double _currentPlaybackSpeed = minPlaybackSpeed;
  int _outOfOrderEvents = 0;
  bool _isPreRolling = true;
  bool _isStreamEnding = false;
  double _ttsLatencySeconds = 0.0;
  bool _hasRecentOutOfOrderEvent = false;
  double _lastLateFragmentDelaySeconds = 0.0;
  Timer? _outOfOrderFlashTimer;
  DateTime? _preRollStartTime;
  int _lastPlayedSequenceNumber = 0;
  DateTime? _lastOutOfOrderTime;
  String? _activeStreamId;

  final List<SequencedAudioDelta> _queue = [];
  
  final _statusController = StreamController<AdaptiveBufferStatus>.broadcast();
  Stream<AdaptiveBufferStatus> get onStatusChanged => _statusController.stream;

  double get targetDelaySeconds => _targetDelaySeconds;
  double get currentPlaybackSpeed => _currentPlaybackSpeed;
  int get outOfOrderEvents => _outOfOrderEvents;
  bool get isPreRolling => _isPreRolling;
  bool get isStreamEnding => _isStreamEnding;
  double get ttsLatencySeconds => _ttsLatencySeconds;
  bool get hasRecentOutOfOrderEvent => _hasRecentOutOfOrderEvent;
  double get lastLateFragmentDelaySeconds => _lastLateFragmentDelaySeconds;

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
    _hasRecentOutOfOrderEvent = false;
    _lastLateFragmentDelaySeconds = 0.0;
    _queue.clear();
    _targetDelaySeconds = initialTargetDelay;
    _currentPlaybackSpeed = minPlaybackSpeed;
    _outOfOrderEvents = 0;
    _isPreRolling = true;
    _isStreamEnding = false;
    _ttsLatencySeconds = 0.0;
    _preRollStartTime = null;
    _lastPlayedSequenceNumber = 0;
    _lastOutOfOrderTime = null;
    _activeStreamId = null;
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
      _lastOutOfOrderTime = DateTime.now();
    }
    _notifyStatus();
  }

  /// Adds a new audio delta chunk to the adaptive buffer.
  /// Reorders out-of-order chunks and adapts buffer delay or speed.
  void addChunk(SequencedAudioDelta delta) {
    if (delta.bytes.isEmpty) {
      if (delta.isLastInStream) {
        _isStreamEnding = true;
        if (_isPreRolling) {
          _isPreRolling = false;
          _preRollStartTime = null;
          AppLogger.info('AdaptiveTtsBuffer stream end signaled via empty chunk; pre-roll completed', tag: 'AdaptiveTtsBuffer');
          _notifyStatus();
        }
      }
      return;
    }

    // Check for stream transition
    if (_activeStreamId != delta.streamId) {
      _activeStreamId = delta.streamId;
      _isStreamEnding = delta.isLastInStream;
      if (!_isStreamEnding && currentBufferDurationSeconds < _targetDelaySeconds) {
        _isPreRolling = true;
        _preRollStartTime = null;
        AppLogger.info('AdaptiveTtsBuffer new stream ${delta.streamId}; re-arming pre-roll state', tag: 'AdaptiveTtsBuffer');
      }
    } else if (delta.isLastInStream) {
      _isStreamEnding = true;
    }

    // Detect late chunk that arrives after its sequence position was already played
    if (delta.sequenceNumber <= _lastPlayedSequenceNumber && _lastPlayedSequenceNumber > 0) {
      _handleOutOfOrderEvent(delta);
      // Place at head of queue so late audio is played next rather than lost
      _queue.insert(0, delta);
    } else {
      // Check if chunk arrived out-of-order relative to queue tail
      if (_queue.isNotEmpty && delta.sequenceNumber < _queue.last.sequenceNumber) {
        _handleOutOfOrderEvent(delta);
      } else if (_queue.isNotEmpty) {
        // Check for sequence gap within the same stream
        final lastSeq = _queue.last.sequenceNumber;
        final sameStream = (delta.sequenceNumber ~/ 1000000) == (lastSeq ~/ 1000000);
        if (sameStream && delta.sequenceNumber > lastSeq + 1) {
          _handleOutOfOrderEvent(delta);
        }
      }

      // Insert in sorted order by sequenceNumber
      int insertIndex = _queue.length;
      for (int i = 0; i < _queue.length; i++) {
        if (_queue[i].sequenceNumber > delta.sequenceNumber) {
          insertIndex = i;
          break;
        }
      }
      _queue.insert(insertIndex, delta);
    }

    // Check if pre-roll requirement is met or fallback timeout elapsed
    if (_isPreRolling) {
      if (_isStreamEnding) {
        _isPreRolling = false;
        _preRollStartTime = null;
        AppLogger.info('AdaptiveTtsBuffer stream ending; pre-roll completed immediately', tag: 'AdaptiveTtsBuffer');
      } else {
        _preRollStartTime ??= DateTime.now();
        final waitedMs = DateTime.now().difference(_preRollStartTime!).inMilliseconds;
        final requiredDelay = math.min(_targetDelaySeconds, rearmTargetDelay);
        final maxWaitMs = (requiredDelay * 1000 + 400).toInt();
        if (currentBufferDurationSeconds >= requiredDelay || waitedMs >= maxWaitMs) {
          _isPreRolling = false;
          _preRollStartTime = null;
          AppLogger.info(
            'AdaptiveTtsBuffer pre-roll complete (buffered: ${currentBufferDurationSeconds.toStringAsFixed(2)}s, waited: ${waitedMs}ms)',
            tag: 'AdaptiveTtsBuffer',
          );
        }
      }
    }

    _evaluateSpeedAndPacing();
    _notifyStatus();
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

    // Calculate required offset increase based on sequence gap and buffer state
    int lastStream = _lastPlayedSequenceNumber ~/ 1000000;
    int deltaStream = delta.sequenceNumber ~/ 1000000;
    int seqGap = (lastStream == deltaStream)
        ? math.max(1, ((_lastPlayedSequenceNumber % 1000000) - (delta.sequenceNumber % 1000000)) + 1)
        : 1;
    double estimatedGapDuration = seqGap * 0.1; // ~100ms per missing frame estimate
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

  /// Rearms pre-roll state when audio queue has drained and playback becomes idle.
  void rearmPreRoll() {
    _isStreamEnding = false;
    if (_queue.isEmpty && !_isPreRolling) {
      _isPreRolling = true;
      _preRollStartTime = null;
      AppLogger.info('AdaptiveTtsBuffer queue drained; re-arming pre-roll state', tag: 'AdaptiveTtsBuffer');
      _notifyStatus();
    }
  }

  /// Force flush pre-roll (e.g. when stream is finishing or user requested immediate playback).
  void flushPreRoll() {
    _isStreamEnding = true;
    if (_isPreRolling) {
      _isPreRolling = false;
      _preRollStartTime = null;
      AppLogger.info('AdaptiveTtsBuffer pre-roll force flushed', tag: 'AdaptiveTtsBuffer');
      _notifyStatus();
    }
  }

  /// Determines whether audio is ready to be popped for playback.
  bool get hasAudioToPlay => (!_isPreRolling || _isStreamEnding) && _queue.isNotEmpty;

  /// Retrieves next audio chunk to play, updating tracking metadata.
  SequencedAudioDelta? popNextChunk() {
    if (!hasAudioToPlay) return null;

    final chunk = _queue.removeAt(0);
    if (chunk.sequenceNumber > _lastPlayedSequenceNumber) {
      _lastPlayedSequenceNumber = chunk.sequenceNumber;
    }

    _evaluateSpeedAndPacing();
    _notifyStatus();

    return chunk;
  }

  /// Evaluates and adjusts playback speed based on buffer depth and sequence stability.
  void _evaluateSpeedAndPacing() {
    if (_isPreRolling || _queue.isEmpty) {
      _currentPlaybackSpeed = minPlaybackSpeed;
      return;
    }

    // Slowly decay _targetDelaySeconds back toward minTargetDelay ONLY if network has been stable for > 30s
    if (_lastOutOfOrderTime != null) {
      final elapsedSinceAnomaly = DateTime.now().difference(_lastOutOfOrderTime!);
      if (elapsedSinceAnomaly >= const Duration(seconds: 5)) {
        if (_targetDelaySeconds > minTargetDelay) {
          _targetDelaySeconds = math.max(
            minTargetDelay,
            _targetDelaySeconds - 0.005,
          );
        }
      } else {
        _currentPlaybackSpeed = minPlaybackSpeed;
        return;
      }
    } else if (_targetDelaySeconds > minTargetDelay) {
      _targetDelaySeconds = math.max(
        minTargetDelay,
        _targetDelaySeconds - 0.005,
      );
    }

    double bufferedDuration = currentBufferDurationSeconds;

    // Accelerate catch-up playback if buffered audio exceeds target delay + 0.5s.
    // Maintain elevated speed until buffered audio catches up down to target delay (_targetDelaySeconds).
    if (bufferedDuration > _targetDelaySeconds + 0.5) {
      _currentPlaybackSpeed = math.min(
        maxPlaybackSpeed,
        _currentPlaybackSpeed + speedStep,
      );
    } else if (bufferedDuration <= _targetDelaySeconds) {
      _currentPlaybackSpeed = minPlaybackSpeed;
    } else {
      // Hysteresis buffer zone: gently step down speed as buffer approaches target delay
      if (bufferedDuration < _targetDelaySeconds + 0.2) {
        _currentPlaybackSpeed = math.max(
          minPlaybackSpeed,
          _currentPlaybackSpeed - speedStep,
        );
      }
    }
  }

  void dispose() {
    _outOfOrderFlashTimer?.cancel();
    _queue.clear();
    _statusController.close();
  }
}
