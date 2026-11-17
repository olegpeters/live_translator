import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/audio/audio_service.dart';
import '../../core/audio/onboard_tts_service.dart';
import '../../core/audio/playout_scheduler.dart';
import '../../core/audio/wav_file_writer.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/android_platform.dart';
import '../../core/network/soniox_realtime_translation_service.dart';
import '../../core/storage/settings_repository.dart';
import '../../core/translation/glossary.dart';
import 'transcript_model.dart';

class TranslationProvider extends ChangeNotifier {
  final SettingsRepository settingsRepository;
  final SonioxRealtimeTranslationService translationService;
  final AudioService audioService;
  final OnboardTtsService onboardTtsService;
  final PlayoutScheduler playoutScheduler;

  StreamSubscription? _audioRecordSubscription;
  WavFileWriter? _micRecorder;
  StreamSubscription? _audioPlaybackSubscription;
  StreamSubscription? _transcriptSubscription;
  StreamSubscription? _transcriptUpdateSubscription;
  StreamSubscription? _networkStateSubscription;
  StreamSubscription? _audioLevelSubscription;
  StreamSubscription? _bufferStatusSubscription;
  DateTime _lastStatusNotify = DateTime.fromMillisecondsSinceEpoch(0);

  bool _isTranslating = false;
  String _statusMessage = 'Inaktiv';
  final TranscriptModel _targetTranscript = TranscriptModel();
  final TranscriptModel _sourceTranscript = TranscriptModel();
  double _audioLevel = 0.0;
  bool _enableSourceTranscription = false;
  String _ttsEngine = 'soniox';
  String _sentenceBuffer = '';
  Timer? _sentenceInactivityTimer;
  TranslationConnectionState _connectionState =
      TranslationConnectionState.disconnected;
  int _reconnectAttempts = 0;
  bool _isStopping = false;

  bool get isTranslating => _isTranslating;
  String get statusMessage => _statusMessage;
  String get targetTranscript => _targetTranscript.text;
  String get sourceTranscript => _sourceTranscript.text;
  double get audioLevel => _audioLevel;
  bool get enableSourceTranscription => _enableSourceTranscription;
  TranslationConnectionState get connectionState => _connectionState;

  double get phoneBufferSeconds =>
      playoutScheduler.backlogSeconds;
  double get audioInFlightSeconds => phoneBufferSeconds;
  double get targetDelaySeconds => playoutScheduler.targetDelaySeconds;
  double get currentPlaybackSpeed => playoutScheduler.currentPlaybackSpeed;
  int get ttsOutOfOrderEvents => playoutScheduler.outOfOrderEvents;
  bool get hasRecentOutOfOrderEvent => playoutScheduler.hasRecentOutOfOrderEvent;
  double get ttsLatencySeconds => playoutScheduler.ttsLatencySeconds;
  double get lastLateFragmentDelaySeconds => playoutScheduler.lastLateFragmentDelaySeconds;
  double get translationLatencySeconds => translationService.translationLatencySeconds;
  bool get isPreRolling => playoutScheduler.isPreRolling;

  TranslationProvider({
    required this.settingsRepository,
    required this.translationService,
    required this.audioService,
    OnboardTtsService? onboardTtsService,
    PlayoutScheduler? playoutScheduler,
  })  : onboardTtsService = onboardTtsService ?? OnboardTtsService(),
        playoutScheduler = playoutScheduler ?? PlayoutScheduler(output: audioService.createPcmOutput()) {
    audioService.isPlaybackActive = () => this.playoutScheduler.backlogSeconds > 0;
    _initListeners();
    _loadSettings();
  }

  void _loadSettings() {
    settingsRepository.getOutputGain().then((gain) {
      playoutScheduler.outputGain = gain;
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
          if (_isTranslating && !_isStopping) {
            _handleUnexpectedDisconnect();
          } else {
            _statusMessage = 'Inaktiv';
            _isTranslating = false;
            _enableWakeLock(false);
          }
          break;
        case TranslationConnectionState.error:
          if (_isTranslating && !_isStopping) {
            _handleUnexpectedDisconnect();
          } else {
            _statusMessage = 'Verbindungsfehler';
            _isTranslating = false;
            _enableWakeLock(false);
          }
          break;
      }
      notifyListeners();
    });

