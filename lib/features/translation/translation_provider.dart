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
  StreamSubscription? _sourceTranscriptSubscription;
  StreamSubscription? _networkStateSubscription;
  StreamSubscription? _audioLevelSubscription;
  Timer? _latencyTimer;

  bool _isTranslating = false;
  String _statusMessage = 'Inaktiv';
  String _targetTranscript = '';
  String _sourceTranscript = '';
  double _audioLevel = 0.0;
  double _latencySeconds = 0.0;
  bool _enableSourceTranscription = false;
  TranslationConnectionState _connectionState =
      TranslationConnectionState.disconnected;

  bool get isTranslating => _isTranslating;
  String get statusMessage => _statusMessage;
  String get targetTranscript => _targetTranscript;
  String get sourceTranscript => _sourceTranscript;
  double get audioLevel => _audioLevel;
  double get latencySeconds => _latencySeconds;
  double get playbackRate => audioService.currentPlaybackRate;
  bool get enableSourceTranscription => _enableSourceTranscription;
  TranslationConnectionState get connectionState => _connectionState;

  TranslationProvider({
    required this.settingsRepository,
    required this.translationService,
    required this.audioService,
  }) {
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
        translationService.onAudioDelta.listen((delta) {
      audioService.playAudioDelta(delta.bytes, sampleRate: delta.sampleRate);
    });

    _transcriptSubscription =
        translationService.onTranscriptDelta.listen((textDelta) {
      _targetTranscript += textDelta;
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

  Future<void> startTranslation() async {
    final apiKey = await settingsRepository.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      _statusMessage = 'Fehler: Keinen API-Key in den Einstellungen hinterlegt!';
      notifyListeners();
      return;
    }

    final targetLanguage = await settingsRepository.getTargetLanguage();
    _enableSourceTranscription =
        await settingsRepository.getEnableSourceTranscription();
    audioService.outputGain = await settingsRepository.getOutputGain();

    _targetTranscript = '';
    _sourceTranscript = '';
    _isTranslating = true;
    _statusMessage = 'Initialisiere...';
    notifyListeners();

    try {
      await _enableWakeLock(true);

      // Start network connection
      await translationService.connect(
        apiKey: apiKey.trim(),
        targetLanguage: targetLanguage,
        enableSourceTranscription: _enableSourceTranscription,
      );

      // Start audio recording and stream chunks to network continuously.
      await audioService.startRecording();
      _audioRecordSubscription = audioService.audioStream.listen((chunk) {
        translationService.sendAudioChunk(chunk);
      });
      _startLatencyTimer();
    } catch (e) {
      _statusMessage = 'Fehler beim Starten: ${e.toString()}';
      _isTranslating = false;
      _stopLatencyTimer();
      await _enableWakeLock(false);
      notifyListeners();
    }
  }

  Future<void> stopTranslation() async {
    _statusMessage = 'Stoppe...';
    _stopLatencyTimer();
    notifyListeners();

    await _audioRecordSubscription?.cancel();
    _audioRecordSubscription = null;

    await audioService.stopRecording();
    await translationService.gracefulStop();
    await _enableWakeLock(false);

    _isTranslating = false;
    notifyListeners();
  }

  void _startLatencyTimer() {
    _latencyTimer?.cancel();
    _latencyTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final currentLatency = audioService.currentBufferDurationSeconds;
      if ((currentLatency - _latencySeconds).abs() > 0.05 ||
          (currentLatency == 0.0 && _latencySeconds > 0.0)) {
        _latencySeconds = currentLatency;
        notifyListeners();
      }
    });
  }

  void _stopLatencyTimer() {
    _latencyTimer?.cancel();
    _latencyTimer = null;
    _latencySeconds = 0.0;
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
    notifyListeners();
  }

  @override
  void dispose() {
    _stopLatencyTimer();
    _audioRecordSubscription?.cancel();
    _audioPlaybackSubscription?.cancel();
    _transcriptSubscription?.cancel();
    _sourceTranscriptSubscription?.cancel();
    _networkStateSubscription?.cancel();
    _audioLevelSubscription?.cancel();
    _enableWakeLock(false);
    super.dispose();
  }
}
