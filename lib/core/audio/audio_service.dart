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

class _PcmChunk {
  final Uint8List bytes;
  final int sampleRate;

  const _PcmChunk(this.bytes, this.sampleRate);
}

class AudioService {
  final AudioRecorder _recorder;
  final AudioPlayer _audioPlayer;

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
            usageType: AndroidUsageType.voiceCommunication,
            audioFocus: AndroidAudioFocus.gainTransient,
            audioMode: AndroidAudioMode.inCommunication,
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioService] Failed to set audio context: $e');
      }
    }
  }

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
        audioSource: AndroidAudioSource.voiceCommunication,
        audioManagerMode: AudioManagerMode.modeInCommunication,
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
          if (kDebugMode) {
            debugPrint('[AudioService] Recording stream error: $error');
          }
          _handleRecordingError();
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint('[AudioService] Recording stream done');
          }
          _handleRecordingError();
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioService] Failed to start recording stream: $e');
      }
      _handleRecordingError();
      rethrow;
    }
  }

  void _handleRecordingError() {
    if (isRecording) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (isRecording) {
          _startStreamInternal().catchError((e) {
            if (kDebugMode) {
              debugPrint('[AudioService] Error restarting recording stream: $e');
            }
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

  Future<void> playAudioDelta(Uint8List pcmBytes,
      {int sampleRate = inputSampleRate}) async {
    if (pcmBytes.isEmpty) {
      _flushRequested = true;
      _startPlaybackLoop();
      return;
    }
    _queue.add(_PcmChunk(pcmBytes, sampleRate));
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

      final int sampleRate = _queue.first.sampleRate;

      // Jitter buffer: wait briefly for more chunks if queue is under minBatchBytes
      if (!_flushRequested) {
        int totalQueueBytes = _queue
            .where((c) => c.sampleRate == sampleRate)
            .fold(0, (sum, c) => sum + c.bytes.length);

        int waitedMs = 0;
        const waitStepMs = 20;
        const maxWaitMs = 150;

        while (_playing &&
            !_flushRequested &&
            _queue.isNotEmpty &&
            _queue.first.sampleRate == sampleRate &&
            totalQueueBytes < minBatchBytes &&
            waitedMs < maxWaitMs) {
          await Future.delayed(const Duration(milliseconds: waitStepMs));
          waitedMs += waitStepMs;
          totalQueueBytes = _queue
              .where((c) => c.sampleRate == sampleRate)
              .fold(0, (sum, c) => sum + c.bytes.length);
        }
      }

      _flushRequested = false;

      if (!_playing || _queue.isEmpty) {
        break;
      }

      // Batch consecutive chunks that share the same sample rate.
      final chunks = <Uint8List>[];
      while (_queue.isNotEmpty && _queue.first.sampleRate == sampleRate) {
        chunks.add(_queue.removeAt(0).bytes);
      }

      final int totalLength = chunks.fold(0, (sum, c) => sum + c.length);
      if (totalLength == 0) continue;

      final Uint8List pcmBytes = Uint8List(totalLength);
      int offset = 0;
      for (final chunk in chunks) {
        pcmBytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      final wavBytes = pcmToWav(pcmBytes, sampleRate: sampleRate);
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

        // Estimated duration: sampleRate samples/sec * 2 bytes/sample -> sampleRate * 2 / 1000 bytes/ms
        final durationMs = (pcmBytes.length * 1000 / (sampleRate * 2)).ceil();
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
        if (!completer.isCompleted) {
          completer.complete();
        }
        await Future.delayed(const Duration(milliseconds: 50));
      } finally {
        await completeSub?.cancel();
        _currentPlaybackCompleter = null;
      }
    }
    _playing = false;
    _flushRequested = false;

    if (_queue.isNotEmpty) {
      _startPlaybackLoop();
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
