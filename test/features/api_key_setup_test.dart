import 'package:auditorium/core/audio/audio_service.dart';
import 'package:auditorium/core/network/soniox_realtime_translation_service.dart';
import 'package:auditorium/core/network/soniox_region.dart';
import 'package:auditorium/core/storage/settings_repository.dart';
import 'package:auditorium/features/translation/api_key_setup.dart';
import 'package:auditorium/features/settings/settings_screen.dart';
import 'package:auditorium/features/translation/home_screen.dart';
import 'package:auditorium/features/translation/translation_provider.dart';
import 'package:auditorium/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home state after the user refused the microphone.
class _MicDeniedProvider extends TranslationProvider {
  _MicDeniedProvider(SettingsRepository repo)
      : super(
          settingsRepository: repo,
          translationService: SonioxRealtimeTranslationService(),
          audioService: AudioService(),
        );

  @override
  TranslationStatus get status => TranslationStatus.micPermissionDenied;
}

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

/// MaterialApp with the app's localizations (German unless [locale] is given).
MaterialApp _app({required Widget home, Locale locale = const Locale('de')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  late SettingsRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    repo = SettingsRepository();
  });

  Widget home(_FakeDetector detector, {Locale locale = const Locale('de')}) => ChangeNotifierProvider(
        create: (_) => TranslationProvider(
          settingsRepository: repo,
          translationService: SonioxRealtimeTranslationService(),
          audioService: AudioService(),
        ),
        child: _app(locale: locale, home: HomeScreen(settingsRepository: repo, regionDetector: detector)),
      );

  /// Pumps the setup alone, enters a key and taps OK. Returns a getter for "done".
  Future<bool Function()> submitKey(WidgetTester tester, _FakeDetector detector) async {
    var done = false;
    await tester.pumpWidget(_app(
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
    expect(find.byTooltip('Vortrag'), findsOneWidget);
    expect(
      find.ancestor(of: find.byTooltip('Vortrag'), matching: find.byType(IgnorePointer)),
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
    expect(find.byTooltip('Vortrag'), findsOneWidget);
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

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('home screen is translated: ${locale.languageCode}', (tester) async {
      final l = lookupAppLocalizations(locale);
      await tester.pumpWidget(home(_FakeDetector(SonioxKeyCheck.eu), locale: locale));
      await tester.pumpAndSettle();
      expect(find.text(l.setupTitle), findsOneWidget);
      expect(find.text(l.setupCreateAccount), findsOneWidget);
      expect(find.byTooltip(l.homeSourceLanguage), findsOneWidget);
      expect(find.text(l.statusIdle), findsOneWidget);
      expect(find.text(l.langAuto), findsOneWidget); // source language defaults to automatic
      expect(find.text(l.homeTranscriptTitle(l.langRussian)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('settings at phone width: ${locale.languageCode}, save top left, debug options', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l = lookupAppLocalizations(locale);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ));
      navigator.currentState!.push(MaterialPageRoute(builder: (_) => SettingsScreen(settingsRepository: repo)));
      await tester.pumpAndSettle();

      final save = find.text(l.save);
      expect(save, findsOneWidget);
      expect(tester.getTopRight(save).dx, greaterThan(250)); // top right
      expect(tester.getTopLeft(save).dy, lessThan(56));
      expect(tester.getTopLeft(find.byType(BackButton)).dx, lessThan(60)); // back top left

      expect(find.text(l.settingsTtsEngine), findsNothing);

      await tester.scrollUntilVisible(find.text(l.settingsDebugMode), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(l.settingsDebugMode));
      await tester.pumpAndSettle();
      expect(find.text(l.settingsTtsEngine), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('OK is disabled while the field is empty', (tester) async {
    await tester.pumpWidget(_app(
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

  testWidgets('denied microphone: error status and a button to the app settings', (tester) async {
    await repo.setApiKey('my-key');
    final provider = _MicDeniedProvider(repo);
    await tester.pumpWidget(ChangeNotifierProvider<TranslationProvider>.value(
      value: provider,
      child: _app(home: HomeScreen(settingsRepository: repo, regionDetector: _FakeDetector(SonioxKeyCheck.eu))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kein Zugriff aufs Mikrofon'), findsOneWidget);
    expect(find.text('App-Einstellungen öffnen'), findsOneWidget);
  });

  testWidgets('glossary preset is a dropdown: empty by default, "Predigt" is saved', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(),
    ));
    navigator.currentState!.push(MaterialPageRoute(builder: (_) => SettingsScreen(settingsRepository: repo)));
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const ValueKey('glossaryPreset'));
    await tester.scrollUntilVisible(dropdown, 200, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: dropdown, matching: find.text('Keine')), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Predigt').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Bibelbücher'), findsOneWidget); // hint for the selected preset

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(await repo.getGlossaryPreset(), 'sermon');
    expect(tester.takeException(), isNull);
  });
}