    // Playout status changes up to 20x/s; throttle UI rebuilds.
    _bufferStatusSubscription = playoutScheduler.onStatusChanged.listen((_) {
      final now = DateTime.now();
      if (now.difference(_lastStatusNotify).inMilliseconds >= 200) {
        _lastStatusNotify = now;
        notifyListeners();
      }
    });

    _audioPlaybackSubscription =
        translationService.onAudioDelta.listen((delta) {
      if (_ttsEngine == 'soniox') {
        if (delta.measuredLatencySeconds != null && delta.measuredLatencySeconds! > 0) {
          playoutScheduler.reportSectionLatency(delta.measuredLatencySeconds!);
        }
        playoutScheduler.addChunk(
          SequencedAudioDelta(
            bytes: delta.bytes,
            sampleRate: delta.sampleRate,
            sequenceNumber: delta.sequenceNumber,
            streamId: delta.streamId,
            isLastInStream: delta.isLastInStream,
            boundary: delta.boundary,
          ),
        );
      }
    });

    // Final translated text only (drives onboard TTS).
    _transcriptSubscription =
        translationService.onTranscriptDelta.listen((textDelta) {
      if (_ttsEngine == 'onboard') {
        _sentenceBuffer += textDelta;
        _restartSentenceInactivityTimer();
        _processSentenceBuffer(force: false);
      }
    });

    // UI transcripts: final text + provisional tail (no duplication of non-final tokens).
    _transcriptUpdateSubscription =
        translationService.onTranscriptUpdate.listen((update) {
      final model = update.isSource ? _sourceTranscript : _targetTranscript;
      if (update.finalText.isEmpty && update.provisionalText == model.provisionalText) return;
      model.apply(finalText: update.finalText, provisionalText: update.provisionalText);
      notifyListeners();
    });

