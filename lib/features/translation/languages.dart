import '../../l10n/app_localizations.dart';

/// Spoken language of the talk (Soniox `language_hints`); '' = automatic detection.
const sourceLanguageCodes = ['', 'de', 'en'];

/// Translation target languages.
const targetLanguageCodes = ['ru', 'uk', 'en', 'de', 'es', 'fr', 'ar'];

/// Target languages written right to left.
const rtlLanguageCodes = {'ar'};

/// Localized name of a language code used on the home screen.
String languageName(AppLocalizations l, String code) => switch (code) {
      'de' => l.langGerman,
      'en' => l.langEnglish,
      'ru' => l.langRussian,
      'uk' => l.langUkrainian,
      'es' => l.langSpanish,
      'fr' => l.langFrench,
      'ar' => l.langArabic,
      '' => l.langAuto,
      _ => code,
    };
