import 'package:auditorium/core/audio/audio_service.dart';
import 'package:auditorium/core/network/soniox_realtime_translation_service.dart';
import 'package:auditorium/core/network/soniox_region.dart';
import 'package:auditorium/core/storage/settings_repository.dart';
import 'package:auditorium/features/translation/api_key_setup.dart';
import 'package:auditorium/features/translation/home_screen.dart';
import 'package:auditorium/features/translation/translation_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDetector extends SonioxRegionDetector {
  _FakeDetector(this.result);
  final SonioxKeyCheck result;
  final checked = <String>[];

  @override
  Future<SonioxKeyCheck> detect(String apiKey) async {
    checked.add(apiKey);
    return result;
  }
}

void main() {
  late SettingsRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    repo = SettingsRepository();
  });

  Widget home(_FakeDetector detector) => ChangeNotifierProvider(
        create: (_) => TranslationProvider(
          settingsRepository: repo,
          translationService: SonioxRealtimeTranslationService(),
          audioService: AudioService(),
        ),
        child: MaterialApp(home: HomeScreen(settingsRepository: repo, regionDetector: detector)),
      );

  /// Pumps the setup alone, enters a key and taps OK. Returns a getter for "done".
  Future<bool Function()> submitKey(WidgetTester tester, _FakeDetector detector) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApiKeySetup(settingsRepository: repo, regionDetector: detector, onDone: () => done = true),
      ),
    ));
    await tester.enterText(find.byType(TextField), '  my-key  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    return () => done;
  }

  testWidgets('without a key the home screen shows the setup over a greyed, read-only translator', (tester) async {
    await tester.pumpWidget(home(_FakeDetector(SonioxKeyCheck.eu)));
    await tester.pumpAndSettle();
    expect(find.text('Soniox-API-Key eintragen'), findsOneWidget);
    expect(find.text('Soniox-Konto erstellen'), findsOneWidget);
    expect(find.textContaining('Region:'), findsNothing); // region hint only after a valid key
    // translator preview with language selection is shown, but not interactive
    expect(find.text('Vortrag'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Vortrag'), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
  });

  testWidgets('"Verstanden" after a valid key hides the setup and enables the translator', (tester) async {
    await tester.pumpWidget(home(_FakeDetector(SonioxKeyCheck.eu)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'eu-key');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Region: EU'), findsOneWidget);

    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();
    expect(find.text('Soniox-API-Key eintragen'), findsNothing);
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('Vortrag'), findsOneWidget);
  });

  testWidgets('phone size (360x740): setup and translator lay out without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(home(_FakeDetector(SonioxKeyCheck.us)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'us-key');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Verstanden'));
    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Übersetzung (Russisch)'), findsOneWidget);
  });

  testWidgets('OK is disabled while the field is empty', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApiKeySetup(settingsRepository: repo, regionDetector: _FakeDetector(SonioxKeyCheck.eu), onDone: () {}),
      ),
    ));
    final ok = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'OK'));
    expect(ok.onPressed, isNull);
  });

  testWidgets('EU key is checked, saved with its region and waits for "Verstanden"', (tester) async {
    final detector = _FakeDetector(SonioxKeyCheck.eu);
    final done = await submitKey(tester, detector);
    expect(detector.checked, ['my-key']);
    expect(await repo.getApiKey(), 'my-key');
    expect(await repo.getSonioxRegion(), 'eu');
    expect(find.textContaining('Region: EU'), findsOneWidget);
    expect(done(), isFalse);

    await tester.tap(find.text('Verstanden'));
    expect(done(), isTrue);
  });

  testWidgets('US key shows the US region hint above "Verstanden"', (tester) async {
    final done = await submitKey(tester, _FakeDetector(SonioxKeyCheck.us));
    expect(await repo.getSonioxRegion(), 'us');
    expect(find.textContaining('Region: USA'), findsOneWidget);
    expect(find.text('Soniox-Konto erstellen'), findsNothing);
    await tester.tap(find.text('Verstanden'));
    expect(done(), isTrue);
  });

  testWidgets('rejected key is not saved and shows an error', (tester) async {
    final done = await submitKey(tester, _FakeDetector(SonioxKeyCheck.invalid));
    expect(await repo.getApiKey(), isNull);
    expect(find.text('Soniox akzeptiert diesen API-Key nicht. Bitte prüfen.'), findsOneWidget);
    expect(find.text('Verstanden'), findsNothing);
    expect(done(), isFalse);
  });
}
