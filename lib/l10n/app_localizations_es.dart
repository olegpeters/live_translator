// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get settings => 'Ajustes';

  @override
  String get save => 'Guardar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get understood => 'Entendido';

  @override
  String get homeSourceLanguage => 'Charla';

  @override
  String get homeTargetLanguage => 'Traducción';

  @override
  String get homeStatus => 'Estado';

  @override
  String get homeTapToStart => 'Toca para empezar';

  @override
  String get homeTapToStop => 'Toca para detener';

  @override
  String get homeMicLevel => 'Nivel del micrófono';

  @override
  String homeTranscriptTitle(String language) {
    return 'Traducción ($language)';
  }

  @override
  String get homeClearText => 'Borrar texto';

  @override
  String get homeTranscriptPlaceholder =>
      'Las frases traducidas aparecen aquí en directo durante la charla...';

  @override
  String get homeSourceTranscriptTitle =>
      'Texto original reconocido – diagnóstico';

  @override
  String get homeSourceTranscriptPlaceholder =>
      'Aquí aparece el texto original reconocido por el modelo...';

  @override
  String get homeBufferTitle => 'Búfer de audio TTS y sincronización';

  @override
  String homeBufferTempo(String speed) {
    return 'Velocidad: ${speed}x';
  }

  @override
  String homeBufferPrerolling(String buffer, String target) {
    return 'Almacenando: $buffer s / objetivo: $target s...';
  }

  @override
  String homeBufferStatus(String buffer, String target) {
    return 'Búfer: $buffer s (objetivo: $target s)';
  }

  @override
  String homeBufferReorder(int count) {
    return 'Orden ajustado ($count)';
  }

  @override
  String homeLatency(String translation, String tts) {
    return 'Latencia: traducción $translation s  •  TTS $tts s';
  }

  @override
  String get statusIdle => 'Inactivo';

  @override
  String get statusConnecting => 'Conectando con Soniox...';

  @override
  String get statusActive => 'Traducción en directo activa';

  @override
  String get statusFinishing =>
      'Finalizando la traducción (procesando frases)...';

  @override
  String get statusConnectionError => 'Error de conexión';

  @override
  String statusReconnecting(int attempt, int max) {
    return 'Conexión interrumpida (intento $attempt/$max)...';
  }

  @override
  String get statusDisconnected => 'Desconectado.';

  @override
  String get statusCheckingKey => 'Comprobando la clave API...';

  @override
  String get statusKeyRejected =>
      'Error: Soniox no acepta la clave API. Revísala en los ajustes.';

  @override
  String get statusNoApiKey =>
      'Error: no hay ninguna clave API en los ajustes.';

  @override
  String get statusInitializing => 'Inicializando...';

  @override
  String statusStartFailed(String error) {
    return 'Error al iniciar: $error';
  }

  @override
  String get statusMicPermissionDenied =>
      'Sin acceso al micrófono. Permítelo en los ajustes de la app de Android.';

  @override
  String get homeOpenAppSettings => 'Abrir ajustes de la app';

  @override
  String get statusStopping => 'Deteniendo...';

  @override
  String get langGerman => 'Alemán';

  @override
  String get langEnglish => 'Inglés';

  @override
  String get langAuto => 'Automático';

  @override
  String get langRussian => 'Ruso';

  @override
  String get langUkrainian => 'Ucraniano';

  @override
  String get langSpanish => 'Español';

  @override
  String get langFrench => 'Francés';

  @override
  String get langArabic => 'Árabe';

  @override
  String get setupTitle => 'Introduce la clave API de Soniox';

  @override
  String get setupIntro =>
      'Auditorium usa Soniox para el reconocimiento de voz, la traducción y la locución. Introduce tu clave API para empezar.';

  @override
  String get apiKeyLabel => 'Clave API de Soniox';

  @override
  String get setupKeyRejected => 'Soniox no acepta esta clave API. Revísala.';

  @override
  String get setupSavedUnchecked =>
      'Clave API guardada. No se ha podido comprobar ahora (¿sin conexión?); se comprobará al iniciar la traducción.';

  @override
  String get setupCreateAccount => 'Crear una cuenta de Soniox';

  @override
  String setupLinkFailed(String url) {
    return 'No se ha podido abrir el enlace: $url';
  }

  @override
  String get regionEu =>
      'Región: UE – el audio y los textos se procesan en la UE.';

  @override
  String get regionUs =>
      'Región: EE. UU. – el audio y los textos se procesan en EE. UU.';

  @override
  String get regionEuHowTo =>
      'Para procesarlos en la UE: solicita la región UE en la consola de Soniox, en «Security & compliance», crea un proyecto en la región UE y usa su clave API.';

  @override
  String get settingsSonioxAccess => 'Acceso a Soniox';

  @override
  String get settingsSpeechOutput => 'Locución';

  @override
  String get settingsVoice => 'Voz';

  @override
  String voiceMaleDefault(String name) {
    return '$name (masculina, predeterminada)';
  }

  @override
  String voiceMale(String name) {
    return '$name (masculina)';
  }

  @override
  String voiceFemale(String name) {
    return '$name (femenina)';
  }

  @override
  String get settingsGlossary => 'Glosario';

  @override
  String get settingsGlossaryPreset => 'Plantilla';

  @override
  String get settingsGlossaryPresetNone => 'Ninguna';

  @override
  String get settingsGlossaryPresetSermon => 'Sermón';

  @override
  String get settingsGlossaryPresetHint =>
      'Libros de la Biblia, nombres, términos adventistas y títulos de libros de Elena G. de White. Se combina con tu propio glosario; tus entradas tienen prioridad.';

  @override
  String get settingsOwnGlossary => 'Glosario propio (nombres, términos)';

  @override
  String get settingsOwnGlossaryHint =>
      'Una entrada por línea, p. ej.\nAaron\nAnbetung = поклонение';

  @override
  String get settingsOwnGlossaryHelper =>
      'Término = ayuda de reconocimiento; «Origen = Destino» fija la traducción.';

  @override
  String get settingsVolume => 'Volumen de la traducción';

  @override
  String get settingsGain => 'Amplificación:';

  @override
  String get settingsGainHint =>
      'Hace que la traducción hablada suene más fuerte (100–300 %). Predeterminado: 200 %.';

  @override
  String get settingsHelp => 'Ayuda';

  @override
  String get settingsReportBug => 'Informar de un problema';

  @override
  String settingsReportBugHint(String email) {
    return 'Envía el registro técnico (sin audio ni texto de la charla) por correo a $email. En el menú de compartir decides si se envía y cómo.';
  }

  @override
  String get settingsNoLogEntries => 'Todavía no hay entradas en el registro.';

  @override
  String settingsBugReportFailed(String error) {
    return 'No se ha podido crear el informe de error: $error';
  }

  @override
  String get settingsDebugMode => 'Modo de depuración';

  @override
  String get settingsDebugModeHint =>
      'Muestra valores técnicos (búfer, latencia) y opciones para buscar errores. Estas opciones solo se aplican mientras el modo de depuración está activado.';

  @override
  String get settingsTtsEngine => 'Motor TTS (locución)';

  @override
  String get ttsEngineSoniox => 'Soniox API (streaming en la nube)';

  @override
  String get ttsEngineOnboard => 'TTS integrado de Android (local)';

  @override
  String get settingsVoiceProcessing => 'Procesamiento de voz del micrófono';

  @override
  String get settingsVoiceProcessingHint =>
      'Supresión de eco y ruido. Desactivado con auriculares (si no, se suprime la voz durante la reproducción), activado con el altavoz.';

  @override
  String get voiceProcessingAuto => 'Automático (según auriculares)';

  @override
  String get voiceProcessingOn => 'Siempre activado';

  @override
  String get voiceProcessingOff => 'Siempre desactivado';

  @override
  String get settingsSourceTranscription => 'Transcripción del texto original';

  @override
  String get settingsSourceTranscriptionHint =>
      'Reconoce y muestra el texto original. Solo es relevante para depuración/diagnóstico. Predeterminado: desactivado.';

  @override
  String get settingsMicRecording => 'Grabación del micrófono';

  @override
  String get settingsMicRecordingHint =>
      'Guarda como WAV el audio del micrófono enviado a Soniox en la última sesión. Se incluye en la exportación del registro. Solo para diagnóstico.';

  @override
  String settingsAppLogs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
    );
    return 'Registro de la app ($_temp0)';
  }

  @override
  String get settingsAppLogsHint =>
      'Muestra el registro de la sesión desde el inicio de la app, cópialo o guárdalo como archivo .txt.';

  @override
  String get settingsSaved => 'Ajustes guardados';

  @override
  String get settingsSavedKeyRejected =>
      'Guardado, pero Soniox no acepta la clave API. Revísala.';

  @override
  String get settingsSavedUs =>
      'Guardado. La clave API pertenece a un proyecto de Soniox en EE. UU.';

  @override
  String get settingsSavedUnchecked =>
      'Guardado. No se ha podido comprobar la clave API (¿sin conexión?); se comprobará al iniciar.';

  @override
  String logsTitle(int count) {
    return 'Registro ($count)';
  }

  @override
  String get logsCopyTooltip => 'Copiar al portapapeles';

  @override
  String get logsShareTooltip => 'Guardar / compartir como archivo de texto';

  @override
  String get logsDeleteTooltip => 'Eliminar registro';

  @override
  String get logsDeleteTitle => '¿Eliminar el registro?';

  @override
  String get logsDeleteConfirm =>
      '¿Seguro que quieres eliminar el registro temporal de la sesión actual?';

  @override
  String get logsDeleted => 'Entradas del registro eliminadas.';

  @override
  String get logsCopied => 'Registro completo copiado al portapapeles.';

  @override
  String get logsNothingToSave => 'No hay entradas para guardar.';

  @override
  String get logsExported => 'Archivo de registro exportado';

  @override
  String logsProvided(String path) {
    return 'Archivo de registro disponible en $path';
  }

  @override
  String logsSaveFailed(String error) {
    return 'No se ha podido guardar el archivo de registro: $error';
  }

  @override
  String logsSessionInfo(String start, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
    );
    return 'Inicio: $start • Total: $_temp0';
  }

  @override
  String get logsAutoScroll => 'Desplazamiento automático';

  @override
  String get logsSearchHint => 'Buscar (texto/etiqueta)...';

  @override
  String get logsLevel => 'Nivel';

  @override
  String get logsAllLevels => 'Todos los niveles';

  @override
  String get logsEmpty => 'No hay entradas desde el inicio de la app.';

  @override
  String get logsNoMatch => 'Ninguna entrada coincide con el filtro.';

  @override
  String get logsCopyButton => 'Copiar';

  @override
  String get logsSaveButton => 'Guardar registro como .txt';

  @override
  String bugReportSubject(String file) {
    return 'Auditorium: informe de error ($file)';
  }

  @override
  String bugReportText(String email) {
    return 'Informe de error de Auditorium – envíalo a $email.\nDescribe brevemente qué ocurrió y cuándo.\nEl registro adjunto solo contiene eventos técnicos, sin audio ni texto de la charla.';
  }

  @override
  String logShareSubject(String file) {
    return 'Auditorium: registro de la app ($file)';
  }

  @override
  String get logShareText => 'Registro de depuración de Auditorium';
}
