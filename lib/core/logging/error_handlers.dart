import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Routes uncaught Flutter and Dart errors into the local session log, so a user can
/// send them via "Fehler melden". Nothing leaves the device automatically.
void installErrorHandlers() {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.error(
      'Flutter-Fehler: ${details.exceptionAsString()}',
      tag: 'Crash',
      error: details.exception,
      stackTrace: details.stack,
    );
    previousFlutterHandler?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.error('Unbehandelter Fehler', tag: 'Crash', error: error, stackTrace: stack);
    return true; // handled: keep the app (and a running translation) alive
  };
}
