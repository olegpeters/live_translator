import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const String _keyApiKey = 'openai_api_key';
  static const String _keyTargetLanguage = 'target_language';
  static const String _keyVoice = 'selected_voice';
  static const String _keySampleRate = 'input_sample_rate';

  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;

  SettingsRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String?> getApiKey() async {
    return await _secureStorage.read(key: _keyApiKey);
  }

  Future<void> setApiKey(String apiKey) async {
    await _secureStorage.write(key: _keyApiKey, value: apiKey);
  }

  Future<String> getTargetLanguage() async {
    await init();
    return _prefs?.getString(_keyTargetLanguage) ?? 'ru';
  }

  Future<void> setTargetLanguage(String languageCode) async {
    await init();
    await _prefs?.setString(_keyTargetLanguage, languageCode);
  }

  Future<String> getVoice() async {
    await init();
    return _prefs?.getString(_keyVoice) ?? 'alloy';
  }

  Future<void> setVoice(String voice) async {
    await init();
    await _prefs?.setString(_keyVoice, voice);
  }

  Future<int> getSampleRate() async {
    await init();
    return _prefs?.getInt(_keySampleRate) ?? 24000;
  }

  Future<void> setSampleRate(int sampleRate) async {
    await init();
    await _prefs?.setInt(_keySampleRate, sampleRate);
  }
}
