import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/audio/audio_service.dart';
import 'core/network/openai_realtime_translation_service.dart';
import 'core/storage/settings_repository.dart';
import 'features/translation/home_screen.dart';
import 'features/translation/translation_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsRepository = SettingsRepository();
  await settingsRepository.init();

  final translationService = OpenAiRealtimeTranslationService();
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
  final OpenAiRealtimeTranslationService translationService;
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
        title: 'Gottesdienst Live-Übersetzung',
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
