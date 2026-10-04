import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

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

class AudioService {
  final AudioRecorder _recorder;
  final AudioPlayer _audioPlayer;

  StreamSubscription<Uint8List>? _recordSubscription;
  final _audioStreamController = StreamController<Uint8List>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();

  List<Uint8List>? _pcmChunkQueue;
  List<Uint8List> get _queue => _pcmChunkQueue ??= <Uint8List>[];
  bool? _isPlaying;
  bool get _playing => _isPlaying ?? false;
  set _playing(bool value) => _isPlaying = value;
  Completer<void>? _currentPlaybackCompleter;
  bool? _isRecording;

  AudioService({AudioRecorder? recorder, AudioPlayer? audioPlayer})
      : _recorder = recorder ?? AudioRecorder(),
        _audioPlayer = audioPlayer ?? AudioPlayer();

  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  bool get isRecording => _isRecording ?? false;

  Future<bool> checkAndRequestPermissions() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<void> startRecording({int sampleRate = 24000}) async {
    if (isRecording) return;

    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    );

    final stream = await _recorder.startStream(config);
    _isRecording = true;

    _recordSubscription = stream.listen((data) {
      if (!_audioStreamController.isClosed) {
        _audioStreamController.add(data);
        _calculateAudioLevel(data);
      }
    });
  }

  void _calculateAudioLevel(Uint8List pcmBytes) {
    if (pcmBytes.length < 2) return;

    // Interpret bytes as 16-bit signed integers
    int sum = 0;
    int count = pcmBytes.length ~/ 2;

    for (int i = 0; i < pcmBytes.length - 1; i += 2) {
      // Little-endian 16-bit integer
      int sample = (pcmBytes[i + 1] << 8) | pcmBytes[i];
      if (sample > 32767) sample -= 65536; // Sign extension
      sum += sample * sample;
    }

    double rms = sqrt(sum / count);
    // Normalize RMS to a range of 0.0 to 1.0
    double level = (rms / 32768.0).clamp(0.0, 1.0);
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(level);
    }
  }

  Future<void> playAudioDelta(Uint8List pcmBytes) async {
    if (pcmBytes.isEmpty) return;
    _queue.add(pcmBytes);
    _startPlaybackLoop();
  }

  void _startPlaybackLoop() {
    if (_playing) return;
    _playing = true;
    _runPlaybackLoop();
  }

  Future<void> _runPlaybackLoop() async {
    while (_playing) {
      if (_queue.isEmpty) {
        break;
      }
      final chunks = List<Uint8List>.from(_queue);
      _queue.clear();

      final int totalLength = chunks.fold(0, (sum, c) => sum + c.length);
      if (totalLength == 0) break;

      final Uint8List pcmBytes = Uint8List(totalLength);
      int offset = 0;
      for (final chunk in chunks) {
        pcmBytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      final wavBytes = pcmToWav(pcmBytes, sampleRate: 24000);
      final completer = Completer<void>();
      _currentPlaybackCompleter = completer;

      StreamSubscription? completeSub;
      try {
        completeSub = _audioPlayer.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });

        await _audioPlayer.play(BytesSource(wavBytes, mimeType: 'audio/wav'));

        // Estimated duration: 24000 samples/sec * 2 bytes/sample = 48000 bytes/sec -> 48 bytes/ms
        final durationMs = (pcmBytes.length / 48).ceil();
        await completer.future.timeout(
          Duration(milliseconds: durationMs + 800),
          onTimeout: () {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[AudioService] Playback error: $e\n$st');
        }
      } finally {
        await completeSub?.cancel();
        _currentPlaybackCompleter = null;
      }
    }
    _playing = false;
    if (_queue.isNotEmpty) {
      _startPlaybackLoop();
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording) return;
    await _recordSubscription?.cancel();
    _recordSubscription = null;
    await _recorder.stop();
    _isRecording = false;
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(0.0);
    }
  }

  Future<void> stopPlayback() async {
    _playing = false;
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
