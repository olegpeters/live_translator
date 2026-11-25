import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auditorium/core/audio/audio_service.dart';
import 'package:auditorium/core/network/soniox_realtime_translation_service.dart';
import 'package:auditorium/core/storage/settings_repository.dart';
import 'package:auditorium/main.dart';

void main() {
  testWidgets('App initializes home screen title test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final settingsRepository = SettingsRepository();
    final translationService = SonioxRealtimeTranslationService();
    final audioService = AudioService();

    await tester.pumpWidget(
      MyApp(
        settingsRepository: settingsRepository,
        translationService: translationService,
        audioService: audioService,
      ),
    );

    expect(find.text('Auditorium'), findsOneWidget);
  });
}
