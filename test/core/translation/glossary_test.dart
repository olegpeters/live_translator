import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/translation/glossary.dart';

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
}
