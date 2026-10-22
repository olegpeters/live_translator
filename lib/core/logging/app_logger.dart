import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get levelString {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  String toFormattedString() {
    final timeStr = _formatTimestamp(timestamp);
    final buffer = StringBuffer('[$timeStr] [$levelString] [$tag] $message');
    if (error != null) {
      buffer.write('\n  Error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n  StackTrace:\n$stackTrace');
    }
    return buffer.toString();
  }

  static String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$y-$m-$d $hh:$mm:$ss.$ms';
  }
}

class AppLogger {
  static final DateTime sessionStart = DateTime.now();
  static final List<LogEntry> _logs = [];
  static const int _maxEntries = 2500;

  /// ValueNotifier that emits total entry count whenever logs are added or cleared.
  static final ValueNotifier<int> logCountNotifier = ValueNotifier<int>(0);

  /// Add a log entry to the temporary session log.
  static void log(
    String message, {
    String tag = 'App',
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    _logs.add(entry);
    if (_logs.length > _maxEntries) {
      _logs.removeAt(0);
    }

    logCountNotifier.value = _logs.length;

    if (kDebugMode) {
      debugPrint(entry.toFormattedString());
    }
  }

  static void info(
    String message, {
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      tag: tag,
      level: LogLevel.info,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void warning(
    String message, {
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      tag: tag,
      level: LogLevel.warning,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(
    String message, {
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      tag: tag,
      level: LogLevel.error,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void debug(
    String message, {
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      tag: tag,
      level: LogLevel.debug,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Get unmodifiable list of log entries since session start.
  static List<LogEntry> get logs => List.unmodifiable(_logs);

  /// Clear all stored log entries for this session.
  static void clear() {
    _logs.clear();
    logCountNotifier.value = 0;
  }

  /// Generate full formatted text string for export.
  static String exportFormattedLog() {
    final now = DateTime.now();
    final buffer = StringBuffer();
    buffer.writeln('==================================================');
    buffer.writeln('Live Translator App Log');
    buffer.writeln('App Launch: ${LogEntry._formatTimestamp(sessionStart)}');
    buffer.writeln('Export Time: ${LogEntry._formatTimestamp(now)}');
    buffer.writeln('Total Log Entries: ${_logs.length}');
    buffer.writeln('==================================================\n');

    if (_logs.isEmpty) {
      buffer.writeln('(Keine Log-Einträge vorhanden)');
    } else {
      for (final entry in _logs) {
        buffer.writeln(entry.toFormattedString());
      }
    }

    return buffer.toString();
  }
}
