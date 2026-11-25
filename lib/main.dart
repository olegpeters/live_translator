import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/audio/audio_service.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/error_handlers.dart';
import 'core/network/soniox_realtime_translation_service.dart';
import 'core/storage/settings_repository.dart';
import 'features/translation/home_screen.dart';
import 'features/translation/translation_provider.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();

  AppLogger.info('Auditorium gestartet', tag: 'App');

  final settingsRepository = SettingsRepository();
  await settingsRepository.init();

  final translationService = SonioxRealtimeTranslationService();
  final audioService = AudioService();

  runApp(
    MyApp(
      settingsRepository: settingsRepository,
      translationService: translationService,
      audioService: audioService,
    ),
  );
}

class MyApp extends StatelessWidget {
  final SettingsRepository settingsRepository;
  final SonioxRealtimeTranslationService translationService;
  final AudioService audioService;

  const MyApp({
    super.key,
    required this.settingsRepository,
    required this.translationService,
    required this.audioService,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TranslationProvider(
        settingsRepository: settingsRepository,
        translationService: translationService,
        audioService: audioService,
      ),
      child: MaterialApp(
        title: 'Auditorium',
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // English first: it is the fallback for device languages the app does not support.
        supportedLocales: [
          const Locale('en'),
          ...AppLocalizations.supportedLocales.where((l) => l.languageCode != 'en'),
        ],
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: HomeScreen(settingsRepository: settingsRepository),
      ),
    );
  }
}
