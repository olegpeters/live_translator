import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class OnboardTtsService {
  final FlutterTts _flutterTts;
  String _language = 'ru';
  bool _isInitialized = false;

  OnboardTtsService({FlutterTts? flutterTts})
      : _flutterTts = flutterTts ?? FlutterTts() {
    _init();
  }

  Future<void> _init() async {
    try {
      await _flutterTts.setLanguage(_language);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      if (!kIsWeb) {
        await _flutterTts.setSharedInstance(true);
      }
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardTtsService] Initialization error: $e');
      }
    }
  }

  Future<void> setLanguage(String languageCode) async {
    _language = languageCode;
    try {
      await _flutterTts.setLanguage(_language);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardTtsService] Failed to set language $languageCode: $e');
      }
    }
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (!_isInitialized) {
      await _init();
    }
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardTtsService] Speak error: $e');
      }
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardTtsService] Stop error: $e');
      }
    }
  }
}
