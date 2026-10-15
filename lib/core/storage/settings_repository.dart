import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const String _keyApiKey = 'soniox_api_key';
  static const String _keyLegacyOpenAiApiKey = 'openai_api_key';
  static const String _keyVoice = 'soniox_voice';
  static const String _keyTargetLanguage = 'target_language';
  static const String _keyOutputGain = 'output_gain';
  static const String _keyEnableSourceTranscription =
      'enable_source_transcription';
  static const String _keyTtsEngine = 'tts_engine';

  /// Default audio output gain multiplier (2.0 = 200% / +6 dB amplification boost).
  static const double defaultOutputGain = 2.0;

  /// Default Soniox TTS Voice ID.
  static const String defaultVoice = 'Daniel';

  /// The Soniox realtime translation API accepts 24 kHz PCM16 mono input.
  static const int inputSampleRate = 24000;

  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;

  SettingsRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String?> getApiKey() async {
    final key = await _secureStorage.read(key: _keyApiKey);
    if (key != null && key.isNotEmpty) return key;
    return await _secureStorage.read(key: _keyLegacyOpenAiApiKey);
  }

  Future<void> setApiKey(String apiKey) async {
    await _secureStorage.write(key: _keyApiKey, value: apiKey);
  }

  Future<String> getVoice() async {
    await init();
    return _prefs?.getString(_keyVoice) ?? defaultVoice;
  }

  Future<void> setVoice(String voice) async {
    await init();
    await _prefs?.setString(_keyVoice, voice);
  }

  Future<String> getTargetLanguage() async {
    await init();
    return _prefs?.getString(_keyTargetLanguage) ?? 'ru';
  }

  Future<void> setTargetLanguage(String languageCode) async {
    await init();
    await _prefs?.setString(_keyTargetLanguage, languageCode);
  }

  Future<double> getOutputGain() async {
    await init();
    return _prefs?.getDouble(_keyOutputGain) ?? defaultOutputGain;
  }

  Future<void> setOutputGain(double gain) async {
    await init();
    await _prefs?.setDouble(_keyOutputGain, gain);
  }

  Future<bool> getEnableSourceTranscription() async {
    await init();
    return _prefs?.getBool(_keyEnableSourceTranscription) ?? false;
  }

  Future<void> setEnableSourceTranscription(bool enabled) async {
    await init();
    await _prefs?.setBool(_keyEnableSourceTranscription, enabled);
  }

  Future<String> getTtsEngine() async {
    await init();
    return _prefs?.getString(_keyTtsEngine) ?? 'soniox';
  }

  Future<void> setTtsEngine(String engine) async {
    await init();
    await _prefs?.setString(_keyTtsEngine, engine);
  }

  /// Always returns 24000.
  Future<int> getSampleRate() async {
    return inputSampleRate;
  }
}
