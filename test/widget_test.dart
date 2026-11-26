import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auditorium/core/audio/audio_service.dart';
import 'package:auditorium/core/network/soniox_realtime_translation_service.dart';
import 'package:auditorium/core/storage/settings_repository.dart';
import 'package:auditorium/features/splash/splash_overlay.dart';
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

    // Launch screen: gradient with the app name over the loading home screen.
    await tester.pump();
    expect(find.descendant(of: find.byType(SplashOverlay), matching: find.text('Auditorium')), findsWidgets);

    // ... then it fades out and only the home screen remains.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Auditorium'), findsOneWidget); // app bar title only
  });
}
