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

    test('Initial pre-roll requires target delay before pre-roll finishes', () {
      expect(buffer.isPreRolling, isTrue);
      expect(buffer.targetDelaySeconds, equals(AdaptiveTtsBuffer.initialTargetDelay));

      // Add 1.0 second of audio (less than initialTargetDelay 3.0s)
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(1.0),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);

      // Add another 2.0 seconds (total 3.0s >= 3.0s required target delay)
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(2.0),
        sequenceNumber: 2,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);
    });

    test('Mid-stream popping allows continuous playback without re-arming pre-roll barrier', () {
      // Complete pre-roll with 3.0s
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(3.0),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);

      final popped = buffer.popNextChunk();
      expect(popped, isNotNull);

      // Mid-stream pre-roll remains unblocked so newly arriving chunks play immediately
      expect(buffer.isPreRolling, isFalse);
    });

    test('Audio interruption below target delay re-arms pre-roll until buffer >= targetDelay again', () {
      // Complete initial pre-roll with 3.0s
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(3.0),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);

      // Pop chunk so buffer drains
      final popped = buffer.popNextChunk();
      expect(popped, isNotNull);
      expect(buffer.currentBufferDurationSeconds, equals(0.0));

      // Audio interruption (underrun) triggers rearmPreRoll()
      buffer.rearmPreRoll();

      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);

      // Add 1.0s chunk (< targetDelay 3.0s) -> playback does NOT start yet
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(1.0),
        sequenceNumber: 2,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);

      // Add another 2.0s chunk (total 3.0s >= targetDelay 3.0s) -> pre-roll completes and playback resumes
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(2.0),
        sequenceNumber: 3,
        streamId: 's1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);
    });

    test('isLastInStream flag flushes pre-roll for trailing audio once target delay has elapsed', () {
      // Add small 0.3s chunk marked as stream end, received a target delay ago
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.3),
        sequenceNumber: 1,
        streamId: 's1',
        isLastInStream: true,
        receivedAt: DateTime.now().subtract(const Duration(seconds: 3)),
      ));

      expect(buffer.isStreamEnding, isTrue);
      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);

      final popped = buffer.popNextChunk();
      expect(popped, isNotNull);
      expect(popped?.durationSeconds, closeTo(0.3, 0.01));
    });

    test('Out-of-order chunks are reordered and increase safety target delay', () {
      // Complete pre-roll with 3.0s
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(3.0),
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
      expect(buffer.targetDelaySeconds, greaterThan(3.0));

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

    test('Playback speed accelerates up to 2.0x when buffer accumulates extra audio', () {
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(8),
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

      expect(buffer.currentPlaybackSpeed, greaterThan(1.0));
      expect(buffer.currentPlaybackSpeed, lessThanOrEqualTo(2.0));
    });

    test('reportSectionLatency does not block speed acceleration', () {
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(8),
        sequenceNumber: 1,
        streamId: 's1',
      ));

      expect(buffer.currentPlaybackSpeed, greaterThan(1.0));

      buffer.reportSectionLatency(3.5);

      expect(buffer.targetDelaySeconds, closeTo(3.7, 0.01));
      // Speedup is still active despite section latency reporting
      expect(buffer.currentPlaybackSpeed, greaterThan(1.0));
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

    test('reportSectionLatency updates ttsLatencySeconds and adapts target delay', () {
      expect(buffer.ttsLatencySeconds, equals(0.0));
      expect(buffer.targetDelaySeconds, equals(3.0));
      buffer.reportSectionLatency(3.5);
      expect(buffer.ttsLatencySeconds, equals(3.5));
      expect(buffer.targetDelaySeconds, closeTo(3.7, 0.01));
    });

    test('reportSectionLatency updates ttsLatencySeconds but does not decrease target delay below current target', () {
      expect(buffer.ttsLatencySeconds, equals(0.0));
      expect(buffer.targetDelaySeconds, equals(3.0));
      buffer.reportSectionLatency(0.85);
      expect(buffer.ttsLatencySeconds, equals(0.85));
      expect(buffer.targetDelaySeconds, equals(3.0));
    });

    test('rearmPreRoll after stream end chunk maintains pre-roll barrier for subsequent utterance', () {
      // Stream s1 completes with isLastInStream
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(1.0),
        sequenceNumber: 1000001,
        streamId: 's1',
        isLastInStream: true,
        receivedAt: DateTime.now().subtract(const Duration(seconds: 3)),
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);

      final popped = buffer.popNextChunk();
      expect(popped, isNotNull);
      expect(buffer.currentBufferDurationSeconds, equals(0.0));

      // Buffer drains and rearms pre-roll
      buffer.rearmPreRoll();
      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);

      // New utterance s2 arrives (first chunk 1.0s < targetDelay 3.0s)
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(1.0),
        sequenceNumber: 2000001,
        streamId: 's2',
        isLastInStream: false,
      ));

      // Pre-roll MUST remain active until target delay is reached!
      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);

      // Add remaining 2.0s audio to hit target delay
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(2.0),
        sequenceNumber: 2000002,
        streamId: 's2',
        isLastInStream: false,
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);
    });

    test('ended short stream keeps pre-roll until target delay elapsed', () {
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.5),
        sequenceNumber: 1000001,
        streamId: 'stream-1',
        isLastInStream: true,
      ));

      expect(buffer.isStreamEnding, isTrue);
      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);
    });

    test('steady playback: chunk arriving into drained buffer does not re-arm pre-roll', () {
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(3.0),
        sequenceNumber: 1000001,
        streamId: 'stream-1',
      ));
      expect(buffer.popNextChunk(), isNotNull); // AudioService takes everything
      expect(buffer.currentBufferDurationSeconds, equals(0.0));

      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(0.2),
        sequenceNumber: 1000002,
        streamId: 'stream-1',
      ));

      expect(buffer.isPreRolling, isFalse);
      expect(buffer.hasAudioToPlay, isTrue);
    });

    test('interleaved chunks of consecutive streams are not out-of-order and do not re-arm pre-roll', () {
      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(3.0), sequenceNumber: 1000001, streamId: 'stream-1'));
      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(0.2), sequenceNumber: 2000001, streamId: 'stream-2'));
      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(0.2), sequenceNumber: 1000002, streamId: 'stream-1'));
      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(0.2), sequenceNumber: 2000002, streamId: 'stream-2'));

      expect(buffer.outOfOrderEvents, equals(0));
      expect(buffer.targetDelaySeconds, equals(3.0));
      expect(buffer.isPreRolling, isFalse);
      expect(buffer.popNextChunk()?.sequenceNumber, equals(1000001));
      expect(buffer.popNextChunk()?.sequenceNumber, equals(1000002));
    });

    test('end marker of another stream does not release pre-roll of current audio', () {
      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(0.5), sequenceNumber: 2000001, streamId: 'stream-2'));
      buffer.addChunk(SequencedAudioDelta(bytes: Uint8List(0), sequenceNumber: 1000009, streamId: 'stream-1', isLastInStream: true));

      expect(buffer.isPreRolling, isTrue);
      expect(buffer.hasAudioToPlay, isFalse);
    });

    test('next stream is held while previous stream still delivers; its tail is not dropped', () {
      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(3.0), sequenceNumber: 1000001, streamId: 'stream-1'));
      expect(buffer.popNextChunk()?.sequenceNumber, equals(1000001));

      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(1.0), sequenceNumber: 2000001, streamId: 'stream-2'));
      // stream-1 has not ended and delivered audio just now -> hold stream-2
      expect(buffer.hasAudioToPlay, isFalse);

      // stream-1 tail arrives late -> must be played, not dropped
      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(0.3), sequenceNumber: 1000002, streamId: 'stream-1', isLastInStream: true));
      expect(buffer.popNextChunk()?.sequenceNumber, equals(1000002));
      expect(buffer.popNextChunk()?.sequenceNumber, equals(2000001));
    });

    test('next stream starts once previous stream stalled longer than transition wait', () {
      buffer.addChunk(SequencedAudioDelta(
        bytes: generatePcmSeconds(3.0),
        sequenceNumber: 1000001,
        streamId: 'stream-1',
        receivedAt: DateTime.now().subtract(const Duration(seconds: 2)),
      ));
      expect(buffer.popNextChunk(), isNotNull);

      buffer.addChunk(SequencedAudioDelta(bytes: generatePcmSeconds(1.0), sequenceNumber: 2000001, streamId: 'stream-2'));
      expect(buffer.popNextChunk()?.sequenceNumber, equals(2000001));
    });
  });
}
