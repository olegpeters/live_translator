import 'package:auditorium/core/audio/audio_service.dart';
import 'package:auditorium/core/network/soniox_realtime_translation_service.dart';
import 'package:auditorium/core/storage/settings_repository.dart';
import 'package:auditorium/core/translation/glossary.dart';
import 'package:auditorium/features/translation/translation_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Microphone refused by the user; records whether recording was attempted anyway.
class _DeniedMicAudioService extends AudioService {
  var recordingStarted = false;

  @override
  Future<bool> checkAndRequestPermissions() async => false;

  @override
  Future<void> startRecording() async => recordingStarted = true;
}

class _NoConnectService extends SonioxRealtimeTranslationService {
  var connected = false;

  @override
  Future<void> connect({
    required String apiKey,
    required String targetLanguage,
    String voice = 'Daniel',
    bool enableSourceTranscription = false,
    bool newSession = true,
    String? sourceLanguage,
    Glossary glossary = const Glossary(),
    SonioxRegion? region,
    bool speechEnabled = true,
  }) async => connected = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The audio plugins (record, audioplayers) have no implementation in unit tests.
  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      'com.llfbandit.record/messages',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(MethodChannel(channel), null));
    }
  });

  test('denied microphone: nothing is started (Android 14+ would kill a mic foreground service)', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final repo = SettingsRepository();
    await repo.setApiKey('my-key');
    await repo.setSonioxRegion('eu');
    final audio = _DeniedMicAudioService();
    final network = _NoConnectService();
    final provider = TranslationProvider(settingsRepository: repo, translationService: network, audioService: audio);

    await provider.startTranslation();

    expect(provider.status, TranslationStatus.micPermissionDenied);
    expect(provider.isTranslating, isFalse);
    expect(network.connected, isFalse);
    expect(audio.recordingStarted, isFalse);
  });
}
