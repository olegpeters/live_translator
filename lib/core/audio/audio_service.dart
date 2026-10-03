import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription<Uint8List>? _recordSubscription;
  final _audioStreamController = StreamController<Uint8List>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();

  bool _isRecording = false;

  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  bool get isRecording => _isRecording;

  Future<bool> checkAndRequestPermissions() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<void> startRecording({int sampleRate = 24000}) async {
    if (_isRecording) return;

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
    _audioLevelController.add(level);
  }

  Future<void> playAudioDelta(Uint8List pcmBytes) async {
    if (pcmBytes.isEmpty) return;
    try {
      // Play raw PCM audio bytes using AudioPlayer
      await _audioPlayer.play(BytesSource(pcmBytes));
    } catch (e) {
      // Audio playback buffer error handling
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    await _recordSubscription?.cancel();
    _recordSubscription = null;
    await _recorder.stop();
    _isRecording = false;
    _audioLevelController.add(0.0);
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
  }

  void dispose() {
    stopRecording();
    stopPlayback();
    _recorder.dispose();
    _audioPlayer.dispose();
    _audioStreamController.close();
    _audioLevelController.close();
  }
}
