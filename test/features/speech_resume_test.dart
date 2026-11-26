import 'package:auditorium/features/translation/speech_resume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('last complete sentence plus the sentence in progress', () {
    expect(
      speechResumeText('Первое предложение. Второе предложение! Третье начинается'),
      'Второе предложение! Третье начинается',
    );
  });

  test('text ending with a complete sentence: only that sentence', () {
    expect(speechResumeText('Один. Два три. '), 'Два три.');
    expect(speechResumeText('Только одно предложение.'), 'Только одно предложение.');
  });

  test('no punctuation yet: the whole (short) text', () {
    expect(speechResumeText('мы начинаем'), 'мы начинаем');
    expect(speechResumeText(''), '');
    expect(speechResumeText('   '), '');
  });

  test('numbers like 3.5 are no sentence end', () {
    expect(speechResumeText('Версия 3.5 готова. Далее'), 'Версия 3.5 готова. Далее');
  });

  test('Arabic punctuation', () {
    expect(speechResumeText('مرحبا. كيف حالكم؟ نحن'), 'كيف حالكم؟ نحن');
  });

  test('long text without punctuation is cut at a word boundary', () {
    final words = List.generate(200, (i) => 'слово$i').join(' ');
    final result = speechResumeText(words, maxChars: 60);
    expect(result.length, lessThanOrEqualTo(60));
    expect(result.endsWith('слово199'), isTrue);
    expect(words.contains(' $result'), isTrue); // starts at a word
  });
}
