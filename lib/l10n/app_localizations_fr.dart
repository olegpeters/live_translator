// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get settings => 'Paramètres';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get understood => 'Compris';

  @override
  String get homeSourceLanguage => 'Conférence';

  @override
  String get homeTargetLanguage => 'Traduction';

  @override
  String get homeStatus => 'État';

  @override
  String get homeTapToStart => 'Appuyer pour démarrer';

  @override
  String get homeTapToStop => 'Appuyer pour arrêter';

  @override
  String get homeMicLevel => 'Niveau du micro';

  @override
  String homeTranscriptTitle(String language) {
    return 'Traduction ($language)';
  }

  @override
  String get homeClearText => 'Effacer le texte';

  @override
  String get homeTranscriptPlaceholder =>
      'Les phrases traduites apparaissent ici en direct pendant la conférence...';

  @override
  String get homeSourceTranscriptTitle => 'Texte source reconnu – diagnostic';

  @override
  String get homeSourceTranscriptPlaceholder =>
      'Le texte original reconnu par le modèle apparaît ici...';

  @override
  String get homeBufferTitle => 'Tampon audio TTS et synchronisation';

  @override
  String homeBufferTempo(String speed) {
    return 'Tempo : ${speed}x';
  }

  @override
  String homeBufferPrerolling(String buffer, String target) {
    return 'Mise en tampon : $buffer s / cible : $target s...';
  }

  @override
  String homeBufferStatus(String buffer, String target) {
    return 'Tampon : $buffer s (cible : $target s)';
  }

  @override
  String homeBufferReorder(int count) {
    return 'Ordre ajusté ($count)';
  }

  @override
  String homeLatency(String translation, String tts) {
    return 'Latence : traduction $translation s  •  TTS $tts s';
  }

  @override
  String get statusIdle => 'Inactif';

  @override
  String get statusConnecting => 'Connexion à Soniox...';

  @override
  String get statusActive => 'Traduction en direct active';

  @override
  String get statusFinishing =>
      'Fin de la traduction (traitement des phrases)...';

  @override
  String get statusConnectionError => 'Erreur de connexion';

  @override
  String statusReconnecting(int attempt, int max) {
    return 'Connexion interrompue (tentative $attempt/$max)...';
  }

  @override
  String get statusDisconnected => 'Déconnecté.';

  @override
  String get statusCheckingKey => 'Vérification de la clé API...';

  @override
  String get statusKeyRejected =>
      'Erreur : Soniox n’accepte pas la clé API. Vérifiez-la dans les paramètres.';

  @override
  String get statusNoApiKey => 'Erreur : aucune clé API dans les paramètres.';

  @override
  String get statusInitializing => 'Initialisation...';

  @override
  String statusStartFailed(String error) {
    return 'Échec du démarrage : $error';
  }

  @override
  String get statusStopping => 'Arrêt...';

  @override
  String get langGerman => 'Allemand';

  @override
  String get langEnglish => 'Anglais';

  @override
  String get langAuto => 'Automatique';

  @override
  String get langRussian => 'Russe';

  @override
  String get langUkrainian => 'Ukrainien';

  @override
  String get langSpanish => 'Espagnol';

  @override
  String get langFrench => 'Français';

  @override
  String get setupTitle => 'Saisir la clé API Soniox';

  @override
  String get setupIntro =>
      'Auditorium utilise Soniox pour la reconnaissance vocale, la traduction et la synthèse vocale. Saisissez votre clé API pour commencer.';

  @override
  String get apiKeyLabel => 'Clé API Soniox';

  @override
  String get setupKeyRejected =>
      'Soniox n’accepte pas cette clé API. Veuillez la vérifier.';

  @override
  String get setupSavedUnchecked =>
      'Clé API enregistrée. Elle n’a pas pu être vérifiée pour l’instant (hors ligne ?) ; la vérification aura lieu au démarrage de la traduction.';

  @override
  String get setupCreateAccount => 'Créer un compte Soniox';

  @override
  String setupLinkFailed(String url) {
    return 'Impossible d’ouvrir le lien : $url';
  }

  @override
  String get regionEu =>
      'Région : UE – l’audio et les textes sont traités dans l’UE.';

  @override
  String get regionUs =>
      'Région : États-Unis – l’audio et les textes sont traités aux États-Unis.';

  @override
  String get regionEuHowTo =>
      'Pour un traitement dans l’UE : demandez la région UE dans la console Soniox, sous « Security & compliance », créez un projet dans la région UE et utilisez sa clé API.';

  @override
  String get settingsSonioxAccess => 'Accès Soniox';

  @override
  String get settingsSpeechOutput => 'Synthèse vocale';

  @override
  String get settingsVoice => 'Voix';

  @override
  String voiceMaleDefault(String name) {
    return '$name (masculine, par défaut)';
  }

  @override
  String voiceMale(String name) {
    return '$name (masculine)';
  }

  @override
  String voiceFemale(String name) {
    return '$name (féminine)';
  }

  @override
  String get settingsGlossary => 'Glossaire';

  @override
  String get settingsGlossaryPreset =>
      'Utiliser le glossaire prédéfini « Sermon (adventiste) »';

  @override
  String get settingsGlossaryPresetHint =>
      'Livres de la Bible, noms, termes adventistes et titres des livres d’Ellen White. Combiné avec votre propre glossaire ; vos entrées sont prioritaires.';

  @override
  String get settingsOwnGlossary => 'Glossaire personnel (noms, termes)';

  @override
  String get settingsOwnGlossaryHint =>
      'Une entrée par ligne, p. ex.\nAaron\nAnbetung = поклонение';

  @override
  String get settingsOwnGlossaryHelper =>
      'Terme = aide à la reconnaissance ; « Source = Cible » fixe la traduction.';

  @override
  String get settingsVolume => 'Volume de la traduction';

  @override
  String get settingsGain => 'Amplification :';

  @override
  String get settingsGainHint =>
      'Rend la traduction parlée plus forte (100–300 %). Par défaut : 200 %.';

  @override
  String get settingsHelp => 'Aide';

  @override
  String get settingsReportBug => 'Signaler un problème';

  @override
  String settingsReportBugHint(String email) {
    return 'Envoie le journal technique (sans audio ni texte de la conférence) par e-mail à $email. Vous décidez dans le menu de partage s’il est envoyé et comment.';
  }

  @override
  String get settingsNoLogEntries => 'Aucune entrée de journal pour l’instant.';

  @override
  String settingsBugReportFailed(String error) {
    return 'Impossible de créer le rapport d’erreur : $error';
  }

  @override
  String get settingsDebugMode => 'Mode débogage';

  @override
  String get settingsDebugModeHint =>
      'Affiche des valeurs techniques (tampon, latence) et des options de dépannage. Ces options ne s’appliquent que lorsque le mode débogage est activé.';

  @override
  String get settingsTtsEngine => 'Moteur TTS (synthèse vocale)';

  @override
  String get ttsEngineSoniox => 'Soniox API (streaming cloud)';

  @override
  String get ttsEngineOnboard => 'TTS Android intégré (local)';

  @override
  String get settingsVoiceProcessing => 'Traitement vocal du micro';

  @override
  String get settingsVoiceProcessingHint =>
      'Suppression d’écho et de bruit. Désactivé avec un casque (sinon la voix est supprimée pendant la lecture), activé avec le haut-parleur.';

  @override
  String get voiceProcessingAuto => 'Automatique (selon le casque)';

  @override
  String get voiceProcessingOn => 'Toujours activé';

  @override
  String get voiceProcessingOff => 'Toujours désactivé';

  @override
  String get settingsSourceTranscription => 'Transcription du texte source';

  @override
  String get settingsSourceTranscriptionHint =>
      'Reconnaît et affiche le texte original. Utile uniquement pour le débogage/diagnostic. Par défaut : désactivé.';

  @override
  String get settingsMicRecording => 'Enregistrement du micro';

  @override
  String get settingsMicRecordingHint =>
      'Enregistre en WAV l’audio du micro envoyé à Soniox lors de la dernière session. Joint à l’export du journal. Diagnostic uniquement.';

  @override
  String settingsAppLogs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées',
      one: '1 entrée',
      zero: '0 entrée',
    );
    return 'Journal de l’app ($_temp0)';
  }

  @override
  String get settingsAppLogsHint =>
      'Afficher le journal de session depuis le démarrage de l’app, le copier ou l’enregistrer en fichier .txt.';

  @override
  String get settingsSaved => 'Paramètres enregistrés';

  @override
  String get settingsSavedKeyRejected =>
      'Enregistré, mais Soniox n’accepte pas la clé API. Veuillez la vérifier.';

  @override
  String get settingsSavedUs =>
      'Enregistré. La clé API appartient à un projet Soniox aux États-Unis.';

  @override
  String get settingsSavedUnchecked =>
      'Enregistré. La clé API n’a pas pu être vérifiée (hors ligne ?) ; vérification au démarrage.';

  @override
  String logsTitle(int count) {
    return 'Journal ($count)';
  }

  @override
  String get logsCopyTooltip => 'Copier dans le presse-papiers';

  @override
  String get logsShareTooltip => 'Enregistrer / partager en fichier texte';

  @override
  String get logsDeleteTooltip => 'Supprimer le journal';

  @override
  String get logsDeleteTitle => 'Supprimer le journal ?';

  @override
  String get logsDeleteConfirm =>
      'Voulez-vous vraiment supprimer le journal temporaire de la session en cours ?';

  @override
  String get logsDeleted => 'Entrées du journal supprimées.';

  @override
  String get logsCopied => 'Journal complet copié dans le presse-papiers.';

  @override
  String get logsNothingToSave => 'Aucune entrée à enregistrer.';

  @override
  String get logsExported => 'Fichier journal exporté';

  @override
  String logsProvided(String path) {
    return 'Fichier journal disponible sous $path';
  }

  @override
  String logsSaveFailed(String error) {
    return 'Impossible d’enregistrer le fichier journal : $error';
  }

  @override
  String logsSessionInfo(String start, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées',
      one: '1 entrée',
      zero: '0 entrée',
    );
    return 'Début : $start • Total : $_temp0';
  }

  @override
  String get logsAutoScroll => 'Défilement auto';

  @override
  String get logsSearchHint => 'Rechercher (texte/tag)...';

  @override
  String get logsLevel => 'Niveau';

  @override
  String get logsAllLevels => 'Tous les niveaux';

  @override
  String get logsEmpty => 'Aucune entrée depuis le démarrage de l’app.';

  @override
  String get logsNoMatch => 'Aucune entrée ne correspond au filtre.';

  @override
  String get logsCopyButton => 'Copier';

  @override
  String get logsSaveButton => 'Enregistrer le journal en .txt';

  @override
  String bugReportSubject(String file) {
    return 'Auditorium : rapport d’erreur ($file)';
  }

  @override
  String bugReportText(String email) {
    return 'Rapport d’erreur Auditorium – à envoyer à $email.\nDécrivez brièvement ce qui s’est passé et quand.\nLe journal joint ne contient que des événements techniques, sans audio ni texte de la conférence.';
  }

  @override
  String logShareSubject(String file) {
    return 'Auditorium : journal de l’app ($file)';
  }

  @override
  String get logShareText => 'Journal de débogage Auditorium';
}
