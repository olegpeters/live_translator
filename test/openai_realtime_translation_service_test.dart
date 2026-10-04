import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/network/openai_realtime_translation_service.dart';

void main() {
  group('OpenAiRealtimeTranslationService', () {
    test('initial state is disconnected', () async {
      final service = OpenAiRealtimeTranslationService();
      expect(service.currentState, TranslationConnectionState.disconnected);
      await service.dispose();
    });

    test('dispose cleans up controllers without throwing', () async {
      final service = OpenAiRealtimeTranslationService();
      await expectLater(service.dispose(), completes);
    });
  });
}
