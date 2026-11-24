import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../audio/wav_file_writer.dart';
import 'app_logger.dart';

/// Shares the session log via the system share sheet. Nothing is sent by the app itself:
/// the user picks the recipient (mail, messenger, files). No third-party crash reporting.
class LogReport {
  LogReport._();

  /// Writes the log to a temp file and opens the share sheet.
  /// [bugReport] adds a short request to describe the problem.
  /// Returns the file path, or null if the log is empty.
  static Future<(String path, ShareResultStatus status)?> share({bool bugReport = false}) async {
    if (AppLogger.logs.isEmpty) return null;

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final dateStr =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final fileName = 'auditorium_log_$dateStr.txt';

    final file = File('${(await getTemporaryDirectory()).path}/$fileName');
    await file.writeAsString(AppLogger.exportFormattedLog());

    final files = [XFile(file.path, mimeType: 'text/plain', name: fileName)];
    // Diagnostic mic recordings only exist in debug builds (see SettingsRepository.getMicRecording).
    final docsDir = await getApplicationDocumentsDirectory();
    await for (final entity in docsDir.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File && name.startsWith(WavFileWriter.filePrefix)) {
        files.add(XFile(entity.path, mimeType: 'audio/wav', name: name));
      }
    }

    final result = await SharePlus.instance.share(
      ShareParams(
        files: files,
        subject: bugReport ? 'Auditorium Fehlerbericht ($fileName)' : 'Auditorium App Log ($fileName)',
        text: bugReport
            ? 'Fehlerbericht Auditorium. Bitte beschreibe kurz, was passiert ist und wann.\n'
                'Das angehängte Protokoll enthält nur technische Ereignisse – kein Audio und keinen Vortragstext.'
            : 'Auditorium Debugging-Protokoll',
      ),
    );
    return (file.path, result.status);
  }
}
