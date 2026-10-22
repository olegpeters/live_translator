import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/logging/app_logger.dart';

void main() {
  setUp(() {
    AppLogger.clear();
  });

  test('AppLogger records log entries correctly', () {
    expect(AppLogger.logs, isEmpty);
    expect(AppLogger.logCountNotifier.value, equals(0));

    AppLogger.info('Test Info Message', tag: 'TestTag');
    expect(AppLogger.logs.length, equals(1));
    expect(AppLogger.logCountNotifier.value, equals(1));

    final entry = AppLogger.logs.first;
    expect(entry.message, equals('Test Info Message'));
    expect(entry.tag, equals('TestTag'));
    expect(entry.level, equals(LogLevel.info));
    expect(entry.levelString, equals('INFO'));
    expect(entry.toFormattedString(), contains('[INFO] [TestTag] Test Info Message'));
  });

  test('AppLogger handles error and warning levels', () {
    AppLogger.warning('Warning msg', tag: 'WarnTag');
    AppLogger.error('Error msg', tag: 'ErrTag', error: 'Exception 123');

    expect(AppLogger.logs.length, equals(2));
    expect(AppLogger.logs[0].level, equals(LogLevel.warning));
    expect(AppLogger.logs[1].level, equals(LogLevel.error));
    expect(AppLogger.logs[1].error, equals('Exception 123'));
    expect(AppLogger.logs[1].toFormattedString(), contains('Error: Exception 123'));
  });

  test('AppLogger exportFormattedLog creates full log text with headers', () {
    AppLogger.info('Sample event 1', tag: 'Audio');
    AppLogger.error('Sample event 2', tag: 'Network');

    final exportedText = AppLogger.exportFormattedLog();
    expect(exportedText, contains('Live Translator App Log'));
    expect(exportedText, contains('Total Log Entries: 2'));
    expect(exportedText, contains('[INFO] [Audio] Sample event 1'));
    expect(exportedText, contains('[ERROR] [Network] Sample event 2'));
  });

  test('AppLogger clear removes all entries', () {
    AppLogger.info('Line 1');
    AppLogger.info('Line 2');
    expect(AppLogger.logs.length, equals(2));

    AppLogger.clear();
    expect(AppLogger.logs, isEmpty);
    expect(AppLogger.logCountNotifier.value, equals(0));
  });
}
