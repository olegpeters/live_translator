import 'package:flutter_test/flutter_test.dart';
import 'package:auditorium/core/audio/audio_service.dart';
import 'package:auditorium/core/storage/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsRepository', () {
    test('getSampleRate returns 24000 by default', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      expect(await repository.getSampleRate(), 24000);
    });

    test('getSampleRate ignores a previously stored 16 kHz value', () async {
      SharedPreferences.setMockInitialValues({'input_sample_rate': 16000});
      final repository = SettingsRepository();
      expect(await repository.getSampleRate(), 24000);
    });

    test('recording sample rate matches the API requirement', () {
      expect(AudioService.inputSampleRate, 24000);
      expect(SettingsRepository.inputSampleRate, 24000);
    });

    test('getOutputGain returns default output gain when not set', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      expect(await repository.getOutputGain(), 2.0);
    });

    test('setOutputGain and getOutputGain persist output gain value correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      await repository.setOutputGain(2.5);
      expect(await repository.getOutputGain(), 2.5);
    });

    test('getEnableSourceTranscription returns false by default', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      expect(await repository.getEnableSourceTranscription(), false);
    });

    test('setEnableSourceTranscription persists value correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      await repository.setEnableSourceTranscription(true);
      expect(await repository.getEnableSourceTranscription(raw: true), true);
    });

    test('source language defaults to automatic detection', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SettingsRepository().getSourceLanguage(), '');
    });

    test('debug options only take effect in debug mode', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      await repository.setEnableSourceTranscription(true);
      await repository.setTtsEngine('onboard');
      await repository.setVoiceProcessingMode('off');

      expect(await repository.getDebugMode(), false);
      expect(await repository.getEnableSourceTranscription(), false);
      expect(await repository.getTtsEngine(), 'soniox');
      expect(await repository.getVoiceProcessingMode(), 'auto');
      // stored values are kept for the settings screen
      expect(await repository.getTtsEngine(raw: true), 'onboard');

      await repository.setDebugMode(true);
      expect(await repository.getEnableSourceTranscription(), true);
      expect(await repository.getTtsEngine(), 'onboard');
      expect(await repository.getVoiceProcessingMode(), 'off');
    });
  });
}
