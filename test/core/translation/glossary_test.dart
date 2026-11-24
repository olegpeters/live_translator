import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:auditorium/core/translation/glossary.dart';

void main() {
  test('parses terms and translation pairs into Soniox context', () {
    final g = Glossary.parse('Aaron\n# Kommentar\n\nAnbetung = поклонение\nGottesdienst -> богослужение\nAaron');
    expect(g.terms, ['Aaron', 'Anbetung', 'Gottesdienst']);
    expect(g.toSonioxContext(), {
      'terms': ['Aaron', 'Anbetung', 'Gottesdienst'],
      'translation_terms': [
        {'source': 'Anbetung', 'target': 'поклонение'},
        {'source': 'Gottesdienst', 'target': 'богослужение'},
      ],
    });
  });

  test('empty glossary yields no context', () {
    expect(Glossary.parse('  \n').toSonioxContext(), isNull);
  });

  test('sections: shared terms + general + only the target language pairs', () {
    const raw = '[general]\ndomain = Predigt\n[terms]\nSabbat\n[ru]\nSabbat = суббота\n[en]\nSabbat = Sabbath\n';
    final ru = Glossary.parse(raw, targetLanguage: 'ru');
    expect(ru.terms, ['Sabbat']);
    expect(ru.translationTerms.single.target, 'суббота');
    expect(ru.general.single, (key: 'domain', value: 'Predigt'));

    final es = Glossary.parse(raw, targetLanguage: 'es');
    expect(es.translationTerms, isEmpty);
    expect(es.terms, ['Sabbat']);
  });

  test('merge: union of terms, free-text pairs override preset pairs', () {
    final preset = Glossary.parse('[ru]\nSabbat = суббота\nHeiligtum = святилище', targetLanguage: 'ru');
    final user = Glossary.parse('Sabbat = Шаббат\nGottesdienst', targetLanguage: 'ru');
    final merged = preset.merge(user);
    expect(merged.terms, containsAll(['Sabbat', 'Heiligtum', 'Gottesdienst']));
    expect(merged.terms.where((t) => t == 'Sabbat'), hasLength(1));
    final sabbat = merged.translationTerms.firstWhere((t) => t.source == 'Sabbat');
    expect(sabbat.target, 'Шаббат');
  });

  test('bundled sermon preset parses and stays well below the Soniox context limit', () {
    final raw = File('assets/glossary/adventist_sermon.txt').readAsStringSync();
    for (final lang in ['ru', 'en', 'uk', 'es', 'fr']) {
      final g = Glossary.parse(raw, targetLanguage: lang);
      expect(g.terms.length, greaterThan(150), reason: lang);
      expect(g.general, isNotEmpty);
      expect(g.estimatedTokens, lessThan(6000), reason: lang);
    }
    final ru = Glossary.parse(raw, targetLanguage: 'ru');
    expect(ru.translationTerms.firstWhere((t) => t.source == 'Der große Kampf').target, '«Великая борьба»');
    expect(ru.translationTerms.firstWhere((t) => t.source == 'Generalkonferenz').target, 'Генеральная Конференция');
    // ambiguous everyday words must not have fixed translations
    for (final ambiguous in ['Richter', 'Prediger', 'Sprüche', 'Römer', 'Verband', 'Vereinigung', 'Division']) {
      expect(ru.translationTerms.where((t) => t.source == ambiguous), isEmpty, reason: ambiguous);
    }
  });
}
