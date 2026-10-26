import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/audio/audio_service.dart';

void main() {
  group('AudioService helper functions', () {
    test('pcmToWav produces 44-byte header and appends PCM bytes', () {
      final pcmBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final wavBytes = pcmToWav(pcmBytes, sampleRate: 24000);

      expect(wavBytes.length, equals(44 + pcmBytes.length));

      // Check RIFF header magic bytes
      expect(wavBytes.sublist(0, 4), equals([0x52, 0x49, 0x46, 0x46])); // "RIFF"
      expect(wavBytes.sublist(8, 12), equals([0x57, 0x41, 0x56, 0x45])); // "WAVE"
      expect(wavBytes.sublist(12, 16), equals([0x66, 0x6D, 0x74, 0x20])); // "fmt "
      expect(wavBytes.sublist(36, 40), equals([0x64, 0x61, 0x74, 0x61])); // "data"

      // Verify payload
      expect(wavBytes.sublist(44), equals(pcmBytes));
    });

    test('amplifyPcm16 multiplies samples and clamps to 16-bit signed range', () {
      final ByteData byteData = ByteData(4);
      byteData.setInt16(0, 10000, Endian.little);
      byteData.setInt16(2, 20000, Endian.little);
      final original = byteData.buffer.asUint8List();

      final amplified = amplifyPcm16(original, 2.0);
      final ByteData resultData = ByteData.sublistView(amplified);

      expect(resultData.getInt16(0, Endian.little), equals(20000));
      // 20000 * 2 = 40000, clamped to max Int16 (32767)
      expect(resultData.getInt16(2, Endian.little), equals(32767));
    });

    test('amplifyPcm16 returns original bytes if gain is 1.0', () {
      final original = Uint8List.fromList([10, 20, 30, 40]);
      final amplified = amplifyPcm16(original, 1.0);
      expect(amplified, equals(original));
    });

    test('applyPcm16EdgeSmoothing returns unmodified bytes when fadeIn and fadeOut are false', () {
      final original = Uint8List.fromList(List.generate(200, (i) => i));
      final smoothed = applyPcm16EdgeSmoothing(original, fadeIn: false, fadeOut: false);
      expect(smoothed, equals(original));
    });

    test('applyPcm16EdgeSmoothing applies fade-in when fadeIn is true', () {
      final ByteData data = ByteData(200);
      for (int i = 0; i < 100; i++) {
        data.setInt16(i * 2, 10000, Endian.little);
      }
      final original = data.buffer.asUint8List();

      final smoothed = applyPcm16EdgeSmoothing(original, fadeIn: true, fadeOut: false, fadeSamples: 10);
      final ByteData resultData = ByteData.sublistView(smoothed);

      // First sample should be 0 (factor 0.0)
      expect(resultData.getInt16(0, Endian.little), equals(0));
      // Mid sample should be > 0 and < 10000
      expect(resultData.getInt16(10, Endian.little), greaterThan(0));
      expect(resultData.getInt16(10, Endian.little), lessThan(10000));
      // Samples past fadeSamples should remain original 10000
      expect(resultData.getInt16(30, Endian.little), equals(10000));
    });

    test('applyPcm16EdgeSmoothing applies fade-out when fadeOut is true', () {
      final ByteData data = ByteData(200);
      for (int i = 0; i < 100; i++) {
        data.setInt16(i * 2, 10000, Endian.little);
      }
      final original = data.buffer.asUint8List();

      final smoothed = applyPcm16EdgeSmoothing(original, fadeIn: false, fadeOut: true, fadeSamples: 10);
      final ByteData resultData = ByteData.sublistView(smoothed);

      // Start samples remain 10000
      expect(resultData.getInt16(0, Endian.little), equals(10000));
      // Last sample should be 0 (factor 0.0)
      expect(resultData.getInt16(198, Endian.little), equals(0));
    });
  });
}
