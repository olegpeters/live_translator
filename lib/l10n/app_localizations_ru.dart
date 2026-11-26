// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settings => 'Настройки';

  @override
  String get save => 'Сохранить';

  @override
  String get cancel => 'Отмена';

  @override
  String get delete => 'Удалить';

  @override
  String get understood => 'Понятно';

  @override
  String get homeSourceLanguage => 'Доклад';

  @override
  String get homeTargetLanguage => 'Перевод';

  @override
  String get homeStatus => 'Статус';

  @override
  String get homeTapToStart => 'Нажмите, чтобы начать';

  @override
  String get homeTapToStop => 'Нажмите, чтобы остановить';

  @override
  String get homeMicLevel => 'Уровень микрофона';

  @override
  String homeTranscriptTitle(String language) {
    return 'Перевод ($language)';
  }

  @override
  String get homeClearText => 'Очистить текст';

  @override
  String get homeTranscriptPlaceholder =>
      'Здесь в реальном времени появляются переведённые предложения...';

  @override
  String get homeSourceTranscriptTitle =>
      'Распознанный исходный текст – диагностика';

  @override
  String get homeSourceTranscriptPlaceholder =>
      'Здесь появляется исходный текст, распознанный моделью...';

  @override
  String get homeBufferTitle => 'Аудиобуфер TTS и синхронизация';

  @override
  String homeBufferTempo(String speed) {
    return 'Темп: ${speed}x';
  }

  @override
  String homeBufferPrerolling(String buffer, String target) {
    return 'Буферизация: $buffer с / цель: $target с...';
  }

  @override
  String homeBufferStatus(String buffer, String target) {
    return 'Буфер: $buffer с (цель: $target с)';
  }

  @override
  String homeBufferReorder(int count) {
    return 'Порядок скорректирован ($count)';
  }

  @override
  String homeLatency(String translation, String tts) {
    return 'Задержка: перевод $translation с  •  TTS $tts с';
  }

  @override
  String get statusIdle => 'Неактивно';

  @override
  String get statusConnecting => 'Подключение к Soniox...';

  @override
  String get statusActive => 'Синхронный перевод активен';

  @override
  String get statusFinishing =>
      'Завершение перевода (обработка предложений)...';

  @override
  String get statusConnectionError => 'Ошибка соединения';

  @override
  String statusReconnecting(int attempt, int max) {
    return 'Соединение прервано (попытка $attempt/$max)...';
  }

  @override
  String get statusDisconnected => 'Соединение разорвано.';

  @override
  String get statusCheckingKey => 'Проверка API-ключа...';

  @override
  String get statusKeyRejected =>
      'Ошибка: Soniox не принимает API-ключ. Проверьте его в настройках.';

  @override
  String get statusNoApiKey => 'Ошибка: в настройках не указан API-ключ.';

  @override
  String get statusInitializing => 'Инициализация...';

  @override
  String statusStartFailed(String error) {
    return 'Ошибка запуска: $error';
  }

  @override
  String get statusMicPermissionDenied =>
      'Нет доступа к микрофону. Разрешите его в настройках приложения Android.';

  @override
  String get homeOpenAppSettings => 'Открыть настройки приложения';

  @override
  String get statusStopping => 'Остановка...';

  @override
  String get langGerman => 'Немецкий';

  @override
  String get langEnglish => 'Английский';

  @override
  String get langAuto => 'Автоматически';

  @override
  String get langRussian => 'Русский';

  @override
  String get langUkrainian => 'Украинский';

  @override
  String get langSpanish => 'Испанский';

  @override
  String get langFrench => 'Французский';

  @override
  String get langArabic => 'Арабский';

  @override
  String get setupTitle => 'Введите API-ключ Soniox';

  @override
  String get setupIntro =>
      'Auditorium использует Soniox для распознавания речи, перевода и озвучивания. Введите свой API-ключ, чтобы начать.';

  @override
  String get apiKeyLabel => 'API-ключ Soniox';

  @override
  String get setupKeyRejected =>
      'Soniox не принимает этот API-ключ. Проверьте его.';

  @override
  String get setupSavedUnchecked =>
      'API-ключ сохранён. Сейчас его не удалось проверить (нет сети?); проверка выполнится при запуске перевода.';

  @override
  String get setupCreateAccount => 'Создать аккаунт Soniox';

  @override
  String setupLinkFailed(String url) {
    return 'Не удалось открыть ссылку: $url';
  }

  @override
  String get regionEu => 'Регион: ЕС – аудио и тексты обрабатываются в ЕС.';

  @override
  String get regionUs => 'Регион: США – аудио и тексты обрабатываются в США.';

  @override
  String get regionEuHowTo =>
      'Для обработки в ЕС: в консоли Soniox в разделе «Security & compliance» запросите регион ЕС, создайте проект в регионе ЕС и используйте его API-ключ.';

  @override
  String get settingsSonioxAccess => 'Доступ к Soniox';

  @override
  String get settingsSpeechOutput => 'Озвучивание';

  @override
  String get settingsVoice => 'Голос';

  @override
  String voiceMaleDefault(String name) {
    return '$name (мужской, по умолчанию)';
  }

  @override
  String voiceMale(String name) {
    return '$name (мужской)';
  }

  @override
  String voiceFemale(String name) {
    return '$name (женский)';
  }

  @override
  String get settingsGlossary => 'Глоссарий';

  @override
  String get settingsGlossaryPreset => 'Шаблон';

  @override
  String get settingsGlossaryPresetNone => 'Нет';

  @override
  String get settingsGlossaryPresetSermon => 'Проповедь';

  @override
  String get settingsGlossaryPresetHint =>
      'Книги Библии, имена, адвентистские термины и названия книг Эллен Уайт. Объединяется с вашим глоссарием; ваши записи имеют приоритет.';

  @override
  String get settingsOwnGlossary => 'Свой глоссарий (имена, термины)';

  @override
  String get settingsOwnGlossaryHint =>
      'Одна запись на строку, например\nAaron\nAnbetung = поклонение';

  @override
  String get settingsOwnGlossaryHelper =>
      'Термин = подсказка для распознавания; «Источник = Перевод» задаёт перевод.';

  @override
  String get settingsVolume => 'Громкость перевода';

  @override
  String get settingsGain => 'Усиление:';

  @override
  String get settingsGainHint =>
      'Делает озвученный перевод громче (100–300 %). По умолчанию: 200 %.';

  @override
  String get settingsHelp => 'Помощь';

  @override
  String get settingsReportBug => 'Сообщить об ошибке';

  @override
  String settingsReportBugHint(String email) {
    return 'Отправляет технический журнал (без аудио и текста доклада) по почте на $email. В меню «Поделиться» вы сами решаете, отправлять ли его и как.';
  }

  @override
  String get settingsNoLogEntries => 'Записей в журнале пока нет.';

  @override
  String settingsBugReportFailed(String error) {
    return 'Не удалось создать отчёт об ошибке: $error';
  }

  @override
  String get settingsDebugMode => 'Режим отладки';

  @override
  String get settingsDebugModeHint =>
      'Показывает технические значения (буфер, задержка) и параметры для поиска ошибок. Эти параметры действуют только при включённом режиме отладки.';

  @override
  String get settingsTtsEngine => 'Движок TTS (озвучивание)';

  @override
  String get ttsEngineSoniox => 'Soniox API (облачный стриминг)';

  @override
  String get ttsEngineOnboard => 'Встроенный Android TTS (локально)';

  @override
  String get settingsVoiceProcessing => 'Обработка голоса микрофона';

  @override
  String get settingsVoiceProcessingHint =>
      'Подавление эха и шума. С наушниками выкл. (иначе речь подавляется во время воспроизведения), с динамиком вкл.';

  @override
  String get voiceProcessingAuto => 'Автоматически (по наушникам)';

  @override
  String get voiceProcessingOn => 'Всегда вкл.';

  @override
  String get voiceProcessingOff => 'Всегда выкл.';

  @override
  String get settingsSourceTranscription => 'Транскрипция исходного текста';

  @override
  String get settingsSourceTranscriptionHint =>
      'Распознаёт и показывает исходный текст. Нужно только для отладки/диагностики. По умолчанию: выкл.';

  @override
  String get settingsMicRecording => 'Запись микрофона';

  @override
  String get settingsMicRecordingHint =>
      'Сохраняет отправленное в Soniox аудио микрофона за последний сеанс в формате WAV. Прикладывается к экспорту журнала. Только для диагностики.';

  @override
  String settingsAppLogs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '$count запись',
    );
    return 'Журнал приложения ($_temp0)';
  }

  @override
  String get settingsAppLogsHint =>
      'Показать журнал сеанса с момента запуска, скопировать его или сохранить как файл .txt.';

  @override
  String get settingsSaved => 'Настройки сохранены';

  @override
  String get settingsSavedKeyRejected =>
      'Сохранено, но Soniox не принимает API-ключ. Проверьте его.';

  @override
  String get settingsSavedUs =>
      'Сохранено. API-ключ относится к проекту Soniox в США.';

  @override
  String get settingsSavedUnchecked =>
      'Сохранено. API-ключ не удалось проверить (нет сети?); проверка при запуске.';

  @override
  String logsTitle(int count) {
    return 'Журнал ($count)';
  }

  @override
  String get logsCopyTooltip => 'Копировать в буфер обмена';

  @override
  String get logsShareTooltip => 'Сохранить / поделиться как текстовым файлом';

  @override
  String get logsDeleteTooltip => 'Удалить журнал';

  @override
  String get logsDeleteTitle => 'Удалить журнал?';

  @override
  String get logsDeleteConfirm =>
      'Вы действительно хотите удалить текущий временный журнал сеанса?';

  @override
  String get logsDeleted => 'Записи журнала удалены.';

  @override
  String get logsCopied => 'Весь журнал скопирован в буфер обмена.';

  @override
  String get logsNothingToSave => 'Нет записей для сохранения.';

  @override
  String get logsExported => 'Файл журнала экспортирован';

  @override
  String logsProvided(String path) {
    return 'Файл журнала доступен по пути $path';
  }

  @override
  String logsSaveFailed(String error) {
    return 'Не удалось сохранить файл журнала: $error';
  }

  @override
  String logsSessionInfo(String start, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '$count запись',
    );
    return 'Начало: $start • Всего: $_temp0';
  }

  @override
  String get logsAutoScroll => 'Автопрокрутка';

  @override
  String get logsSearchHint => 'Поиск (текст/тег)...';

  @override
  String get logsLevel => 'Уровень';

  @override
  String get logsAllLevels => 'Все уровни';

  @override
  String get logsEmpty => 'С момента запуска записей нет.';

  @override
  String get logsNoMatch => 'Нет записей, соответствующих фильтру.';

  @override
  String get logsCopyButton => 'Копировать';

  @override
  String get logsSaveButton => 'Сохранить журнал как .txt';

  @override
  String bugReportSubject(String file) {
    return 'Auditorium: отчёт об ошибке ($file)';
  }

  @override
  String bugReportText(String email) {
    return 'Отчёт об ошибке Auditorium – пожалуйста, отправьте на $email.\nКратко опишите, что произошло и когда.\nПриложенный журнал содержит только технические события – без аудио и текста доклада.';
  }

  @override
  String logShareSubject(String file) {
    return 'Auditorium: журнал приложения ($file)';
  }

  @override
  String get logShareText => 'Отладочный журнал Auditorium';
}
