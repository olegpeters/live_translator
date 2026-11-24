import 'dart:async';

import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// Playback status reported by a [PcmOutput].
class PcmOutputStatus {
  /// Frames actually played by the device so far.
  final int playedFrames;

  /// Frames written to the device (excluding not yet handed-over queue).
  final int writtenFrames;

  /// Frames handed to the output but not yet played (device buffer + native queue).
  final int queuedFrames;

  final int sampleRate;
  final double speed;

  /// Segment (TTS stream) currently audible, if known.
  final String? segmentId;

  const PcmOutputStatus({
    required this.playedFrames,
    required this.writtenFrames,
    required this.queuedFrames,
    required this.sampleRate,
    this.speed = 1.0,
    this.segmentId,
  });

  double get queuedSeconds => queuedFrames / sampleRate;
  bool get isIdle => queuedFrames <= 0;
}

/// Continuous PCM16 mono output. Implementations must play written chunks back-to-back
/// without gaps (unlike one-shot players that reload a source per chunk).
abstract class PcmOutput {
  Stream<PcmOutputStatus> get status;

  Future<void> start({int sampleRate = 24000});

  /// Queues [pcm] behind everything written before. [segmentId] tags it for status reports.
  Future<void> write(Uint8List pcm, {required String segmentId});

  /// Pitch-preserving playback speed, applied to everything not yet played.
  Future<void> setSpeed(double speed);

  /// Drops all queued, unplayed audio.
  Future<void> flush();

  Future<void> stop();

  /// Seconds handed over but not yet played, updated locally between status events.
  double get queuedSeconds;
}

/// Android implementation backed by `PcmStreamPlayer.kt` (AudioTrack, MODE_STREAM).
class AndroidPcmStreamPlayer implements PcmOutput {
  static const _methods = MethodChannel('auditorium/pcm_player');
  static const _events = EventChannel('auditorium/pcm_player/events');

  final _statusController = StreamController<PcmOutputStatus>.broadcast();
  StreamSubscription? _eventSub;
  int _sampleRate = 24000;
  bool _started = false;

  /// Frames written by Dart since the last native status (not yet reflected there).
  int _framesSinceStatus = 0;
  PcmOutputStatus? _last;

  @override
  Stream<PcmOutputStatus> get status => _statusController.stream;

  @override
  double get queuedSeconds =>
      ((_last?.queuedFrames ?? 0) + _framesSinceStatus) / _sampleRate;

  @override
  Future<void> start({int sampleRate = 24000}) async {
    if (_started && sampleRate == _sampleRate) return;
    _sampleRate = sampleRate;
    _eventSub ??= _events.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final status = PcmOutputStatus(
        playedFrames: (event['playedFrames'] as num).toInt(),
        writtenFrames: (event['writtenFrames'] as num).toInt(),
        queuedFrames: (event['queuedFrames'] as num).toInt(),
        sampleRate: _sampleRate,
        speed: (event['speed'] as num?)?.toDouble() ?? 1.0,
        segmentId: event['segmentId'] as String?,
      );
      _last = status;
      _framesSinceStatus = 0;
      if (!_statusController.isClosed) _statusController.add(status);
    }, onError: (e) {
      AppLogger.warning('PcmStreamPlayer event error: $e', tag: 'PcmStreamPlayer');
    });
    await _methods.invokeMethod('start', {'sampleRate': sampleRate});
    _started = true;
  }

  @override
  Future<void> write(Uint8List pcm, {required String segmentId}) async {
    if (pcm.isEmpty) return;
    _framesSinceStatus += pcm.length ~/ 2;
    await _methods.invokeMethod('write', {'bytes': pcm, 'segmentId': segmentId});
  }

  @override
  Future<void> setSpeed(double speed) => _methods.invokeMethod('setSpeed', {'speed': speed});

  @override
  Future<void> flush() async {
    _framesSinceStatus = 0;
    _last = null;
    await _methods.invokeMethod('flush');
  }

  @override
  Future<void> stop() async {
    _started = false;
    _framesSinceStatus = 0;
    _last = null;
    await _methods.invokeMethod('stop');
  }
}
