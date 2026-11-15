import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// Android-only platform helpers (no-ops elsewhere).
class AndroidPlatform {
  static const _channel = MethodChannel('live_translator/platform');

  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Keeps mic capture alive in the background (foreground service of type microphone).
  static Future<void> startForegroundService() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (e) {
      AppLogger.warning('Foreground service could not be started: $e', tag: 'AndroidPlatform');
    }
  }

  static Future<void> stopForegroundService() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }

  /// True if wired / USB / Bluetooth headphones are connected as audio output.
  static Future<bool> isHeadphoneConnected() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isHeadphoneConnected') ?? false;
    } catch (_) {
      return false;
    }
  }
}
