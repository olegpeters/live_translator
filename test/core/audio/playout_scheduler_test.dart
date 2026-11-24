import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auditorium/core/audio/pcm_stream_player.dart';
import 'package:auditorium/core/audio/playout_scheduler.dart';

const int rate = 24000;

/// Simulated gapless output: consumes queued audio in (fake) real time at the current speed.
class FakePcmOutput implements PcmOutput {
  final _status = StreamController<PcmOutputStatus>.broadcast(sync: true);
  final List<(String, int)> writes = []; // (segmentId, frames)
  final List<double> speeds = [];
  Timer? _timer;
  double _queuedFrames = 0;
  int _played = 0;
  int _written = 0;
  double _speed = 1.0;

  /// Ticks where the device ran dry while audio had been played before.
  int idleTicks = 0;

  @override
  Stream<PcmOutputStatus> get status => _status.stream;

  @override
  double get queuedSeconds => _queuedFrames / rate;

  @override
  Future<void> start({int sampleRate = 24000}) async {
    _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      final consume = math.min(_queuedFrames, rate * 0.05 * _speed);
      _queuedFrames -= consume;
      _played += consume.round();
      _status.add(PcmOutputStatus(
        playedFrames: _played,
        writtenFrames: _written,
        queuedFrames: _queuedFrames.round(),
        sampleRate: rate,
        speed: _speed,
      ));
    });
  }

  @override
  Future<void> write(Uint8List pcm, {required String segmentId}) async {
    final frames = pcm.length ~/ 2;
    _queuedFrames += frames;
    _written += frames;
    writes.add((segmentId, frames));
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    speeds.add(speed);
  }

  @override
  Future<void> flush() async => _queuedFrames = 0;

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  List<String> get segmentOrder {
    final order = <String>[];
    for (final (id, _) in writes) {
      if (order.isEmpty || order.last != id) order.add(id);
    }
    return order;
  }
}

