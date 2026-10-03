import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/audio/audio_service.dart';
import 'package:live_translator/core/network/openai_realtime_translation_service.dart';
import 'package:live_translator/core/storage/settings_repository.dart';
import 'package:live_translator/main.dart';

void main() {
  testWidgets('App initializes home screen title test', (WidgetTester tester) async {
    final settingsRepository = SettingsRepository();
    final translationService = OpenAiRealtimeTranslationService();
    final audioService = AudioService();

    await tester.pumpWidget(
      MyApp(
        settingsRepository: settingsRepository,
        translationService: translationService,
        audioService: audioService,
      ),
    );

    expect(find.text('Live-Übersetzung Gottesdienst'), findsOneWidget);
  });
}
