import 'package:auditorium/core/network/soniox_region.dart';
import 'package:auditorium/core/storage/settings_repository.dart';
import 'package:auditorium/features/translation/api_key_setup.dart';
import 'package:auditorium/features/translation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<bool> pumpSetup(WidgetTester tester, _FakeDetector detector) async {
    var saved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApiKeySetup(settingsRepository: repo, regionDetector: detector, onSaved: () => saved = true),
      ),
    ));
    await tester.enterText(find.byType(TextField), '  my-key  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    return saved;
  }

  testWidgets('home screen asks for the API key when none is stored', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(settingsRepository: repo, regionDetector: _FakeDetector(SonioxKeyCheck.eu)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Soniox-API-Key eintragen'), findsOneWidget);
    expect(find.text('Soniox-Konto erstellen'), findsOneWidget);
    expect(find.textContaining('Region:'), findsNothing); // region hint only after a valid key
  });

  testWidgets('OK is disabled while the field is empty', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApiKeySetup(settingsRepository: repo, regionDetector: _FakeDetector(SonioxKeyCheck.eu), onSaved: () {}),
      ),
    ));
    final ok = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'OK'));
    expect(ok.onPressed, isNull);
  });

  testWidgets('EU key is checked, then saved with its region', (tester) async {
    final detector = _FakeDetector(SonioxKeyCheck.eu);
    final saved = await pumpSetup(tester, detector);
    expect(detector.checked, ['my-key']);
    expect(saved, isTrue);
    expect(await repo.getApiKey(), 'my-key');
    expect(await repo.getSonioxRegion(), 'eu');
  });

  testWidgets('rejected key is not saved and shows an error', (tester) async {
    final saved = await pumpSetup(tester, _FakeDetector(SonioxKeyCheck.invalid));
    expect(saved, isFalse);
    expect(await repo.getApiKey(), isNull);
    expect(find.text('Soniox akzeptiert diesen API-Key nicht. Bitte prüfen.'), findsOneWidget);
  });

  testWidgets('US key is saved and the US region hint must be acknowledged', (tester) async {
    var saved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApiKeySetup(
          settingsRepository: repo,
          regionDetector: _FakeDetector(SonioxKeyCheck.us),
          onSaved: () => saved = true,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'us-key');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Region: USA'), findsOneWidget);
    expect(saved, isFalse); // waits for the dialog
    expect(await repo.getSonioxRegion(), 'us');

    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
  });
}
