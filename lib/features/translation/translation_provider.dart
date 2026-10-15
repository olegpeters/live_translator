import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/audio/audio_service.dart';
import '../../core/audio/onboard_tts_service.dart';
import '../../core/network/soniox_realtime_translation_service.dart';
import '../../core/storage/settings_repository.dart';

class TranslationProvider extends ChangeNotifier {
  final SettingsRepository settingsRepository;
  final SonioxRealtimeTranslationService translationService;
  final AudioService audioService;
  final OnboardTtsService onboardTtsService;

  StreamSubscription? _audioRecordSubscription;
  StreamSubscription? _audioPlaybackSubscription;
  StreamSubscription? _transcriptSubscription;
  StreamSubscription? _sourceTranscriptSubscription;
  StreamSubscription? _networkStateSubscription;
  StreamSubscription? _audioLevelSubscription;

  bool _isTranslating = false;
  String _statusMessage = 'Inaktiv';
  String _targetTranscript = '';
  String _sourceTranscript = '';
  double _audioLevel = 0.0;
  bool _enableSourceTranscription = false;
  String _ttsEngine = 'soniox';
  String _sentenceBuffer = '';
  TranslationConnectionState _connectionState =
      TranslationConnectionState.disconnected;

  bool get isTranslating => _isTranslating;
  String get statusMessage => _statusMessage;
  String get targetTranscript => _targetTranscript;
  String get sourceTranscript => _sourceTranscript;
  double get audioLevel => _audioLevel;
  bool get enableSourceTranscription => _enableSourceTranscription;
  TranslationConnectionState get connectionState => _connectionState;

  TranslationProvider({
    required this.settingsRepository,
    required this.translationService,
    required this.audioService,
    OnboardTtsService? onboardTtsService,
  }) : onboardTtsService = onboardTtsService ?? OnboardTtsService() {
    _initListeners();
    _loadSettings();
  }

  void _loadSettings() {
    settingsRepository.getOutputGain().then((gain) {
      audioService.outputGain = gain;
    });
    settingsRepository.getEnableSourceTranscription().then((enabled) {
      _enableSourceTranscription = enabled;
      notifyListeners();
    });
    settingsRepository.getTtsEngine().then((engine) {
      _ttsEngine = engine;
    });
  }

  void _initListeners() {
    _networkStateSubscription = translationService.onStateChanged.listen((state) {
      _connectionState = state;
      switch (state) {
        case TranslationConnectionState.connecting:
          _statusMessage = 'Verbinde mit Soniox...';
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
        translationService.onAudioDelta.listen((delta) {
      if (_ttsEngine == 'soniox') {
        audioService.playAudioDelta(delta.bytes, sampleRate: delta.sampleRate);
      }
    });

    _transcriptSubscription =
        translationService.onTranscriptDelta.listen((textDelta) {
      _targetTranscript += textDelta;
      if (_ttsEngine == 'onboard') {
        _sentenceBuffer += textDelta;
        _processSentenceBuffer();
      }
      notifyListeners();
    });

    _sourceTranscriptSubscription =
        translationService.onSourceTranscriptDelta.listen((textDelta) {
      _sourceTranscript += textDelta;
      notifyListeners();
    });

    _audioLevelSubscription = audioService.audioLevelStream.listen((level) {
      _audioLevel = level;
      notifyListeners();
    });
  }

  void _processSentenceBuffer() {
    while (true) {
      int index = -1;
      for (int i = 0; i < _sentenceBuffer.length; i++) {
        final char = _sentenceBuffer[i];
        if (char == '.' || char == '!' || char == '?' || char == '\n') {
          index = i;
          break;
        }
      }
      if (index == -1) {
        if (_sentenceBuffer.length > 100) {
          int lastSpace = _sentenceBuffer.lastIndexOf(' ', 100);
          if (lastSpace != -1) {
            final sentence = _sentenceBuffer.substring(0, lastSpace + 1).trim();
            _sentenceBuffer = _sentenceBuffer.substring(lastSpace + 1);
            if (sentence.isNotEmpty) {
              onboardTtsService.speak(sentence);
            }
            continue;
          }
        }
        break;
      }

      final sentence = _sentenceBuffer.substring(0, index + 1).trim();
      _sentenceBuffer = _sentenceBuffer.substring(index + 1);
      if (sentence.isNotEmpty) {
        onboardTtsService.speak(sentence);
      }
    }
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
    _ttsEngine = await settingsRepository.getTtsEngine();
    _enableSourceTranscription =
        await settingsRepository.getEnableSourceTranscription();
    audioService.outputGain = await settingsRepository.getOutputGain();

    if (_ttsEngine == 'onboard') {
      await onboardTtsService.setLanguage(targetLanguage);
    }

    _targetTranscript = '';
    _sourceTranscript = '';
    _sentenceBuffer = '';
    _isTranslating = true;
    _statusMessage = 'Initialisiere...';
    notifyListeners();

    try {
      await _enableWakeLock(true);
      await audioService.prepareAudioForPlayback();

      // Start network connection
      await translationService.connect(
        apiKey: apiKey.trim(),
        targetLanguage: targetLanguage,
        voice: voice,
        enableSourceTranscription: _enableSourceTranscription,
      );

      // Start audio recording and stream chunks to network continuously.
      await audioService.startRecording();
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
    await audioService.stopPlayback();

    if (_ttsEngine == 'onboard') {
      final remaining = _sentenceBuffer.trim();
      if (remaining.isNotEmpty) {
        await onboardTtsService.speak(remaining);
      }
      _sentenceBuffer = '';
      await onboardTtsService.stop();
    }

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
    _sourceTranscript = '';
    _sentenceBuffer = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _audioRecordSubscription?.cancel();
    _audioPlaybackSubscription?.cancel();
    _transcriptSubscription?.cancel();
    _sourceTranscriptSubscription?.cancel();
    _networkStateSubscription?.cancel();
    _audioLevelSubscription?.cancel();
    onboardTtsService.stop();
    _enableWakeLock(false);
    super.dispose();
  }
}
