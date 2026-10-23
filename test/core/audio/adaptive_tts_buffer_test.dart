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

    test('Initial pre-roll requires 1.0 second before pre-roll finishes', () {
      expect(buffer.isPreRolling, isTrue);
      expect(buffer.targetDelaySeconds, equals(1.0));

      // Add 0.5 second of audio
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.5),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);

      // Add another 0.5 second (total 1.0s)
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.5),
        sequenceNumber: 2,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);
    });

    test('Underrun re-arms pre-roll when remaining buffer drops below 0.4s during active stream', () {
      // Complete pre-roll with 1.0s
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(1.0),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);

      // Pop 0.7s chunk (leaves 0.3s remaining < 0.4s threshold)
      final popped = buffer.popNextChunk();
      expect(popped, isNotNull);

      // Since active stream is NOT ending and remaining buffer dropped below 0.4s, pre-roll re-arms
      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);
    });

    test('isLastInStream flag flushes pre-roll for trailing audio playback', () {
      // Add small 0.3s chunk marked as stream end
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.3),
        sequenceNumber: 1,
        streamId: 's1',
        isLastInStream: true,
      ));

      expect(buffer.isStreamEnding, isTrue);
      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);

      final popped = buffer.popNextChunk();
      expect(popped, isNotNull);
      expect(popped?.durationSeconds, closeTo(0.3, 0.01));
    });

    test('Out-of-order chunks are reordered and increase safety target delay', () {
      // Complete pre-roll with 1.0s
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(1.0),
        sequenceNumber: 1000001,
        streamId: 'stream-1',
      ));

      expect(buffer.isPreRolling, isFalse);

      // Now chunk 3 arrives before chunk 2
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.5),
        sequenceNumber: 1000003,
        streamId: 'stream-1',
      ));

      expect(buffer.outOfOrderEvents, equals(1));
      expect(buffer.targetDelaySeconds, greaterThan(1.0));

      // Late chunk 2 arrives
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.5),
        sequenceNumber: 1000002,
        streamId: 'stream-1',
      ));

      final popped1 = buffer.popNextChunk();
      final popped2 = buffer.popNextChunk();
      final popped3 = buffer.popNextChunk();

      expect(popped1?.sequenceNumber, equals(1000001));
      expect(popped2?.sequenceNumber, equals(1000002));
      expect(popped3?.sequenceNumber, equals(1000003));
    });

    test('Playback speed accelerates up to 1.3x when buffer accumulates extra audio', () {
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(2.5),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.currentPlaybackSpeed, greaterThan(1.0));

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
