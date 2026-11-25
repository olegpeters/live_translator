import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ru'),
  ];

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @understood.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get understood;

  /// No description provided for @homeSourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Talk'**
  String get homeSourceLanguage;

  /// No description provided for @homeTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get homeTargetLanguage;

  /// No description provided for @homeStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get homeStatus;

  /// No description provided for @homeTapToStart.
  ///
  /// In en, this message translates to:
  /// **'Tap to start'**
  String get homeTapToStart;

  /// No description provided for @homeTapToStop.
  ///
  /// In en, this message translates to:
  /// **'Tap to stop'**
  String get homeTapToStop;

  /// No description provided for @homeMicLevel.
  ///
  /// In en, this message translates to:
  /// **'Microphone level'**
  String get homeMicLevel;

  /// No description provided for @homeTranscriptTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation ({language})'**
  String homeTranscriptTitle(String language);

  /// No description provided for @homeClearText.
  ///
  /// In en, this message translates to:
  /// **'Clear text'**
  String get homeClearText;

  /// No description provided for @homeTranscriptPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'The translated sentences appear here live during the talk...'**
  String get homeTranscriptPlaceholder;

  /// No description provided for @homeSourceTranscriptTitle.
  ///
  /// In en, this message translates to:
  /// **'Recognized source text – diagnostics'**
  String get homeSourceTranscriptTitle;

  /// No description provided for @homeSourceTranscriptPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'The original text recognized by the model appears here...'**
  String get homeSourceTranscriptPlaceholder;

  /// No description provided for @homeBufferTitle.
  ///
  /// In en, this message translates to:
  /// **'TTS audio buffer & sync'**
  String get homeBufferTitle;

  /// No description provided for @homeBufferTempo.
  ///
  /// In en, this message translates to:
  /// **'Tempo: {speed}x'**
  String homeBufferTempo(String speed);

  /// No description provided for @homeBufferPrerolling.
  ///
  /// In en, this message translates to:
  /// **'Buffering: {buffer}s / target: {target}s...'**
  String homeBufferPrerolling(String buffer, String target);

  /// No description provided for @homeBufferStatus.
  ///
  /// In en, this message translates to:
  /// **'Buffer: {buffer}s (target: {target}s)'**
  String homeBufferStatus(String buffer, String target);

  /// No description provided for @homeBufferReorder.
  ///
  /// In en, this message translates to:
  /// **'Order adjusted ({count})'**
  String homeBufferReorder(int count);

  /// No description provided for @homeLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency: translation {translation}s  •  TTS {tts}s'**
  String homeLatency(String translation, String tts);

  /// No description provided for @statusIdle.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get statusIdle;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to Soniox...'**
  String get statusConnecting;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Live translation active'**
  String get statusActive;

  /// No description provided for @statusFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing translation (processing sentences)...'**
  String get statusFinishing;

  /// No description provided for @statusConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get statusConnectionError;

  /// No description provided for @statusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Connection lost (attempt {attempt}/{max})...'**
  String statusReconnecting(int attempt, int max);

  /// No description provided for @statusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected.'**
  String get statusDisconnected;

  /// No description provided for @statusCheckingKey.
  ///
  /// In en, this message translates to:
  /// **'Checking API key...'**
  String get statusCheckingKey;

  /// No description provided for @statusKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Error: Soniox does not accept the API key. Please check it in the settings.'**
  String get statusKeyRejected;

  /// No description provided for @statusNoApiKey.
  ///
  /// In en, this message translates to:
  /// **'Error: no API key in the settings.'**
  String get statusNoApiKey;

  /// No description provided for @statusInitializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing...'**
  String get statusInitializing;

  /// No description provided for @statusStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start: {error}'**
  String statusStartFailed(String error);

  /// No description provided for @statusStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping...'**
  String get statusStopping;

  /// No description provided for @langGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get langGerman;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get langAuto;

  /// No description provided for @langRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get langRussian;

  /// No description provided for @langUkrainian.
  ///
  /// In en, this message translates to:
  /// **'Ukrainian'**
  String get langUkrainian;

  /// No description provided for @langSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get langSpanish;

  /// No description provided for @langFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get langFrench;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Soniox API key'**
  String get setupTitle;

  /// No description provided for @setupIntro.
  ///
  /// In en, this message translates to:
  /// **'Auditorium uses Soniox for speech recognition, translation and speech output. Enter your API key to get started.'**
  String get setupIntro;

  /// No description provided for @apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Soniox API key'**
  String get apiKeyLabel;

  /// No description provided for @setupKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Soniox does not accept this API key. Please check it.'**
  String get setupKeyRejected;

  /// No description provided for @setupSavedUnchecked.
  ///
  /// In en, this message translates to:
  /// **'API key saved. It could not be checked right now (offline?); it will be checked when the translation starts.'**
  String get setupSavedUnchecked;

  /// No description provided for @setupCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Soniox account'**
  String get setupCreateAccount;

  /// No description provided for @setupLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open link: {url}'**
  String setupLinkFailed(String url);

  /// No description provided for @regionEu.
  ///
  /// In en, this message translates to:
  /// **'Region: EU – audio and text are processed in the EU.'**
  String get regionEu;

  /// No description provided for @regionUs.
  ///
  /// In en, this message translates to:
  /// **'Region: USA – audio and text are processed in the USA.'**
  String get regionUs;

  /// No description provided for @regionEuHowTo.
  ///
  /// In en, this message translates to:
  /// **'To have them processed in the EU: request the EU region in the Soniox console under “Security & compliance”, create a project in the EU region and use its API key.'**
  String get regionEuHowTo;

  /// No description provided for @settingsSonioxAccess.
  ///
  /// In en, this message translates to:
  /// **'Soniox access'**
  String get settingsSonioxAccess;

  /// No description provided for @settingsSpeechOutput.
  ///
  /// In en, this message translates to:
  /// **'Speech output'**
  String get settingsSpeechOutput;

  /// No description provided for @settingsVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get settingsVoice;

  /// No description provided for @voiceMaleDefault.
  ///
  /// In en, this message translates to:
  /// **'{name} (male, default)'**
  String voiceMaleDefault(String name);

  /// No description provided for @voiceMale.
  ///
  /// In en, this message translates to:
  /// **'{name} (male)'**
  String voiceMale(String name);

  /// No description provided for @voiceFemale.
  ///
  /// In en, this message translates to:
  /// **'{name} (female)'**
  String voiceFemale(String name);

  /// No description provided for @settingsGlossary.
  ///
  /// In en, this message translates to:
  /// **'Glossary'**
  String get settingsGlossary;

  /// No description provided for @settingsGlossaryPreset.
  ///
  /// In en, this message translates to:
  /// **'Use glossary preset “Sermon (Adventist)”'**
  String get settingsGlossaryPreset;

  /// No description provided for @settingsGlossaryPresetHint.
  ///
  /// In en, this message translates to:
  /// **'Bible books, names, Adventist terms and Ellen White book titles. Combined with your own glossary; your own entries take precedence.'**
  String get settingsGlossaryPresetHint;

  /// No description provided for @settingsOwnGlossary.
  ///
  /// In en, this message translates to:
  /// **'Own glossary (names, terms)'**
  String get settingsOwnGlossary;

  /// No description provided for @settingsOwnGlossaryHint.
  ///
  /// In en, this message translates to:
  /// **'One entry per line, e.g.\nAaron\nAnbetung = поклонение'**
  String get settingsOwnGlossaryHint;

  /// No description provided for @settingsOwnGlossaryHelper.
  ///
  /// In en, this message translates to:
  /// **'Term = recognition aid; “Source = Target” fixes the translation.'**
  String get settingsOwnGlossaryHelper;

  /// No description provided for @settingsVolume.
  ///
  /// In en, this message translates to:
  /// **'Translation volume'**
  String get settingsVolume;

  /// No description provided for @settingsGain.
  ///
  /// In en, this message translates to:
  /// **'Amplification:'**
  String get settingsGain;

  /// No description provided for @settingsGainHint.
  ///
  /// In en, this message translates to:
  /// **'Makes the spoken translation louder (100–300 %). Default: 200 %.'**
  String get settingsGainHint;

  /// No description provided for @settingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsHelp;

  /// No description provided for @settingsReportBug.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get settingsReportBug;

  /// No description provided for @settingsReportBugHint.
  ///
  /// In en, this message translates to:
  /// **'Sends the technical log (no audio, no talk text) by email to {email}. You decide in the share menu whether and how it is sent.'**
  String settingsReportBugHint(String email);

  /// No description provided for @settingsNoLogEntries.
  ///
  /// In en, this message translates to:
  /// **'No log entries yet.'**
  String get settingsNoLogEntries;

  /// No description provided for @settingsBugReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the bug report: {error}'**
  String settingsBugReportFailed(String error);

  /// No description provided for @settingsDebugMode.
  ///
  /// In en, this message translates to:
  /// **'Debug mode'**
  String get settingsDebugMode;

  /// No description provided for @settingsDebugModeHint.
  ///
  /// In en, this message translates to:
  /// **'Shows technical values (buffer, latency) and troubleshooting options. These options only take effect while debug mode is on.'**
  String get settingsDebugModeHint;

  /// No description provided for @settingsTtsEngine.
  ///
  /// In en, this message translates to:
  /// **'TTS engine (speech output)'**
  String get settingsTtsEngine;

  /// No description provided for @ttsEngineSoniox.
  ///
  /// In en, this message translates to:
  /// **'Soniox API (cloud streaming)'**
  String get ttsEngineSoniox;

  /// No description provided for @ttsEngineOnboard.
  ///
  /// In en, this message translates to:
  /// **'Onboard Android TTS (local)'**
  String get ttsEngineOnboard;

  /// No description provided for @settingsVoiceProcessing.
  ///
  /// In en, this message translates to:
  /// **'Microphone voice processing'**
  String get settingsVoiceProcessing;

  /// No description provided for @settingsVoiceProcessingHint.
  ///
  /// In en, this message translates to:
  /// **'Echo/noise suppression. Off with headphones (otherwise speech is suppressed during playback), on with the loudspeaker.'**
  String get settingsVoiceProcessingHint;

  /// No description provided for @voiceProcessingAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic (by headphones)'**
  String get voiceProcessingAuto;

  /// No description provided for @voiceProcessingOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get voiceProcessingOn;

  /// No description provided for @voiceProcessingOff.
  ///
  /// In en, this message translates to:
  /// **'Always off'**
  String get voiceProcessingOff;

  /// No description provided for @settingsSourceTranscription.
  ///
  /// In en, this message translates to:
  /// **'Source text transcription'**
  String get settingsSourceTranscription;

  /// No description provided for @settingsSourceTranscriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Recognizes and shows the original text. Only relevant for debugging/diagnostics. Default: off.'**
  String get settingsSourceTranscriptionHint;

  /// No description provided for @settingsMicRecording.
  ///
  /// In en, this message translates to:
  /// **'Microphone recording'**
  String get settingsMicRecording;

  /// No description provided for @settingsMicRecordingHint.
  ///
  /// In en, this message translates to:
  /// **'Saves the microphone audio of the last session sent to Soniox as WAV. Included in the log export. Diagnostics only.'**
  String get settingsMicRecordingHint;

  /// No description provided for @settingsAppLogs.
  ///
  /// In en, this message translates to:
  /// **'App logs ({count, plural, =1{1 entry} other{{count} entries}})'**
  String settingsAppLogs(int count);

  /// No description provided for @settingsAppLogsHint.
  ///
  /// In en, this message translates to:
  /// **'Show the session log since app start, copy it or save it as a .txt file.'**
  String get settingsAppLogsHint;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @settingsSavedKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Saved, but Soniox does not accept the API key. Please check it.'**
  String get settingsSavedKeyRejected;

  /// No description provided for @settingsSavedUs.
  ///
  /// In en, this message translates to:
  /// **'Saved. The API key belongs to a Soniox project in the USA.'**
  String get settingsSavedUs;

  /// No description provided for @settingsSavedUnchecked.
  ///
  /// In en, this message translates to:
  /// **'Saved. The API key could not be checked (offline?); it will be checked at start.'**
  String get settingsSavedUnchecked;

  /// No description provided for @logsTitle.
  ///
  /// In en, this message translates to:
  /// **'App logs ({count})'**
  String logsTitle(int count);

  /// No description provided for @logsCopyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get logsCopyTooltip;

  /// No description provided for @logsShareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save / share as text file'**
  String get logsShareTooltip;

  /// No description provided for @logsDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete log'**
  String get logsDeleteTooltip;

  /// No description provided for @logsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete log?'**
  String get logsDeleteTitle;

  /// No description provided for @logsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you really want to delete the current temporary session log?'**
  String get logsDeleteConfirm;

  /// No description provided for @logsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Log entries deleted.'**
  String get logsDeleted;

  /// No description provided for @logsCopied.
  ///
  /// In en, this message translates to:
  /// **'Entire log copied to clipboard.'**
  String get logsCopied;

  /// No description provided for @logsNothingToSave.
  ///
  /// In en, this message translates to:
  /// **'No log entries to save.'**
  String get logsNothingToSave;

  /// No description provided for @logsExported.
  ///
  /// In en, this message translates to:
  /// **'Log file exported'**
  String get logsExported;

  /// No description provided for @logsProvided.
  ///
  /// In en, this message translates to:
  /// **'Log file available at {path}'**
  String logsProvided(String path);

  /// No description provided for @logsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the log file: {error}'**
  String logsSaveFailed(String error);

  /// No description provided for @logsSessionInfo.
  ///
  /// In en, this message translates to:
  /// **'Start: {start} • Total: {count, plural, =1{1 entry} other{{count} entries}}'**
  String logsSessionInfo(String start, int count);

  /// No description provided for @logsAutoScroll.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll'**
  String get logsAutoScroll;

  /// No description provided for @logsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search (text/tag)...'**
  String get logsSearchHint;

  /// No description provided for @logsLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get logsLevel;

  /// No description provided for @logsAllLevels.
  ///
  /// In en, this message translates to:
  /// **'All levels'**
  String get logsAllLevels;

  /// No description provided for @logsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No log entries since app start.'**
  String get logsEmpty;

  /// No description provided for @logsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No log entries match the filter.'**
  String get logsNoMatch;

  /// No description provided for @logsCopyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get logsCopyButton;

  /// No description provided for @logsSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save log as .txt'**
  String get logsSaveButton;

  /// No description provided for @bugReportSubject.
  ///
  /// In en, this message translates to:
  /// **'Auditorium bug report ({file})'**
  String bugReportSubject(String file);

  /// No description provided for @bugReportText.
  ///
  /// In en, this message translates to:
  /// **'Auditorium bug report – please send to {email}.\nBriefly describe what happened and when.\nThe attached log contains only technical events – no audio and no talk text.'**
  String bugReportText(String email);

  /// No description provided for @logShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Auditorium app log ({file})'**
  String logShareSubject(String file);

  /// No description provided for @logShareText.
  ///
  /// In en, this message translates to:
  /// **'Auditorium debug log'**
  String get logShareText;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
