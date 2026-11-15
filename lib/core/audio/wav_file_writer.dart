import 'dart:io';
import 'dart:typed_data';

import '../logging/app_logger.dart';

/// Streams PCM16 mono audio into a WAV file (diagnostics: exactly what is sent to STT).
///
/// The header is written with placeholder sizes and patched in [close].
class WavFileWriter {
  final String path;
  final int sampleRate;
  RandomAccessFile? _file;
  Future<void> _pending = Future.value();
  int _dataBytes = 0;
  bool _closed = false;

  WavFileWriter._(this.path, this.sampleRate);

  /// Prefix of diagnostic recordings in the documents directory.
  static const String filePrefix = 'mic_recording_';

  static Future<WavFileWriter> open(String path, {int sampleRate = 24000}) async {
    final writer = WavFileWriter._(path, sampleRate);
    writer._file = await File(path).open(mode: FileMode.write);
    await writer._file!.writeFrom(_header(sampleRate, 0));
    AppLogger.info('Mic recording started: $path', tag: 'WavFileWriter');
    return writer;
  }

  void add(Uint8List pcm) {
    if (_closed || pcm.isEmpty) return;
    _dataBytes += pcm.length;
    final file = _file;
    _pending = _pending.then((_) => file?.writeFrom(pcm));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final file = _file;
    _file = null;
    if (file == null) return;
    await _pending;
    await file.setPosition(0);
    await file.writeFrom(_header(sampleRate, _dataBytes));
    await file.close();
    AppLogger.info(
      'Mic recording saved: $path (${(_dataBytes / (sampleRate * 2)).toStringAsFixed(1)}s)',
      tag: 'WavFileWriter',
    );
  }

  static Uint8List _header(int sampleRate, int dataBytes) {
    final b = ByteData(44);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataBytes, Endian.little);
    return b.buffer.asUint8List();
  }
}
