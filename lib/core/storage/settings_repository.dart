import 'package:flutter/foundation.dart';
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
  static const String _keySonioxRegion = 'soniox_region';
  static const String _keyDebugMode = 'debug_mode';

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

  /// Detected Soniox region of the stored API key ('eu' / 'us'); null = not detected yet.
  Future<String?> getSonioxRegion() async {
    await init();
    return _prefs?.getString(_keySonioxRegion);
  }

  Future<void> setSonioxRegion(String? code) async {
    await init();
    if (code == null) {
      await _prefs?.remove(_keySonioxRegion);
    } else {
      await _prefs?.setString(_keySonioxRegion, code);
    }
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

  /// Debug mode shows technical values and options. The options below marked
  /// "debug option" only take effect while it is on; [raw] reads the stored value
  /// regardless (settings screen).
  Future<bool> getDebugMode() async {
    await init();
    return _prefs?.getBool(_keyDebugMode) ?? false;
  }

  Future<void> setDebugMode(bool enabled) async {
    await init();
    await _prefs?.setBool(_keyDebugMode, enabled);
  }

  Future<bool> _debugOptionsActive(bool raw) async => raw || await getDebugMode();

  /// Debug option (default off).
  Future<bool> getEnableSourceTranscription({bool raw = false}) async {
    await init();
    if (!await _debugOptionsActive(raw)) return false;
    return _prefs?.getBool(_keyEnableSourceTranscription) ?? false;
  }

  Future<void> setEnableSourceTranscription(bool enabled) async {
    await init();
    await _prefs?.setBool(_keyEnableSourceTranscription, enabled);
  }

  /// Android/OS voice processing (echo cancel, noise suppression, auto gain) on mic input:
  /// 'auto' (off with headphones, on with loudspeaker), 'on' or 'off'.
  /// Needed against echo in loudspeaker mode; with headphones it can suppress speech during playback.
  /// Debug option (default 'auto').
  Future<String> getVoiceProcessingMode({bool raw = false}) async {
    await init();
    if (!await _debugOptionsActive(raw)) return 'auto';
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
  /// Never active in release builds (not declared in the store's data safety form).
  /// Debug option (default off).
  Future<bool> getMicRecording({bool raw = false}) async {
    if (kReleaseMode) return false;
    await init();
    if (!await _debugOptionsActive(raw)) return false;
    return _prefs?.getBool(_keyMicRecording) ?? false;
  }

  Future<void> setMicRecording(bool enabled) async {
    await init();
    await _prefs?.setBool(_keyMicRecording, enabled);
  }

  /// Expected spoken language (Soniox `language_hints`); empty = automatic detection.
  Future<String> getSourceLanguage() async {
    await init();
    return _prefs?.getString(_keySourceLanguage) ?? ''; // default: automatic detection
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

  /// Debug option (default 'soniox').
  Future<String> getTtsEngine({bool raw = false}) async {
    await init();
    if (!await _debugOptionsActive(raw)) return 'soniox';
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
