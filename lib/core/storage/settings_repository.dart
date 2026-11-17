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
  static const String _keyVoiceProcessing = 'voice_processing';
  static const String _keyVoiceProcessingMode = 'voice_processing_mode';
  static const String _keyMicRecording = 'debug_mic_recording';
  static const String _keySourceLanguage = 'source_language';
  static const String _keyGlossary = 'glossary';
  static const String _keyUseGlossaryPreset = 'use_glossary_preset';

  /// Bundled glossary preset (sermon context, Seventh-day Adventist church).
  static const String glossaryPresetAsset = 'assets/glossary/adventist_sermon.txt';

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

  /// Android/OS voice processing (echo cancel, noise suppression, auto gain) on mic input:
  /// 'auto' (off with headphones, on with loudspeaker), 'on' or 'off'.
  /// Needed against echo in loudspeaker mode; with headphones it can suppress speech during playback.
  Future<String> getVoiceProcessingMode() async {
    await init();
    final mode = _prefs?.getString(_keyVoiceProcessingMode);
    if (mode != null) return mode;
    // Migrate the former on/off switch if it was set explicitly.
    final legacy = _prefs?.getBool(_keyVoiceProcessing);
    if (legacy != null) return legacy ? 'on' : 'off';
    return 'auto';
  }

  Future<void> setVoiceProcessingMode(String mode) async {
    await init();
    await _prefs?.setString(_keyVoiceProcessingMode, mode);
  }

  /// Debug: record the audio sent to STT as WAV (to analyze lost speech).
  Future<bool> getMicRecording() async {
    await init();
    return _prefs?.getBool(_keyMicRecording) ?? false;
  }

  Future<void> setMicRecording(bool enabled) async {
    await init();
    await _prefs?.setBool(_keyMicRecording, enabled);
  }

  /// Expected spoken language (Soniox `language_hints`); empty = automatic detection.
  Future<String> getSourceLanguage() async {
    await init();
    return _prefs?.getString(_keySourceLanguage) ?? 'de';
  }

  Future<void> setSourceLanguage(String code) async {
    await init();
    await _prefs?.setString(_keySourceLanguage, code);
  }

  /// Glossary lines (see `Glossary.parse`).
  Future<String> getGlossary() async {
    await init();
    return _prefs?.getString(_keyGlossary) ?? '';
  }

  Future<void> setGlossary(String glossary) async {
    await init();
    await _prefs?.setString(_keyGlossary, glossary);
  }

  /// Whether the bundled glossary preset is combined with the free-text glossary.
  Future<bool> getUseGlossaryPreset() async {
    await init();
    return _prefs?.getBool(_keyUseGlossaryPreset) ?? true;
  }

  Future<void> setUseGlossaryPreset(bool enabled) async {
    await init();
    await _prefs?.setBool(_keyUseGlossaryPreset, enabled);
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
