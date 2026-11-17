/// Glossary for Soniox STT `context`.
///
/// Line format:
/// - `Begriff` -> recognition hint (`context.terms`)
/// - `Quelle = Ziel` (also `->` / `=>`) -> fixed translation (`context.translation_terms`);
///   the source is added to the terms as well
/// - `# ...` comment
///
/// Optional sections (used by preset files):
/// - `[general]`: `key = value` lines -> `context.general` (domain / topic description)
/// - `[terms]` / `[all]`: entries for every target language (same as no section)
/// - `[<language code>]` (e.g. `[ru]`): entries only used for that target language
class Glossary {
  final List<String> terms;
  final List<({String source, String target})> translationTerms;
  final List<({String key, String value})> general;

  const Glossary({
    this.terms = const [],
    this.translationTerms = const [],
    this.general = const [],
  });

  bool get isEmpty => terms.isEmpty && translationTerms.isEmpty && general.isEmpty;

  static final RegExp _separator = RegExp(r'\s*(=>|->|=)\s*');
  static final RegExp _section = RegExp(r'^\[([A-Za-z_-]+)\]$');

  /// Parses [raw]. Language sections other than [targetLanguage] are skipped
  /// (all language sections are skipped if [targetLanguage] is null).
  static Glossary parse(String raw, {String? targetLanguage}) {
    final terms = <String>[];
    final translations = <({String source, String target})>[];
    final general = <({String key, String value})>[];
    String section = 'terms';

    for (final line in raw.split('\n')) {
      final entry = line.trim();
      if (entry.isEmpty || entry.startsWith('#')) continue;

      final header = _section.firstMatch(entry);
      if (header != null) {
        section = header.group(1)!.toLowerCase();
        continue;
      }

      final isShared = section == 'terms' || section == 'all';
      final isGeneral = section == 'general';
      final isTargetSection = targetLanguage != null && section == targetLanguage.toLowerCase();
      if (!isShared && !isGeneral && !isTargetSection) continue;

      final m = _separator.firstMatch(entry);
      final left = m == null ? entry : entry.substring(0, m.start).trim();
      final right = m == null ? '' : entry.substring(m.end).trim();

      if (isGeneral) {
        if (left.isNotEmpty && right.isNotEmpty) general.add((key: left, value: right));
        continue;
      }
      if (m != null && left.isNotEmpty && right.isNotEmpty) {
        translations.add((source: left, target: right));
        terms.add(left);
      } else {
        terms.add(entry);
      }
    }
    return Glossary(terms: _unique(terms), translationTerms: translations, general: general);
  }

  /// Combines two glossaries. Entries of [other] win (same translation source / general key).
  Glossary merge(Glossary other) {
    final translationBySource = <String, ({String source, String target})>{
      for (final t in translationTerms) t.source.toLowerCase(): t,
      for (final t in other.translationTerms) t.source.toLowerCase(): t,
    };
    final generalByKey = <String, ({String key, String value})>{
      for (final g in general) g.key.toLowerCase(): g,
      for (final g in other.general) g.key.toLowerCase(): g,
    };
    return Glossary(
      terms: _unique([...terms, ...other.terms]),
      translationTerms: translationBySource.values.toList(),
      general: generalByKey.values.toList(),
    );
  }

  static List<String> _unique(List<String> items) {
    final seen = <String>{};
    return [
      for (final t in items)
        if (seen.add(t.toLowerCase())) t,
    ];
  }

  /// Rough size estimate (Soniox limits the whole context to 8000 tokens).
  int get estimatedTokens {
    int count(String s) => (s.length / 3).ceil() + 1;
    return terms.fold<int>(0, (n, t) => n + count(t)) +
        translationTerms.fold<int>(0, (n, t) => n + count(t.source) + count(t.target) + 2) +
        general.fold<int>(0, (n, g) => n + count(g.key) + count(g.value) + 2);
  }

  /// Soniox STT `context` object, or null if empty.
  Map<String, dynamic>? toSonioxContext() {
    if (isEmpty) return null;
    return {
      if (general.isNotEmpty)
        'general': [
          for (final g in general) {'key': g.key, 'value': g.value},
        ],
      if (terms.isNotEmpty) 'terms': terms,
      if (translationTerms.isNotEmpty)
        'translation_terms': [
          for (final t in translationTerms) {'source': t.source, 'target': t.target},
        ],
    };
  }
}
