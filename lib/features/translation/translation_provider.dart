import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/audio/adaptive_tts_buffer.dart';
import '../../core/audio/audio_service.dart';
import '../../core/audio/onboard_tts_service.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/soniox_realtime_translation_service.dart';
import '../../core/storage/settings_repository.dart';

class TranslationProvider extends ChangeNotifier {
  final SettingsRepository settingsRepository;
  final SonioxRealtimeTranslationService translationService;
  final AudioService audioService;
  final OnboardTtsService onboardTtsService;
  final AdaptiveTtsBuffer adaptiveTtsBuffer;

  StreamSubscription? _audioRecordSubscription;
  StreamSubscription? _audioPlaybackSubscription;
  StreamSubscription? _transcriptSubscription;
  StreamSubscription? _sourceTranscriptSubscription;
  StreamSubscription? _networkStateSubscription;
  StreamSubscription? _audioLevelSubscription;
  StreamSubscription? _bufferStatusSubscription;

  bool _isTranslating = false;
  String _statusMessage = 'Inaktiv';
  String _targetTranscript = '';
  String _sourceTranscript = '';
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
  String get targetTranscript => _targetTranscript;
  String get sourceTranscript => _sourceTranscript;
  double get audioLevel => _audioLevel;
  bool get enableSourceTranscription => _enableSourceTranscription;
  TranslationConnectionState get connectionState => _connectionState;

  double get audioInFlightSeconds => adaptiveTtsBuffer.currentBufferDurationSeconds;
  double get targetDelaySeconds => adaptiveTtsBuffer.targetDelaySeconds;
  double get currentPlaybackSpeed => adaptiveTtsBuffer.currentPlaybackSpeed;
  int get ttsOutOfOrderEvents => adaptiveTtsBuffer.outOfOrderEvents;
  bool get isPreRolling => adaptiveTtsBuffer.isPreRolling;

  TranslationProvider({
    required this.settingsRepository,
    required this.translationService,
    required this.audioService,
    OnboardTtsService? onboardTtsService,
    AdaptiveTtsBuffer? adaptiveTtsBuffer,
  })  : onboardTtsService = onboardTtsService ?? OnboardTtsService(),
        adaptiveTtsBuffer = adaptiveTtsBuffer ?? AdaptiveTtsBuffer() {
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

    _bufferStatusSubscription = adaptiveTtsBuffer.onStatusChanged.listen((_) {
      if (adaptiveTtsBuffer.hasAudioToPlay) {
        _pumpAudioFromBuffer();
      }
      notifyListeners();
    });

    _audioPlaybackSubscription =
        translationService.onAudioDelta.listen((delta) {
      if (_ttsEngine == 'soniox') {
        if (delta.measuredLatencySeconds != null && delta.measuredLatencySeconds! > 0) {
          adaptiveTtsBuffer.reportSectionLatency(delta.measuredLatencySeconds!);
        }
        adaptiveTtsBuffer.addChunk(
          SequencedAudioDelta(
            bytes: delta.bytes,
            sampleRate: delta.sampleRate,
            sequenceNumber: delta.sequenceNumber,
            streamId: delta.streamId,
            isLastInStream: delta.isLastInStream,
          ),
        );
        _pumpAudioFromBuffer();
      }
    });

    _transcriptSubscription =
        translationService.onTranscriptDelta.listen((textDelta) {
      _targetTranscript += textDelta;
      AppLogger.debug('Target transcript updated (+${textDelta.length} chars): "$textDelta"', tag: 'TranslationProvider');
      if (_ttsEngine == 'onboard') {
        _sentenceBuffer += textDelta;
        _restartSentenceInactivityTimer();
        _processSentenceBuffer(force: false);
      }
      notifyListeners();
    });

    _sourceTranscriptSubscription =
        translationService.onSourceTranscriptDelta.listen((textDelta) {
      _sourceTranscript += textDelta;
      AppLogger.debug('Source transcript updated (+${textDelta.length} chars): "$textDelta"', tag: 'TranslationProvider');
      notifyListeners();
    });

    _audioLevelSubscription = audioService.audioLevelStream.listen((level) {
      _audioLevel = level;
      notifyListeners();
    });
  }

  Future<void> _pumpAudioFromBuffer() async {
    if (adaptiveTtsBuffer.hasAudioToPlay) {
      await audioService.pumpFromBuffer(adaptiveTtsBuffer);
    }
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
    audioService.outputGain = await settingsRepository.getOutputGain();

    AppLogger.info(
      'Start translation (lang=$targetLanguage, voice=$voice, ttsEngine=$_ttsEngine, gain=${audioService.outputGain}x)',
      tag: 'TranslationProvider',
    );

    if (_ttsEngine == 'onboard') {
      await onboardTtsService.setLanguage(targetLanguage);
    }

    _targetTranscript = '';
    _sourceTranscript = '';
    _sentenceBuffer = '';
    adaptiveTtsBuffer.reset();
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
    _isStopping = true;
    _statusMessage = 'Stoppe...';
    notifyListeners();

    _sentenceInactivityTimer?.cancel();
    _sentenceInactivityTimer = null;

    adaptiveTtsBuffer.flushPreRoll();
    await _pumpAudioFromBuffer();

    await _audioRecordSubscription?.cancel();
    _audioRecordSubscription = null;

    await audioService.stopRecording();
    await translationService.gracefulStop();
    await audioService.stopPlayback();

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

  void clearTranscript() {
    _targetTranscript = '';
    _sourceTranscript = '';
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
    _sourceTranscriptSubscription?.cancel();
    _networkStateSubscription?.cancel();
    _audioLevelSubscription?.cancel();
    _bufferStatusSubscription?.cancel();
    adaptiveTtsBuffer.dispose();
    onboardTtsService.stop();
    _enableWakeLock(false);
    super.dispose();
  }
}
