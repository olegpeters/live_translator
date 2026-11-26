// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settings => 'Settings';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get understood => 'Got it';

  @override
  String get homeSourceLanguage => 'Talk';

  @override
  String get homeTargetLanguage => 'Translation';

  @override
  String get homeStatus => 'Status';

  @override
  String get homeTapToStart => 'Tap to start';

  @override
  String get homeTapToStop => 'Tap to stop';

  @override
  String get homeMicLevel => 'Microphone level';

  @override
  String homeTranscriptTitle(String language) {
    return 'Translation ($language)';
  }

  @override
  String get homeClearText => 'Clear text';

  @override
  String get homeTranscriptPlaceholder =>
      'The translated sentences appear here live during the talk...';

  @override
  String get homeSourceTranscriptTitle =>
      'Recognized source text – diagnostics';

  @override
  String get homeSourceTranscriptPlaceholder =>
      'The original text recognized by the model appears here...';

  @override
  String get homeBufferTitle => 'TTS audio buffer & sync';

  @override
  String homeBufferTempo(String speed) {
    return 'Tempo: ${speed}x';
  }

  @override
  String homeBufferPrerolling(String buffer, String target) {
    return 'Buffering: ${buffer}s / target: ${target}s...';
  }

  @override
  String homeBufferStatus(String buffer, String target) {
    return 'Buffer: ${buffer}s (target: ${target}s)';
  }

  @override
  String homeBufferReorder(int count) {
    return 'Order adjusted ($count)';
  }

  @override
  String homeLatency(String translation, String tts) {
    return 'Latency: translation ${translation}s  •  TTS ${tts}s';
  }

  @override
  String get statusIdle => 'Inactive';

  @override
  String get statusConnecting => 'Connecting to Soniox...';

  @override
  String get statusActive => 'Live translation active';

  @override
  String get statusFinishing =>
      'Finishing translation (processing sentences)...';

  @override
  String get statusConnectionError => 'Connection error';

  @override
  String statusReconnecting(int attempt, int max) {
    return 'Connection lost (attempt $attempt/$max)...';
  }

  @override
  String get statusDisconnected => 'Disconnected.';

  @override
  String get statusCheckingKey => 'Checking API key...';

  @override
  String get statusKeyRejected =>
      'Error: Soniox does not accept the API key. Please check it in the settings.';

  @override
  String get statusNoApiKey => 'Error: no API key in the settings.';

  @override
  String get statusInitializing => 'Initializing...';

  @override
  String statusStartFailed(String error) {
    return 'Failed to start: $error';
  }

  @override
  String get statusMicPermissionDenied =>
      'Microphone access denied. Allow it in the Android app settings.';

  @override
  String get homeOpenAppSettings => 'Open app settings';

  @override
  String get statusStopping => 'Stopping...';

  @override
  String get langGerman => 'German';

  @override
  String get langEnglish => 'English';

  @override
  String get langAuto => 'Automatic';

  @override
  String get langRussian => 'Russian';

  @override
  String get langUkrainian => 'Ukrainian';

  @override
  String get langSpanish => 'Spanish';

  @override
  String get langFrench => 'French';

  @override
  String get setupTitle => 'Enter Soniox API key';

  @override
  String get setupIntro =>
      'Auditorium uses Soniox for speech recognition, translation and speech output. Enter your API key to get started.';

  @override
  String get apiKeyLabel => 'Soniox API key';

  @override
  String get setupKeyRejected =>
      'Soniox does not accept this API key. Please check it.';

  @override
  String get setupSavedUnchecked =>
      'API key saved. It could not be checked right now (offline?); it will be checked when the translation starts.';

  @override
  String get setupCreateAccount => 'Create Soniox account';

  @override
  String setupLinkFailed(String url) {
    return 'Could not open link: $url';
  }

  @override
  String get regionEu => 'Region: EU – audio and text are processed in the EU.';

  @override
  String get regionUs =>
      'Region: USA – audio and text are processed in the USA.';

  @override
  String get regionEuHowTo =>
      'To have them processed in the EU: request the EU region in the Soniox console under “Security & compliance”, create a project in the EU region and use its API key.';

  @override
  String get settingsSonioxAccess => 'Soniox access';

  @override
  String get settingsSpeechOutput => 'Speech output';

  @override
  String get settingsVoice => 'Voice';

  @override
  String voiceMaleDefault(String name) {
    return '$name (male, default)';
  }

  @override
  String voiceMale(String name) {
    return '$name (male)';
  }

  @override
  String voiceFemale(String name) {
    return '$name (female)';
  }

  @override
  String get settingsGlossary => 'Glossary';

  @override
  String get settingsGlossaryPreset => 'Preset';

  @override
  String get settingsGlossaryPresetNone => 'None';

  @override
  String get settingsGlossaryPresetSermon => 'Sermon';

  @override
  String get settingsGlossaryPresetHint =>
      'Bible books, names, Adventist terms and Ellen White book titles. Combined with your own glossary; your own entries take precedence.';

  @override
  String get settingsOwnGlossary => 'Own glossary (names, terms)';

  @override
  String get settingsOwnGlossaryHint =>
      'One entry per line, e.g.\nAaron\nAnbetung = поклонение';

  @override
  String get settingsOwnGlossaryHelper =>
      'Term = recognition aid; “Source = Target” fixes the translation.';

  @override
  String get settingsVolume => 'Translation volume';

  @override
  String get settingsGain => 'Amplification:';

  @override
  String get settingsGainHint =>
      'Makes the spoken translation louder (100–300 %). Default: 200 %.';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsReportBug => 'Report a problem';

  @override
  String settingsReportBugHint(String email) {
    return 'Sends the technical log (no audio, no talk text) by email to $email. You decide in the share menu whether and how it is sent.';
  }

  @override
  String get settingsNoLogEntries => 'No log entries yet.';

  @override
  String settingsBugReportFailed(String error) {
    return 'Could not create the bug report: $error';
  }

  @override
  String get settingsDebugMode => 'Debug mode';

  @override
  String get settingsDebugModeHint =>
      'Shows technical values (buffer, latency) and troubleshooting options. These options only take effect while debug mode is on.';

  @override
  String get settingsTtsEngine => 'TTS engine (speech output)';

  @override
  String get ttsEngineSoniox => 'Soniox API (cloud streaming)';

  @override
  String get ttsEngineOnboard => 'Onboard Android TTS (local)';

  @override
  String get settingsVoiceProcessing => 'Microphone voice processing';

  @override
  String get settingsVoiceProcessingHint =>
      'Echo/noise suppression. Off with headphones (otherwise speech is suppressed during playback), on with the loudspeaker.';

  @override
  String get voiceProcessingAuto => 'Automatic (by headphones)';

  @override
  String get voiceProcessingOn => 'Always on';

  @override
  String get voiceProcessingOff => 'Always off';

  @override
  String get settingsSourceTranscription => 'Source text transcription';

  @override
  String get settingsSourceTranscriptionHint =>
      'Recognizes and shows the original text. Only relevant for debugging/diagnostics. Default: off.';

  @override
  String get settingsMicRecording => 'Microphone recording';

  @override
  String get settingsMicRecordingHint =>
      'Saves the microphone audio of the last session sent to Soniox as WAV. Included in the log export. Diagnostics only.';

  @override
  String settingsAppLogs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'App logs ($_temp0)';
  }

  @override
  String get settingsAppLogsHint =>
      'Show the session log since app start, copy it or save it as a .txt file.';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get settingsSavedKeyRejected =>
      'Saved, but Soniox does not accept the API key. Please check it.';

  @override
  String get settingsSavedUs =>
      'Saved. The API key belongs to a Soniox project in the USA.';

  @override
  String get settingsSavedUnchecked =>
      'Saved. The API key could not be checked (offline?); it will be checked at start.';

  @override
  String logsTitle(int count) {
    return 'App logs ($count)';
  }

  @override
  String get logsCopyTooltip => 'Copy to clipboard';

  @override
  String get logsShareTooltip => 'Save / share as text file';

  @override
  String get logsDeleteTooltip => 'Delete log';

  @override
  String get logsDeleteTitle => 'Delete log?';

  @override
  String get logsDeleteConfirm =>
      'Do you really want to delete the current temporary session log?';

  @override
  String get logsDeleted => 'Log entries deleted.';

  @override
  String get logsCopied => 'Entire log copied to clipboard.';

  @override
  String get logsNothingToSave => 'No log entries to save.';

  @override
  String get logsExported => 'Log file exported';

  @override
  String logsProvided(String path) {
    return 'Log file available at $path';
  }

  @override
  String logsSaveFailed(String error) {
    return 'Could not save the log file: $error';
  }

  @override
  String logsSessionInfo(String start, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'Start: $start • Total: $_temp0';
  }

  @override
  String get logsAutoScroll => 'Auto-scroll';

  @override
  String get logsSearchHint => 'Search (text/tag)...';

  @override
  String get logsLevel => 'Level';

  @override
  String get logsAllLevels => 'All levels';

  @override
  String get logsEmpty => 'No log entries since app start.';

  @override
  String get logsNoMatch => 'No log entries match the filter.';

  @override
  String get logsCopyButton => 'Copy';

  @override
  String get logsSaveButton => 'Save log as .txt';

  @override
  String bugReportSubject(String file) {
    return 'Auditorium bug report ($file)';
  }

  @override
  String bugReportText(String email) {
    return 'Auditorium bug report – please send to $email.\nBriefly describe what happened and when.\nThe attached log contains only technical events – no audio and no talk text.';
  }

  @override
  String logShareSubject(String file) {
    return 'Auditorium app log ($file)';
  }

  @override
  String get logShareText => 'Auditorium debug log';
}
