/// User glossary for Soniox STT `context`.
///
/// One entry per line:
/// - `Begriff` -> recognition hint (`context.terms`)
/// - `Quelle = Ziel` (also `->` / `=>`) -> fixed translation (`context.translation_terms`)
class Glossary {
  final List<String> terms;
  final List<({String source, String target})> translationTerms;

  const Glossary({this.terms = const [], this.translationTerms = const []});

  bool get isEmpty => terms.isEmpty && translationTerms.isEmpty;

  static final RegExp _separator = RegExp(r'\s*(=>|->|=)\s*');

  static Glossary parse(String raw) {
    final terms = <String>[];
    final translations = <({String source, String target})>[];
    for (final line in raw.split('\n')) {
      final entry = line.trim();
      if (entry.isEmpty || entry.startsWith('#')) continue;
      final m = _separator.firstMatch(entry);
      if (m != null) {
        final source = entry.substring(0, m.start).trim();
        final target = entry.substring(m.end).trim();
        if (source.isNotEmpty && target.isNotEmpty) {
          translations.add((source: source, target: target));
          terms.add(source);
          continue;
        }
      }
      terms.add(entry);
    }
    return Glossary(terms: terms.toSet().toList(), translationTerms: translations);
  }

  /// Soniox STT `context` object, or null if empty.
  Map<String, dynamic>? toSonioxContext() {
    if (isEmpty) return null;
    return {
      if (terms.isNotEmpty) 'terms': terms,
      if (translationTerms.isNotEmpty)
        'translation_terms': [
          for (final t in translationTerms) {'source': t.source, 'target': t.target},
        ],
    };
  }
}
