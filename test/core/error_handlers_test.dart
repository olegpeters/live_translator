import 'package:auditorium/core/logging/app_logger.dart';
import 'package:auditorium/core/logging/error_handlers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uncaught Flutter and Dart errors land in the session log', () {
    final savedFlutter = FlutterError.onError;
    final savedDispatcher = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = savedFlutter;
      PlatformDispatcher.instance.onError = savedDispatcher;
    });
    AppLogger.clear();
    FlutterError.onError = null;
    installErrorHandlers();

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));
    final handled = PlatformDispatcher.instance.onError!(ArgumentError('async'), StackTrace.current);

    expect(handled, isTrue);
    final crashes = AppLogger.logs.where((e) => e.tag == 'Crash').toList();
    expect(crashes, hasLength(2));
    expect(crashes.every((e) => e.level == LogLevel.error), isTrue);
    expect(crashes.first.message, contains('boom'));
  });
}
