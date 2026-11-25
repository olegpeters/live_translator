/// Languages offered on the home screen.
class LanguageOption {
  const LanguageOption(this.code, this.name);

  final String code;
  final String name;
}

/// Spoken language of the talk (Soniox `language_hints`); '' = automatic detection.
const sourceLanguages = [
  LanguageOption('de', 'Deutsch'),
  LanguageOption('en', 'Englisch'),
  LanguageOption('', 'Automatisch'),
];

/// Translation target languages.
const targetLanguages = [
  LanguageOption('ru', 'Russisch'),
  LanguageOption('uk', 'Ukrainisch'),
  LanguageOption('en', 'Englisch'),
  LanguageOption('es', 'Spanisch'),
  LanguageOption('fr', 'Französisch'),
];

String languageName(List<LanguageOption> options, String code) =>
    options.firstWhere((o) => o.code == code, orElse: () => LanguageOption(code, code)).name;
