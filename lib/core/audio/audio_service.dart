import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../logging/app_logger.dart';
import 'audioplayers_pcm_output.dart';
import 'pcm_stream_player.dart';

export 'pcm_utils.dart';

class _MicStats {
  double sumSquares = 0;
  double peakRms = 0;
  int samples = 0;
  int chunks = 0;

  void add(double rms, int n) {
    sumSquares += rms * rms * n;
    samples += n;
    chunks++;
    if (rms > peakRms) peakRms = rms;
  }

  static double _db(double rms) => rms <= 0 ? -120 : 20 * log(rms / 32768.0) / ln10;
  double get avgDbfs => samples == 0 ? -120 : _db(sqrt(sumSquares / samples));
  double get peakDbfs => _db(peakRms);

  void reset() {
    sumSquares = 0;
    peakRms = 0;
    samples = 0;
    chunks = 0;
  }
}

class AudioService {
  final AudioRecorder _recorder;
  final AudioPlayer _audioPlayer;

  /// Enables OS voice processing (echo cancel, noise suppression, auto gain) on mic input.
  /// Applied when recording starts.
  bool voiceProcessing = true;

  /// Reports whether translated audio is currently being played (for mic diagnostics).
  bool Function()? isPlaybackActive;

  StreamSubscription<Uint8List>? _recordSubscription;
  final _audioStreamController = StreamController<Uint8List>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();

  bool? _isRecording;

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

  /// Creates the output for translated speech: the gapless native player on Android,
  /// an audioplayers-based fallback elsewhere.
  PcmOutput createPcmOutput() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidPcmStreamPlayer();
    }
    return AudioPlayersPcmOutput(player: _audioPlayer);
  }

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
      echoCancel: voiceProcessing,
      noiseSuppress: voiceProcessing,
      autoGain: voiceProcessing,
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

    _collectMicDiagnostics(rms, count);
  }

  // --- Mic diagnostics: compares input level while TTS playback is active vs. idle ---
  DateTime? _micDiagWindowStart;
  final _micDiag = {
    true: _MicStats(),  // playback active
    false: _MicStats(), // playback idle
  };

  void _collectMicDiagnostics(double rms, int samples) {
    final now = DateTime.now();
    _micDiagWindowStart ??= now;
    _micDiag[isPlaybackActive?.call() ?? false]!.add(rms, samples);

    if (now.difference(_micDiagWindowStart!).inMilliseconds < 2000) return;
    String fmt(_MicStats s) => s.samples == 0
        ? '-'
        : 'avg ${s.avgDbfs.toStringAsFixed(1)} dBFS, peak ${s.peakDbfs.toStringAsFixed(1)} dBFS, '
            '${(s.samples / inputSampleRate).toStringAsFixed(2)}s audio, ${s.chunks} chunks';
    AppLogger.debug(
      'MicDiag playing: [${fmt(_micDiag[true]!)}] | idle: [${fmt(_micDiag[false]!)}]',
      tag: 'AudioService',
    );
    _micDiag[true]!.reset();
    _micDiag[false]!.reset();
    _micDiagWindowStart = now;
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

  Future<void> dispose() async {
    await stopRecording();
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    _recorder.dispose();
    await _audioPlayer.dispose();
    await _audioStreamController.close();
    await _audioLevelController.close();
  }
}
