import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// A chunk of translated audio with sequence tracking for reordering and jitter buffering.
class SequencedAudioDelta {
  final Uint8List bytes;
  final int sampleRate;
  final int sequenceNumber;
  final String streamId;
  final DateTime receivedAt;

  SequencedAudioDelta({
    required this.bytes,
    this.sampleRate = 24000,
    required this.sequenceNumber,
    required this.streamId,
    DateTime? receivedAt,
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

  const AdaptiveBufferStatus({
    required this.targetDelaySeconds,
    required this.currentBufferDurationSeconds,
    required this.currentPlaybackSpeed,
    required this.outOfOrderEvents,
    required this.isPreRolling,
  });
}

/// Adaptive TTS Jitter & Reordering Buffer.
///
/// Features:
/// 1. Pre-rolls initial 0.4 seconds (400ms) for low-latency live audio streaming.
/// 2. Sorts incoming audio deltas by sequence number to fix out-of-order deliveries.
/// 3. Adjusts target delay pessimistically (up to 1.5s) upon detecting out-of-order/late fragments.
/// 4. Gradually accelerates playback speed (up to 1.3x) when buffer level allows, to catch up with live speech.
class AdaptiveTtsBuffer {
  static const double initialTargetDelay = 0.4; // 400ms initial pre-roll for low latency
  static const double maxTargetDelay = 1.2;     // 1.2s upper limit for real-time translation
  static const double minPlaybackSpeed = 1.0;
  static const double maxPlaybackSpeed = 1.3;
  static const double speedStep = 0.05;

  double _targetDelaySeconds = initialTargetDelay;
  double _currentPlaybackSpeed = minPlaybackSpeed;
  int _outOfOrderEvents = 0;
  bool _isPreRolling = true;
  DateTime? _preRollStartTime;
  int _lastPlayedSequenceNumber = 0;
  DateTime? _lastOutOfOrderTime;

  final List<SequencedAudioDelta> _queue = [];
  
  final _statusController = StreamController<AdaptiveBufferStatus>.broadcast();
  Stream<AdaptiveBufferStatus> get onStatusChanged => _statusController.stream;

  double get targetDelaySeconds => _targetDelaySeconds;
  double get currentPlaybackSpeed => _currentPlaybackSpeed;
  int get outOfOrderEvents => _outOfOrderEvents;
  bool get isPreRolling => _isPreRolling;

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
      );

  void _notifyStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(currentStatus);
    }
  }

  /// Reset buffer state for a new translation session.
  void reset() {
    _queue.clear();
    _targetDelaySeconds = initialTargetDelay;
    _currentPlaybackSpeed = minPlaybackSpeed;
    _outOfOrderEvents = 0;
    _isPreRolling = true;
    _preRollStartTime = null;
    _lastPlayedSequenceNumber = 0;
    _lastOutOfOrderTime = null;
    _notifyStatus();
  }

  /// Adds a new audio delta chunk to the adaptive buffer.
  /// Reorders out-of-order chunks and adapts buffer delay or speed.
  void addChunk(SequencedAudioDelta delta) {
    if (delta.bytes.isEmpty) return;

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

    // Check if pre-roll requirement is met or timeout elapsed (max 250ms wait)
    if (_isPreRolling) {
      _preRollStartTime ??= DateTime.now();
      final waitedMs = DateTime.now().difference(_preRollStartTime!).inMilliseconds;
      if (currentBufferDurationSeconds >= _targetDelaySeconds || waitedMs >= 250) {
        _isPreRolling = false;
        _preRollStartTime = null;
      }
    }

    _evaluateSpeedAndPacing();
    _notifyStatus();
  }

  /// Immediately adjusts safety buffer delay upon out-of-order or late fragment detection.
  void _handleOutOfOrderEvent(SequencedAudioDelta delta) {
    _outOfOrderEvents++;
    _lastOutOfOrderTime = DateTime.now();

    // Immediately reset playback rate to 1.0x to avoid skipping audio during delay spike
    _currentPlaybackSpeed = minPlaybackSpeed;

    // Calculate required offset increase based on sequence gap and buffer state
    int seqGap = math.max(1, (_lastPlayedSequenceNumber - delta.sequenceNumber) + 1);
    double estimatedGapDuration = seqGap * 0.1; // ~100ms per missing frame estimate
    double newTarget = math.min(
      maxTargetDelay,
      math.max(_targetDelaySeconds + 0.1, _targetDelaySeconds + estimatedGapDuration),
    );

    _targetDelaySeconds = newTarget;
  }

  /// Force flush pre-roll (e.g. when stream is finishing or user requested immediate playback).
  void flushPreRoll() {
    if (_isPreRolling) {
      _isPreRolling = false;
      _preRollStartTime = null;
      _notifyStatus();
    }
  }

  /// Determines whether audio is ready to be popped for playback.
  bool get hasAudioToPlay => !_isPreRolling && _queue.isNotEmpty;

  /// Retrieves next audio chunk to play, updating tracking metadata.
  SequencedAudioDelta? popNextChunk() {
    if (!hasAudioToPlay) return null;

    final chunk = _queue.removeAt(0);
    if (chunk.sequenceNumber > _lastPlayedSequenceNumber) {
      _lastPlayedSequenceNumber = chunk.sequenceNumber;
    }

    if (_queue.isEmpty) {
      _isPreRolling = true;
      _preRollStartTime = null;
    }

    _evaluateSpeedAndPacing();
    _notifyStatus();

    return chunk;
  }

  /// Evaluates and adjusts playback speed based on buffer depth and sequence stability.
  void _evaluateSpeedAndPacing() {
    if (_isPreRolling || _queue.isEmpty) {
      return;
    }

    // Slowly decay _targetDelaySeconds back toward initialTargetDelay if network is stable
    if (_lastOutOfOrderTime != null) {
      final elapsedSinceAnomaly = DateTime.now().difference(_lastOutOfOrderTime!);
      if (elapsedSinceAnomaly >= const Duration(seconds: 3)) {
        if (_targetDelaySeconds > initialTargetDelay) {
          _targetDelaySeconds = math.max(
            initialTargetDelay,
            _targetDelaySeconds - 0.05,
          );
        }
      } else {
        _currentPlaybackSpeed = minPlaybackSpeed;
        return;
      }
    } else if (_targetDelaySeconds > initialTargetDelay) {
      _targetDelaySeconds = math.max(
        initialTargetDelay,
        _targetDelaySeconds - 0.05,
      );
    }

    double bufferedDuration = currentBufferDurationSeconds;

    // Catch up if buffered audio exceeds target delay
    if (bufferedDuration > _targetDelaySeconds + 0.3) {
      _currentPlaybackSpeed = math.min(
        maxPlaybackSpeed,
        _currentPlaybackSpeed + speedStep,
      );
    } else if (bufferedDuration <= _targetDelaySeconds) {
      _currentPlaybackSpeed = math.max(
        minPlaybackSpeed,
        _currentPlaybackSpeed - speedStep,
      );
    }
  }

  void dispose() {
    _queue.clear();
    _statusController.close();
  }
}
