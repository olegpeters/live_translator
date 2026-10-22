import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../logging/app_logger.dart';

class OnboardTtsService {
  final FlutterTts _flutterTts;
  String _language = 'ru';
  bool _isInitialized = false;

  final List<String> _speechQueue = [];
  bool _isProcessingQueue = false;
  Completer<void>? _currentSpeakCompleter;

  OnboardTtsService({FlutterTts? flutterTts})
      : _flutterTts = flutterTts ?? FlutterTts() {
    _init();
  }

  String _getFormattedLanguage(String code) {
    switch (code.toLowerCase()) {
      case 'ru':
        return 'ru-RU';
      case 'en':
        return 'en-US';
      case 'es':
        return 'es-ES';
      case 'fr':
        return 'fr-FR';
      case 'uk':
        return 'uk-UA';
      default:
        return code;
    }
  }

  Future<void> _init() async {
    try {
      final formattedLang = _getFormattedLanguage(_language);
      await _flutterTts.setLanguage(formattedLang);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(true);

      _flutterTts.setCompletionHandler(() {
        _completeCurrentSpeak();
      });

      _flutterTts.setErrorHandler((msg) {
        AppLogger.error('TTS error: $msg', tag: 'OnboardTtsService');
        _completeCurrentSpeak();
      });

      _flutterTts.setCancelHandler(() {
        _completeCurrentSpeak();
      });

      if (!kIsWeb) {
        await _flutterTts.setSharedInstance(true);
      }
      _isInitialized = true;
      AppLogger.info('Onboard Android TTS initialized ($formattedLang)', tag: 'OnboardTtsService');
    } catch (e) {
      AppLogger.error('Initialization error: $e', tag: 'OnboardTtsService');
    }
  }

  void _completeCurrentSpeak() {
    final completer = _currentSpeakCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> setLanguage(String languageCode) async {
    _language = languageCode;
    try {
      final formatted = _getFormattedLanguage(_language);
      await _flutterTts.setLanguage(formatted);
      AppLogger.info('Language set to $languageCode ($formatted)', tag: 'OnboardTtsService');
    } catch (e) {
      AppLogger.error('Failed to set language $languageCode: $e', tag: 'OnboardTtsService');
    }
  }

  Future<void> speak(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    _speechQueue.add(cleanText);
    _processQueue();
  }

  void _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    if (!_isInitialized) {
      await _init();
    }

    while (_speechQueue.isNotEmpty && _isProcessingQueue) {
      final textToSpeak = _speechQueue.removeAt(0);
      final completer = Completer<void>();
      _currentSpeakCompleter = completer;

      // Generous fallback timeout based on length to prevent hanging if TTS callback drops
      final timeoutMs = ((textToSpeak.length / 6.0) * 1000).ceil() + 3000;

      try {
        final speakFuture = _flutterTts.speak(textToSpeak);

        await Future.any([
          speakFuture,
          completer.future,
          Future.delayed(Duration(milliseconds: timeoutMs)),
        ]);
      } catch (e) {
        AppLogger.error('Speak error for "$textToSpeak": $e', tag: 'OnboardTtsService');
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
        _currentSpeakCompleter = null;
      }

      // On Android native, TTS completion fires when synthesis finishes in memory buffer.
      // Adding a short inter-utterance delay prevents cutting off the ending speaker audio.
      if (!kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    _isProcessingQueue = false;
  }

  Future<void> drainQueue({Duration timeout = const Duration(seconds: 8)}) async {
    final stopwatch = Stopwatch()..start();
    while ((_speechQueue.isNotEmpty || _isProcessingQueue) &&
        stopwatch.elapsed < timeout) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> stop() async {
    _speechQueue.clear();
    _completeCurrentSpeak();
    _isProcessingQueue = false;
    try {
      await _flutterTts.stop();
    } catch (e) {
      AppLogger.error('Stop error: $e', tag: 'OnboardTtsService');
    }
  }
}
