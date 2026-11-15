import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../logging/app_logger.dart';
import 'pcm_stream_player.dart';
import 'pcm_utils.dart';

/// Fallback [PcmOutput] for platforms without the native streaming player (e.g. Web).
///
/// Plays queued PCM as WAV batches via `audioplayers`. Every `play()` reloads the source, so
/// small gaps between batches remain; batches are ~1–2 s to keep them rare.
class AudioPlayersPcmOutput implements PcmOutput {
  static const double _minBatchSeconds = 1.0;
  static const double _maxBatchSeconds = 2.0;

  final AudioPlayer _player;
  final _statusController = StreamController<PcmOutputStatus>.broadcast();
  final List<Uint8List> _queue = [];
  int _queuedBytes = 0;
  int _sampleRate = 24000;
  double _speed = 1.0;
  bool _running = false;
  bool _playing = false;
  int _playedFrames = 0;
  int _writtenFrames = 0;
  DateTime? _batchEndsAt;
  int _batchFrames = 0;
  Timer? _statusTimer;
  Timer? _batchTimer;

  AudioPlayersPcmOutput({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  @override
  Stream<PcmOutputStatus> get status => _statusController.stream;

  double get _remainingBatchSeconds {
    final end = _batchEndsAt;
    if (end == null) return 0.0;
    final ms = end.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0.0 : ms / 1000.0 * _speed;
  }

  @override
  double get queuedSeconds => _queuedBytes / (_sampleRate * 2) + _remainingBatchSeconds;

  @override
  Future<void> start({int sampleRate = 24000}) async {
    _sampleRate = sampleRate;
    _running = true;
    _statusTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) => _emitStatus());
  }

  @override
  Future<void> write(Uint8List pcm, {required String segmentId}) async {
    if (!_running || pcm.isEmpty) return;
    _queue.add(pcm);
    _queuedBytes += pcm.length;
    _writtenFrames += pcm.length ~/ 2;
    _maybePlayNext();
  }

  void _maybePlayNext() {
    if (_playing || _queue.isEmpty) return;
    // Wait for a reasonably large batch unless the player would otherwise idle anyway.
    final queuedSecs = _queuedBytes / (_sampleRate * 2);
    if (queuedSecs < _minBatchSeconds) {
      _batchTimer?.cancel();
      _batchTimer = Timer(const Duration(milliseconds: 150), () {
        if (!_playing && _queue.isNotEmpty) _playBatch();
      });
      return;
    }
    _playBatch();
  }

  void _playBatch() {
    _batchTimer?.cancel();
    final maxBytes = (_maxBatchSeconds * _sampleRate * 2).toInt();
    final builder = BytesBuilder(copy: false);
    while (_queue.isNotEmpty && builder.length < maxBytes) {
      final c = _queue.removeAt(0);
      _queuedBytes -= c.length;
      builder.add(c);
    }
    final pcm = builder.takeBytes();
    if (pcm.isEmpty) return;
    _playing = true;
    _batchFrames = pcm.length ~/ 2;
    final durationMs = (pcm.length * 1000 / (_sampleRate * 2 * _speed)).ceil();
    _batchEndsAt = DateTime.now().add(Duration(milliseconds: durationMs));
    _player.play(BytesSource(pcmToWav(pcm, sampleRate: _sampleRate), mimeType: 'audio/wav')).catchError((Object e) {
      AppLogger.warning('AudioPlayersPcmOutput play failed: $e', tag: 'AudioPlayersPcmOutput');
    });
    // Use the computed duration rather than onPlayerComplete (fires early on Web).
    Timer(Duration(milliseconds: durationMs), () {
      _playedFrames += _batchFrames;
      _batchFrames = 0;
      _batchEndsAt = null;
      _playing = false;
      if (_running) _maybePlayNext();
    });
  }

  void _emitStatus() {
    if (!_running || _statusController.isClosed) return;
    final queuedFrames = (queuedSeconds * _sampleRate).round();
    _statusController.add(PcmOutputStatus(
      playedFrames: _playedFrames,
      writtenFrames: _writtenFrames,
      queuedFrames: queuedFrames,
      sampleRate: _sampleRate,
      speed: _speed,
    ));
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    try {
      await _player.setPlaybackRate(speed);
    } catch (_) {}
  }

  @override
  Future<void> flush() async {
    _queue.clear();
    _queuedBytes = 0;
    _batchTimer?.cancel();
    try {
      await _player.stop();
    } catch (_) {}
    _playing = false;
    _batchEndsAt = null;
  }

  @override
  Future<void> stop() async {
    await flush();
    _running = false;
    _statusTimer?.cancel();
    _statusTimer = null;
  }
}
