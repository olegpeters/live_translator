import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/audio/audio_service.dart';
import '../../core/network/openai_realtime_translation_service.dart';
import '../../core/storage/settings_repository.dart';

class TranslationProvider extends ChangeNotifier {
  final SettingsRepository settingsRepository;
  final OpenAiRealtimeTranslationService translationService;
  final AudioService audioService;

  StreamSubscription? _audioRecordSubscription;
  StreamSubscription? _audioPlaybackSubscription;
  StreamSubscription? _transcriptSubscription;
  StreamSubscription? _networkStateSubscription;
  StreamSubscription? _audioLevelSubscription;

  bool _isTranslating = false;
  String _statusMessage = 'Inaktiv';
  String _targetTranscript = '';
  double _audioLevel = 0.0;
  TranslationConnectionState _connectionState =
      TranslationConnectionState.disconnected;

  bool get isTranslating => _isTranslating;
  String get statusMessage => _statusMessage;
  String get targetTranscript => _targetTranscript;
  double get audioLevel => _audioLevel;
  TranslationConnectionState get connectionState => _connectionState;

  TranslationProvider({
    required this.settingsRepository,
    required this.translationService,
    required this.audioService,
  }) {
    _initListeners();
  }

  void _initListeners() {
    _networkStateSubscription = translationService.onStateChanged.listen((state) {
      _connectionState = state;
      switch (state) {
        case TranslationConnectionState.connecting:
          _statusMessage = 'Verbinde mit OpenAI...';
          break;
        case TranslationConnectionState.connected:
          _statusMessage = 'Live Übersetzung aktiv';
          break;
        case TranslationConnectionState.closing:
          _statusMessage = 'Beende Übersetzung (Sätze werden verarbeitet)...';
          break;
        case TranslationConnectionState.closed:
        case TranslationConnectionState.disconnected:
          _statusMessage = 'Inaktiv';
          _isTranslating = false;
          _enableWakeLock(false);
          break;
        case TranslationConnectionState.error:
          _statusMessage = 'Verbindungsfehler';
          _isTranslating = false;
          _enableWakeLock(false);
          break;
      }
      notifyListeners();
    });

    _audioPlaybackSubscription =
        translationService.onAudioDelta.listen((pcmBytes) {
      audioService.playAudioDelta(pcmBytes);
    });

    _transcriptSubscription =
        translationService.onTranscriptDelta.listen((textDelta) {
      _targetTranscript += textDelta;
      notifyListeners();
    });

    _audioLevelSubscription = audioService.audioLevelStream.listen((level) {
      _audioLevel = level;
      notifyListeners();
    });
  }

  Future<void> startTranslation() async {
    final apiKey = await settingsRepository.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      _statusMessage = 'Fehler: Keinen API-Key in den Einstellungen hinterlegt!';
      notifyListeners();
      return;
    }

    final targetLanguage = await settingsRepository.getTargetLanguage();
    final voice = await settingsRepository.getVoice();
    final sampleRate = await settingsRepository.getSampleRate();

    _targetTranscript = '';
    _isTranslating = true;
    _statusMessage = 'Initialisiere...';
    notifyListeners();

    try {
      await _enableWakeLock(true);

      // Start network connection
      await translationService.connect(
        apiKey: apiKey.trim(),
        targetLanguage: targetLanguage,
        voice: voice,
      );

      // Start audio recording and stream chunks to network
      await audioService.startRecording(sampleRate: sampleRate);
      _audioRecordSubscription = audioService.audioStream.listen((chunk) {
        translationService.sendAudioChunk(chunk);
      });
    } catch (e) {
      _statusMessage = 'Fehler beim Starten: ${e.toString()}';
      _isTranslating = false;
      await _enableWakeLock(false);
      notifyListeners();
    }
  }

  Future<void> stopTranslation() async {
    _statusMessage = 'Stoppe...';
    notifyListeners();

    await _audioRecordSubscription?.cancel();
    _audioRecordSubscription = null;

    await audioService.stopRecording();
    await translationService.gracefulStop();
    await _enableWakeLock(false);

    _isTranslating = false;
    notifyListeners();
  }

  Future<void> _enableWakeLock(bool enable) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      // Ignore Wakelock errors on unsupported platforms
    }
  }

  void clearTranscript() {
    _targetTranscript = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _audioRecordSubscription?.cancel();
    _audioPlaybackSubscription?.cancel();
    _transcriptSubscription?.cancel();
    _networkStateSubscription?.cancel();
    _audioLevelSubscription?.cancel();
    _enableWakeLock(false);
    super.dispose();
  }
}