    _audioLevelSubscription = audioService.audioLevelStream.listen((level) {
      _audioLevel = level;
      notifyListeners();
    });
  }

  void _restartSentenceInactivityTimer() {
    _sentenceInactivityTimer?.cancel();
    _sentenceInactivityTimer = Timer(const Duration(milliseconds: 1200), () {
      if (_sentenceBuffer.trim().isNotEmpty) {
        _processSentenceBuffer(force: true);
      }
    });
  }

  void _processSentenceBuffer({bool force = false}) {
    if (force) {
      _sentenceInactivityTimer?.cancel();
      _sentenceInactivityTimer = null;
      final sentence = _sentenceBuffer.trim();
      _sentenceBuffer = '';
      if (sentence.isNotEmpty) {
        onboardTtsService.speak(sentence);
      }
      return;
    }

    while (_sentenceBuffer.isNotEmpty) {
      int sentenceIndex = -1;
      for (int i = 0; i < _sentenceBuffer.length; i++) {
        final char = _sentenceBuffer[i];
        if (char == '.' || char == '!' || char == '?' || char == '\n' || char == '…') {
          sentenceIndex = i;
          break;
        }
      }

      if (sentenceIndex != -1) {
        final sentence = _sentenceBuffer.substring(0, sentenceIndex + 1).trim();
        _sentenceBuffer = _sentenceBuffer.substring(sentenceIndex + 1);
        if (sentence.isNotEmpty) {
          onboardTtsService.speak(sentence);
        }
        continue;
      }

      // Check for clause punctuation boundaries if clause has enough words or length
      int clauseIndex = -1;
      for (int i = 0; i < _sentenceBuffer.length; i++) {
        final char = _sentenceBuffer[i];
        if (char == ',' || char == ';' || char == ':' || char == '—' || char == '-' || char == '»' || char == '"') {
          final candidate = _sentenceBuffer.substring(0, i + 1).trim();
          final wordCount = candidate.split(RegExp(r'\s+')).length;
          if (wordCount >= 5 || candidate.length >= 18) {
            clauseIndex = i;
            break;
          }
        }
      }

      if (clauseIndex != -1) {
        final clause = _sentenceBuffer.substring(0, clauseIndex + 1).trim();
        _sentenceBuffer = _sentenceBuffer.substring(clauseIndex + 1);
        if (clause.isNotEmpty) {
          onboardTtsService.speak(clause);
        }
        continue;
      }

      // If buffer accumulated >= 8 words without punctuation, flush up to last space
      final words = _sentenceBuffer.trim().split(RegExp(r'\s+'));
      if (words.length >= 8) {
        int lastSpace = _sentenceBuffer.lastIndexOf(' ');
        if (lastSpace != -1) {
          final chunk = _sentenceBuffer.substring(0, lastSpace + 1).trim();
          _sentenceBuffer = _sentenceBuffer.substring(lastSpace + 1);
          if (chunk.isNotEmpty) {
            onboardTtsService.speak(chunk);
          }
          continue;
        }
      }

      break;
    }
  }

  Future<void> _handleUnexpectedDisconnect() async {
    if (!_isTranslating || _isStopping) return;

    if (_reconnectAttempts < 3) {
      _reconnectAttempts++;
      _statusMessage = 'Verbindung unterbrochen (Versuch $_reconnectAttempts/3)...';
      notifyListeners();

      await Future.delayed(Duration(seconds: _reconnectAttempts));
      if (_isTranslating && !_isStopping) {
        try {
          final apiKey = await settingsRepository.getApiKey();
          final targetLanguage = await settingsRepository.getTargetLanguage();
          final voice = await settingsRepository.getVoice();
          if (apiKey != null && apiKey.isNotEmpty) {
            await translationService.connect(
              apiKey: apiKey.trim(),
              targetLanguage: targetLanguage,
              voice: voice,
              enableSourceTranscription: _enableSourceTranscription,
              newSession: false,
              sourceLanguage: await _sourceLanguageHint(),
              glossary: await _buildGlossary(targetLanguage),
            );
            _reconnectAttempts = 0;
            return;
          }
        } catch (e) {
          AppLogger.error('Reconnect failed: $e', tag: 'TranslationProvider');
        }
      }
    }

    _statusMessage = 'Verbindung getrennt.';
    await stopTranslation();
  }

  Future<void> startTranslation() async {
    _reconnectAttempts = 0;
    _isStopping = false;

    final apiKey = await settingsRepository.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      _statusMessage = 'Fehler: Keinen API-Key in den Einstellungen hinterlegt!';
      AppLogger.warning('Start translation failed: API key missing', tag: 'TranslationProvider');
      notifyListeners();
      return;
    }

    final targetLanguage = await settingsRepository.getTargetLanguage();
    final voice = await settingsRepository.getVoice();
    _ttsEngine = await settingsRepository.getTtsEngine();
    _enableSourceTranscription =
        await settingsRepository.getEnableSourceTranscription();
    playoutScheduler.outputGain = await settingsRepository.getOutputGain();
    final voiceProcessingMode = await settingsRepository.getVoiceProcessingMode();
    final headphones = await AndroidPlatform.isHeadphoneConnected();
    audioService.voiceProcessing = switch (voiceProcessingMode) {
      'on' => true,
      'off' => false,
      _ => !headphones,
    };

    AppLogger.info(
      'Start translation (lang=$targetLanguage, voice=$voice, ttsEngine=$_ttsEngine, gain=${playoutScheduler.outputGain}x, voiceProcessing=${audioService.voiceProcessing} (mode $voiceProcessingMode, headphones=$headphones))',
      tag: 'TranslationProvider',
    );

    if (_ttsEngine == 'onboard') {
      await onboardTtsService.setLanguage(targetLanguage);
    }

    _targetTranscript.clear();
    _sourceTranscript.clear();
    _sentenceBuffer = '';
    playoutScheduler.reset();
    _isTranslating = true;
    _statusMessage = 'Initialisiere...';
    notifyListeners();

    try {
      await _enableWakeLock(true);
      await audioService.prepareAudioForPlayback();
      await playoutScheduler.start();

      // Start network connection
      await translationService.connect(
        apiKey: apiKey.trim(),
        targetLanguage: targetLanguage,
        voice: voice,
        enableSourceTranscription: _enableSourceTranscription,
        sourceLanguage: await _sourceLanguageHint(),
        glossary: await _buildGlossary(targetLanguage),
      );

      // Start audio recording and stream chunks to network continuously.
      // The foreground service keeps the mic alive with the screen off / app in background.
      if (AndroidPlatform.isAndroid) {
        // Android 13+: the service notification needs this permission (service runs either way).
        await Permission.notification.request();
      }
      await AndroidPlatform.startForegroundService();
      await audioService.startRecording();
      _micRecorder = await _openMicRecorderIfEnabled();
      _audioRecordSubscription = audioService.audioStream.listen((chunk) {
        translationService.sendAudioChunk(chunk);
        _micRecorder?.add(chunk);
      });
    } catch (e) {
      _statusMessage = 'Fehler beim Starten: ${e.toString()}';
      _isTranslating = false;
      await AndroidPlatform.stopForegroundService();
      await _enableWakeLock(false);
      notifyListeners();
    }
  }

  Future<void> stopTranslation() async {
    _isStopping = true;
    _statusMessage = 'Stoppe...';
    notifyListeners();

    _sentenceInactivityTimer?.cancel();
    _sentenceInactivityTimer = null;

    playoutScheduler.flushPreRoll();

    await _audioRecordSubscription?.cancel();
    _audioRecordSubscription = null;
    final recorder = _micRecorder;
    _micRecorder = null;
    await recorder?.close();

    await audioService.stopRecording();
    await AndroidPlatform.stopForegroundService();
    await translationService.gracefulStop();
    await playoutScheduler.stop();

    if (_ttsEngine == 'onboard') {
      _processSentenceBuffer(force: true);
      await onboardTtsService.drainQueue(timeout: const Duration(seconds: 8));
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

  /// Opens a WAV writer for the mic audio sent to STT (debug setting); keeps only the latest file.
  Future<WavFileWriter?> _openMicRecorderIfEnabled() async {
    if (kIsWeb || !await settingsRepository.getMicRecording()) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      await for (final entity in dir.list()) {
        if (entity is File && entity.uri.pathSegments.last.startsWith(WavFileWriter.filePrefix)) {
          await entity.delete();
        }
      }
      final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      return await WavFileWriter.open('${dir.path}/${WavFileWriter.filePrefix}$ts.wav',
          sampleRate: AudioService.inputSampleRate);
    } catch (e) {
      AppLogger.warning('Mic recording could not be started: $e', tag: 'TranslationProvider');
      return null;
    }
  }

  /// Preset glossary (if enabled) combined with the free-text glossary; free-text entries win.
  Future<Glossary> _buildGlossary(String targetLanguage) async {
    var glossary = const Glossary();
    if (await settingsRepository.getUseGlossaryPreset()) {
      try {
        final raw = await rootBundle.loadString(SettingsRepository.glossaryPresetAsset);
        glossary = Glossary.parse(raw, targetLanguage: targetLanguage);
      } catch (e) {
        AppLogger.warning('Glossary preset could not be loaded: $e', tag: 'TranslationProvider');
      }
    }
    final user = Glossary.parse(await settingsRepository.getGlossary(), targetLanguage: targetLanguage);
    return glossary.merge(user);
  }

  Future<String?> _sourceLanguageHint() async {
    final code = await settingsRepository.getSourceLanguage();
    return code.isEmpty ? null : code;
  }

  void clearTranscript() {
    _targetTranscript.clear();
    _sourceTranscript.clear();
    _sentenceInactivityTimer?.cancel();
    _sentenceInactivityTimer = null;
    _sentenceBuffer = '';
    onboardTtsService.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _sentenceInactivityTimer?.cancel();
    _audioRecordSubscription?.cancel();
    _audioPlaybackSubscription?.cancel();
    _transcriptSubscription?.cancel();
    _transcriptUpdateSubscription?.cancel();
    _networkStateSubscription?.cancel();
    _audioLevelSubscription?.cancel();
    _bufferStatusSubscription?.cancel();
    playoutScheduler.dispose();
    onboardTtsService.stop();
    _enableWakeLock(false);
    super.dispose();
  }
}
