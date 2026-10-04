import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/audio/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (MethodCall methodCall) async => null,
    );
  });

  group('AudioService & WAV Utilities', () {
    test('pcmToWav generates a valid 44-byte WAV header with PCM data', () {
      final samplePcm = Uint8List.fromList([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80]);
      final wav = pcmToWav(samplePcm, sampleRate: 24000, numChannels: 1, bitsPerSample: 16);

      expect(wav.length, 44 + samplePcm.length);

      // Verify "RIFF"
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // File size - 8 = 36 + 6 = 42
      final byteData = ByteData.sublistView(wav);
      expect(byteData.getUint32(4, Endian.little), 42);

      // Verify "WAVE"
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');

      // Verify "fmt "
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(byteData.getUint32(16, Endian.little), 16); // Subchunk1Size
      expect(byteData.getUint16(20, Endian.little), 1);  // AudioFormat (PCM)
      expect(byteData.getUint16(22, Endian.little), 1);  // NumChannels (1)
      expect(byteData.getUint32(24, Endian.little), 24000); // SampleRate (24000)
      expect(byteData.getUint32(28, Endian.little), 48000); // ByteRate (24000 * 1 * 2)
      expect(byteData.getUint16(32, Endian.little), 2);  // BlockAlign
      expect(byteData.getUint16(34, Endian.little), 16); // BitsPerSample

      // Verify "data"
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(byteData.getUint32(40, Endian.little), samplePcm.length);

      // Verify PCM payload
      expect(wav.sublist(44), samplePcm);
    });

    test('AudioService handles playAudioDelta and stopPlayback cleanly', () async {
      final service = AudioService();
      final chunk1 = Uint8List.fromList([1, 2, 3, 4]);
      final chunk2 = Uint8List.fromList([5, 6, 7, 8]);

      await expectLater(service.playAudioDelta(chunk1), completes);
      await expectLater(service.playAudioDelta(chunk2), completes);
      await expectLater(service.stopPlayback(), completes);
      await expectLater(service.dispose(), completes);
    });

    test('AudioService initialization and dispose lifecycle', () async {
      final service = AudioService();
      expect(service.isRecording, false);
      await service.stopPlayback();
      await service.dispose();
    });
  });
}