/// Speech-like PCM (440 Hz sine, -12 dBFS).
Uint8List speech(double seconds) {
  final n = (seconds * rate).round();
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    b.setInt16(i * 2, (8000 * math.sin(2 * math.pi * 440 * i / rate)).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

Uint8List silence(double seconds) => Uint8List((seconds * rate).round() * 2);

Uint8List concat(List<Uint8List> parts) {
  final bb = BytesBuilder();
  for (final p in parts) {
    bb.add(p);
  }
  return bb.takeBytes();
}

SequencedAudioDelta chunk(int stream, int idx, Uint8List bytes, {bool last = false, SegmentBoundary? boundary}) =>
    SequencedAudioDelta(
      bytes: bytes,
      sequenceNumber: stream * 1000000 + idx,
      streamId: 'stream-$stream',
      isLastInStream: last,
      boundary: boundary,
    );

void main() {
  late FakePcmOutput output;
  late PlayoutScheduler scheduler;

  void setUpScheduler() {
    output = FakePcmOutput();
    scheduler = PlayoutScheduler(output: output);
    scheduler.start();
  }

  void tearDownScheduler() {
    scheduler.dispose();
    output.stop();
  }

  test('segment waits for the target delay before starting (unless complete)', () {
    fakeAsync((async) {
      setUpScheduler();
      scheduler.addChunk(chunk(2, 1, speech(0.5)));
      async.elapse(const Duration(milliseconds: 1000));
      expect(output.writes, isEmpty);
      expect(scheduler.isPreRolling, isTrue);

      async.elapse(Duration(milliseconds: (PlayoutScheduler.initialTargetDelay * 1000).round()));
      expect(output.writes, isNotEmpty);
      tearDownScheduler();
    });
  });

  test('complete segment starts immediately', () {
    fakeAsync((async) {
      setUpScheduler();
      scheduler.addChunk(chunk(2, 1, speech(0.5), last: true));
      async.elapse(const Duration(milliseconds: 60));
      expect(output.writes, isNotEmpty);
      tearDownScheduler();
    });
  });

  test('segments play in stream order even if a later stream arrives first', () {
    fakeAsync((async) {
      setUpScheduler();
      scheduler.addChunk(chunk(2, 1, speech(0.3), last: true));
      async.elapse(const Duration(milliseconds: 2000));
      // stream-4 arrives before stream-3
      scheduler.addChunk(chunk(4, 1, speech(0.3), last: true));
      async.elapse(const Duration(milliseconds: 300));
      scheduler.addChunk(chunk(3, 1, speech(0.3), last: true));
      async.elapse(const Duration(milliseconds: 3000));
      expect(output.segmentOrder, ['stream-2', 'stream-3', 'stream-4']);
      tearDownScheduler();
    });
  });

  test('chunks of an already finished segment are dropped, not played out of order', () {
    fakeAsync((async) {
      setUpScheduler();
      scheduler.addChunk(chunk(2, 1, speech(0.3), last: true));
      async.elapse(const Duration(milliseconds: 1000));
      final writes = output.writes.length;
      scheduler.addChunk(chunk(2, 2, speech(0.3)));
      async.elapse(const Duration(milliseconds: 1000));
      expect(output.writes.length, writes);
      expect(scheduler.outOfOrderEvents, 1);
      tearDownScheduler();
    });
  });

  test('leading TTS silence is trimmed and a sentence pause is inserted between segments', () {
    fakeAsync((async) {
      setUpScheduler();
      scheduler.addChunk(chunk(2, 1, concat([silence(0.5), speech(0.5), silence(0.6)]),
          last: true, boundary: SegmentBoundary.sentence));
      scheduler.addChunk(chunk(3, 1, concat([silence(0.4), speech(0.5)]), last: true));
      async.elapse(const Duration(seconds: 3));

      final framesBySegment = <String, int>{};
      for (final (id, frames) in output.writes) {
        framesBySegment[id] = (framesBySegment[id] ?? 0) + frames;
      }
      // stream-2: 30ms kept before + 0.5s speech + 30ms kept after; rest of the trailing
      // silence (0.57s) is replaced by the sentence pause
      expect(framesBySegment['stream-2']! / rate, closeTo(0.56, 0.015));
      // stream-3: sentence pause (0.35s, written with stream-3 id) + 0.03 keep + 0.5s speech
      expect(framesBySegment['stream-3']! / rate, closeTo(0.35 + 0.53, 0.02));
      expect(scheduler.targetDelaySeconds, closeTo(PlayoutScheduler.initialTargetDelay * 0.85 * 0.85, 0.01));
      tearDownScheduler();
    });
  });

  test('bursty text arrival: start delay is learned so later segments do not starve', () {
    fakeAsync((async) {
      setUpScheduler();
      // Each sentence: 3 bursts of 1.2s audio arriving 1.6s apart (translation bursts),
      // i.e. a 1.2s-sentence part, then nothing while the next clause is being translated.
      var stream = 2;
      for (var sentence = 0; sentence < 6; sentence++) {
        for (var burst = 0; burst < 3; burst++) {
          scheduler.addChunk(chunk(stream, burst + 1, speech(1.2), last: burst == 2));
          async.elapse(const Duration(milliseconds: 1600));
        }
        stream++;
        async.elapse(const Duration(milliseconds: 500));
      }
      async.elapse(const Duration(seconds: 15));

      // need = max(arrival - first - audioBefore) = 3.2 - 2.4 = 0.8s -> target ~1.1s
      expect(scheduler.targetDelaySeconds, closeTo(1.1, 0.15));
      expect(scheduler.underruns, 0);
      tearDownScheduler();
    });
  });

  test('starvation mid-segment is detected and raises the start delay', () {
    fakeAsync((async) {
      setUpScheduler();
      scheduler.addChunk(chunk(2, 1, speech(0.3)));
      async.elapse(const Duration(milliseconds: 2600)); // starts after 2.5s
      async.elapse(const Duration(milliseconds: 2000)); // 0.3s played, then dry, stream not ended
      expect(scheduler.underruns, 1);
      expect(scheduler.targetDelaySeconds, greaterThan(PlayoutScheduler.initialTargetDelay));
      tearDownScheduler();
    });
  });

  test('large backlog: pauses shortened and speed ramps up gently, capped at 1.25x', () {
    fakeAsync((async) {
      setUpScheduler();
      for (var s = 2; s < 14; s++) {
        scheduler.addChunk(chunk(s, 1, speech(1.0), last: true));
      }
      async.elapse(const Duration(seconds: 2));
      expect(scheduler.pauseScale, lessThan(1.0));
      expect(scheduler.currentPlaybackSpeed, greaterThan(1.0));

      // Ramp: never jumps more than one step
      for (var i = 1; i < output.speeds.length; i++) {
        expect((output.speeds[i] - output.speeds[i - 1]).abs(), lessThanOrEqualTo(0.051));
      }
      expect(output.speeds.reduce(math.max), lessThanOrEqualTo(PlayoutScheduler.maxCatchUpSpeed));

      async.elapse(const Duration(seconds: 20));
      expect(scheduler.backlogSeconds, closeTo(0, 0.01));
      tearDownScheduler();
    });
  });

  test('flushPreRoll plays queued audio immediately', () {
    fakeAsync((async) {
      setUpScheduler();
      scheduler.addChunk(chunk(2, 1, speech(0.5)));
      scheduler.flushPreRoll();
      async.elapse(const Duration(milliseconds: 60));
      expect(output.writes, isNotEmpty);
      tearDownScheduler();
    });
  });

  test('receivedAt uses the injectable clock', () {
    fakeAsync((async) {
      final before = clock.now();
      async.elapse(const Duration(seconds: 5));
      final d = chunk(2, 1, speech(0.1));
      expect(d.receivedAt.difference(before).inSeconds, 5);
    });
  });
}
