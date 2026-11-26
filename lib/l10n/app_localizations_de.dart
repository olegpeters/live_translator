// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get settings => 'Einstellungen';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get understood => 'Verstanden';

  @override
  String get homeSourceLanguage => 'Vortrag';

  @override
  String get homeTargetLanguage => 'Übersetzung';

  @override
  String get homeStatus => 'Status';

  @override
  String get homeTapToStart => 'Tippen zum Starten';

  @override
  String get homeTapToStop => 'Tippen zum Stoppen';

  @override
  String get homeMicLevel => 'Mikrofon-Pegel';

  @override
  String get homeTranscriptTitle => 'Übersetzung';

  @override
  String get homeClearText => 'Text leeren';

  @override
  String get homeSpeechToggle => 'Vorlesen';

  @override
  String get homeSpeechOnTooltip => 'Vorlesen ist an: tippen für nur Text';

  @override
  String get homeSpeechOffTooltip => 'Übersetzung vorlesen lassen (Kopfhörer)';

  @override
  String get homeTranscriptPlaceholder =>
      'Die übersetzten Sätze erscheinen hier live während des Vortrags...';

  @override
  String get homeSourceTranscriptTitle => 'Erkannter Quelltext – Diagnose';

  @override
  String get homeSourceTranscriptPlaceholder =>
      'Hier erscheint der vom Modell erkannte Originaltext...';

  @override
  String get homeBufferTitle => 'TTS Audio-Puffer & Sync';

  @override
  String homeBufferTempo(String speed) {
    return 'Tempo: ${speed}x';
  }

  @override
  String homeBufferPrerolling(String buffer, String target) {
    return 'Puffern: ${buffer}s / Ziel: ${target}s...';
  }

  @override
  String homeBufferStatus(String buffer, String target) {
    return 'Puffer: ${buffer}s (Ziel: ${target}s)';
  }

  @override
  String homeBufferReorder(int count) {
    return 'Reihenfolge-Anpassung erfolgte ($count)';
  }

  @override
  String homeLatency(String translation, String tts) {
    return 'Latenz: Übersetzung ${translation}s  •  TTS ${tts}s';
  }

  @override
  String get statusIdle => 'Inaktiv';

  @override
  String get statusConnecting => 'Verbinde mit Soniox...';

  @override
  String get statusActive => 'Live-Übersetzung aktiv';

  @override
  String get statusFinishing =>
      'Beende Übersetzung (Sätze werden verarbeitet)...';

  @override
  String get statusConnectionError => 'Verbindungsfehler';

  @override
  String statusReconnecting(int attempt, int max) {
    return 'Verbindung unterbrochen (Versuch $attempt/$max)...';
  }

  @override
  String get statusDisconnected => 'Verbindung getrennt.';

  @override
  String get statusCheckingKey => 'Prüfe API-Key...';

  @override
  String get statusKeyRejected =>
      'Fehler: Der API-Key wird von Soniox nicht akzeptiert. Bitte in den Einstellungen prüfen.';

  @override
  String get statusNoApiKey =>
      'Fehler: Kein API-Key in den Einstellungen hinterlegt.';

  @override
  String get statusInitializing => 'Initialisiere...';

  @override
  String statusStartFailed(String error) {
    return 'Fehler beim Starten: $error';
  }

  @override
  String get statusMicPermissionDenied =>
      'Kein Zugriff aufs Mikrofon. Bitte in den Android-App-Einstellungen erlauben.';

  @override
  String get homeOpenAppSettings => 'App-Einstellungen öffnen';

  @override
  String get statusStopping => 'Stoppe...';

  @override
  String get langGerman => 'Deutsch';

  @override
  String get langEnglish => 'Englisch';

  @override
  String get langAuto => 'Automatisch';

  @override
  String get langRussian => 'Russisch';

  @override
  String get langUkrainian => 'Ukrainisch';

  @override
  String get langSpanish => 'Spanisch';

  @override
  String get langFrench => 'Französisch';

  @override
  String get langArabic => 'Arabisch';

  @override
  String get setupTitle => 'Soniox-API-Key eintragen';

  @override
  String get setupIntro =>
      'Auditorium nutzt Soniox für Spracherkennung, Übersetzung und Sprachausgabe. Trage deinen API-Key ein, um zu starten.';

  @override
  String get apiKeyLabel => 'Soniox API-Key';

  @override
  String get setupKeyRejected =>
      'Soniox akzeptiert diesen API-Key nicht. Bitte prüfen.';

  @override
  String get setupSavedUnchecked =>
      'API-Key gespeichert. Er konnte gerade nicht geprüft werden (offline?); die Prüfung erfolgt beim Start der Übersetzung.';

  @override
  String get setupCreateAccount => 'Soniox-Konto erstellen';

  @override
  String setupLinkFailed(String url) {
    return 'Link konnte nicht geöffnet werden: $url';
  }

  @override
  String get regionEu =>
      'Region: EU – Audio und Texte werden in der EU verarbeitet.';

  @override
  String get regionUs =>
      'Region: USA – Audio und Texte werden in den USA verarbeitet.';

  @override
  String get regionEuHowTo =>
      'Für Verarbeitung in der EU: in der Soniox-Konsole unter „Security & compliance“ die EU-Region beantragen, ein Projekt in der EU-Region anlegen und dessen API-Key verwenden.';

  @override
  String get settingsSonioxAccess => 'Soniox-Zugang';

  @override
  String get settingsSpeechOutput => 'Sprachausgabe';

  @override
  String get settingsVoice => 'Stimme';

  @override
  String voiceMaleDefault(String name) {
    return '$name (männlich, Standard)';
  }

  @override
  String voiceMale(String name) {
    return '$name (männlich)';
  }

  @override
  String voiceFemale(String name) {
    return '$name (weiblich)';
  }

  @override
  String get settingsGlossary => 'Glossar';

  @override
  String get settingsGlossaryPreset => 'Vorlage';

  @override
  String get settingsGlossaryPresetNone => 'Keine';

  @override
  String get settingsGlossaryPresetSermon => 'Predigt';

  @override
  String get settingsGlossaryPresetHint =>
      'Bibelbücher, Namen, adventistische Begriffe und Ellen-White-Buchtitel. Wird mit dem eigenen Glossar kombiniert; eigene Einträge haben Vorrang.';

  @override
  String get settingsOwnGlossary => 'Eigenes Glossar (Namen, Fachbegriffe)';

  @override
  String get settingsOwnGlossaryHint =>
      'Ein Eintrag pro Zeile, z. B.\nAaron\nAnbetung = поклонение';

  @override
  String get settingsOwnGlossaryHelper =>
      'Begriff = Erkennungshilfe; „Quelle = Ziel“ legt die Übersetzung fest.';

  @override
  String get settingsVolume => 'Lautstärke der Übersetzung';

  @override
  String get settingsGain => 'Verstärkung:';

  @override
  String get settingsGainHint =>
      'Macht die gesprochene Übersetzung lauter (100–300 %). Standard: 200 %.';

  @override
  String get settingsHelp => 'Hilfe';

  @override
  String get settingsReportBug => 'Fehler melden';

  @override
  String settingsReportBugHint(String email) {
    return 'Schickt das technische Protokoll (ohne Audio und Vortragstext) per Mail an $email. Du entscheidest im Teilen-Menü, ob und wie es gesendet wird.';
  }

  @override
  String get settingsNoLogEntries => 'Noch keine Protokolleinträge vorhanden.';

  @override
  String settingsBugReportFailed(String error) {
    return 'Fehlerbericht konnte nicht erstellt werden: $error';
  }

  @override
  String get settingsDebugMode => 'Debug-Modus';

  @override
  String get settingsDebugModeHint =>
      'Zeigt technische Werte (Puffer, Latenz) und Optionen zur Fehlersuche. Diese Optionen wirken nur, solange der Debug-Modus an ist.';

  @override
  String get settingsTtsEngine => 'TTS-Engine (Sprachausgabe)';

  @override
  String get ttsEngineSoniox => 'Soniox API (Cloud-Streaming)';

  @override
  String get ttsEngineOnboard => 'Onboard Android TTS (lokal)';

  @override
  String get settingsVoiceProcessing => 'Sprachverarbeitung Mikrofon';

  @override
  String get settingsVoiceProcessingHint =>
      'Echo-/Rauschunterdrückung. Mit Kopfhörern aus (sonst wird Sprache während der Wiedergabe unterdrückt), mit Lautsprecher an.';

  @override
  String get voiceProcessingAuto => 'Automatisch (nach Kopfhörer)';

  @override
  String get voiceProcessingOn => 'Immer an';

  @override
  String get voiceProcessingOff => 'Immer aus';

  @override
  String get settingsSourceTranscription => 'Quelltext-Transkription';

  @override
  String get settingsSourceTranscriptionHint =>
      'Erkennt und zeigt den Originaltext an. Nur für Debugging/Diagnose relevant. Standard: aus.';

  @override
  String get settingsMicRecording => 'Mikrofon-Mitschnitt';

  @override
  String get settingsMicRecordingHint =>
      'Speichert das an Soniox gesendete Mikrofon-Audio der letzten Sitzung als WAV. Wird beim Log-Export mitgeteilt. Nur zur Diagnose.';

  @override
  String settingsAppLogs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return 'App-Logs / Protokoll ($_temp0)';
  }

  @override
  String get settingsAppLogsHint =>
      'Sitzungsprotokoll seit App-Start anzeigen, kopieren oder als .txt-Datei speichern.';

  @override
  String get settingsSaved => 'Einstellungen gespeichert';

  @override
  String get settingsSavedKeyRejected =>
      'Gespeichert, aber der API-Key wird von Soniox nicht akzeptiert. Bitte prüfen.';

  @override
  String get settingsSavedUs =>
      'Gespeichert. Der API-Key gehört zu einem Soniox-Projekt in den USA.';

  @override
  String get settingsSavedUnchecked =>
      'Gespeichert. Der API-Key konnte nicht geprüft werden (offline?); Prüfung beim Start.';

  @override
  String logsTitle(int count) {
    return 'App-Logs ($count)';
  }

  @override
  String get logsCopyTooltip => 'In Zwischenablage kopieren';

  @override
  String get logsShareTooltip => 'Als Textdatei speichern / teilen';

  @override
  String get logsDeleteTooltip => 'Log löschen';

  @override
  String get logsDeleteTitle => 'Log löschen?';

  @override
  String get logsDeleteConfirm =>
      'Möchtest du das aktuelle temporäre Sitzungsprotokoll wirklich löschen?';

  @override
  String get logsDeleted => 'Log-Einträge gelöscht.';

  @override
  String get logsCopied => 'Gesamtes Log in die Zwischenablage kopiert.';

  @override
  String get logsNothingToSave => 'Keine Log-Einträge zum Speichern vorhanden.';

  @override
  String get logsExported => 'Log-Datei exportiert';

  @override
  String logsProvided(String path) {
    return 'Log-Datei unter $path bereitgestellt';
  }

  @override
  String logsSaveFailed(String error) {
    return 'Fehler beim Speichern der Log-Datei: $error';
  }

  @override
  String logsSessionInfo(String start, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return 'Start: $start • Gesamt: $_temp0';
  }

  @override
  String get logsAutoScroll => 'Auto-Scroll';

  @override
  String get logsSearchHint => 'Suchen (Text/Tag)...';

  @override
  String get logsLevel => 'Level';

  @override
  String get logsAllLevels => 'Alle Levels';

  @override
  String get logsEmpty => 'Keine Log-Einträge seit dem App-Start vorhanden.';

  @override
  String get logsNoMatch =>
      'Keine passenden Log-Einträge für den Filter gefunden.';

  @override
  String get logsCopyButton => 'Kopieren';

  @override
  String get logsSaveButton => 'Log als .txt speichern';

  @override
  String bugReportSubject(String file) {
    return 'Auditorium Fehlerbericht ($file)';
  }

  @override
  String bugReportText(String email) {
    return 'Fehlerbericht Auditorium – bitte an $email senden.\nBeschreibe kurz, was passiert ist und wann.\nDas angehängte Protokoll enthält nur technische Ereignisse – kein Audio und keinen Vortragstext.';
  }

  @override
  String logShareSubject(String file) {
    return 'Auditorium App-Log ($file)';
  }

  @override
  String get logShareText => 'Auditorium Debugging-Protokoll';
}
