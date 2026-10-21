import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/audio/adaptive_tts_buffer.dart';

void main() {
  group('AdaptiveTtsBuffer Tests', () {
    late AdaptiveTtsBuffer buffer;

    setUp(() {
      buffer = AdaptiveTtsBuffer();
    });

    tearDown(() {
      buffer.dispose();
    });

    // Helper: 1 second of PCM16 24kHz mono audio = 48,000 bytes
    Uint8List generatePcmSeconds(double seconds, {int sampleRate = 24000}) {
      final byteCount = (seconds * sampleRate * 2).toInt();
      return Uint8List(byteCount);
    }

    test('Initial pre-roll requires 0.4 seconds before pre-roll finishes', () {
      expect(buffer.isPreRolling, isTrue);
      expect(buffer.targetDelaySeconds, equals(0.4));

      // Add 0.2 seconds of audio
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.2),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);

      // Add another 0.2 seconds (total 0.4s)
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.2),
        sequenceNumber: 2,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);
    });

    test('Out-of-order chunks are reordered and increase safety target delay', () {
      // Complete pre-roll
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.5),
        sequenceNumber: 1000001,
        streamId: 'stream-1',
      ));

      expect(buffer.isPreRolling, isFalse);

      // Now chunk 3 arrives before chunk 2 (queue contains chunk 1)
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.2),
        sequenceNumber: 1000003,
        streamId: 'stream-1',
      ));

      expect(buffer.outOfOrderEvents, equals(1));
      expect(buffer.targetDelaySeconds, greaterThan(0.4));

      // Late chunk 2 arrives
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.2),
        sequenceNumber: 1000002,
        streamId: 'stream-1',
      ));

      // Pop next chunk should be chunk 1, then chunk 2, then chunk 3 (correct sequence order restored)
      final popped1 = buffer.popNextChunk();
      final popped2 = buffer.popNextChunk();
      final popped3 = buffer.popNextChunk();

      expect(popped1?.sequenceNumber, equals(1000001));
      expect(popped2?.sequenceNumber, equals(1000002));
      expect(popped3?.sequenceNumber, equals(1000003));
    });

    test('Playback speed accelerates up to 1.3x when buffer accumulates extra audio', () {
      // Add 2.0 seconds of audio (exceeding initial 0.4s target)
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(2.0),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.currentPlaybackSpeed, greaterThan(1.0));

      // Add more chunks to push speed towards 1.3x
      for (int i = 2; i <= 10; i++) {
        buffer.addChunk(SequencedAudioDelta(
          bytes: generatePcmSeconds(0.5),
          sequenceNumber: i,
          streamId: 's1',
        ));
      }

      expect(buffer.currentPlaybackSpeed, lessThanOrEqualTo(1.3));
    });

    test('flushPreRoll forces pre-roll completion immediately', () {
      // Add a small chunk (0.1s < target 0.4s) so pre-roll is still active
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.1),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isTrue);

      buffer.flushPreRoll();

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);
    });
  });
}
