import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/translation/translation_segmenter.dart';
import 'package:live_translator/core/translation/tts_stream_manager.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late List<TtsAudioEvent> audio;
  late TtsStreamManager mgr;

  void setUpMgr() {
    sent = [];
    audio = [];
    mgr = TtsStreamManager(
      send: sent.add,
      configFor: (id) => {'stream_id': id, 'model': 'tts-rt-v2'},
      onAudio: audio.add,
    );
  }

  List<String> configured() => sent.where((m) => m.containsKey('model')).map((m) => m['stream_id'] as String).toList();

  Map<String, dynamic> audioMsg(String id, {bool end = false}) =>
      {'stream_id': id, 'audio': base64Encode([1, 2]), 'audio_end': end};

  test('at most 4 streams are configured concurrently; the 5th waits for a termination', () {
    fakeAsync((async) {
      setUpMgr();
      for (var i = 0; i < 5; i++) {
        mgr.sendPiece(TextPiece('Satz $i.', isEnd: true));
      }
      expect(configured(), ['stream-2', 'stream-3', 'stream-4', 'stream-5']);

      mgr.handleMessage(audioMsg('stream-2', end: true));
      mgr.handleMessage({'stream_id': 'stream-2', 'terminated': true});
      expect(configured(), contains('stream-6'));
      // The waiting stream gets its accumulated text in one message, with text_end.
      final textForSix = sent.lastWhere((m) => m['stream_id'] == 'stream-6' && m.containsKey('text'));
      expect(textForSix['text'], 'Satz 4.');
      expect(textForSix['text_end'], isTrue);
      mgr.dispose();
    });
  });

  test('429 before any audio is retried with the same stream id (keeps playout order)', () {
    fakeAsync((async) {
      setUpMgr();
      mgr.sendPiece(const TextPiece('Привет.', isEnd: true));
      mgr.handleMessage({'stream_id': 'stream-2', 'error_code': 429, 'error_type': 'limit_exceeded'});
      mgr.handleMessage({'stream_id': 'stream-2', 'terminated': true});
      expect(audio, isEmpty); // no end marker: will be retried
      async.elapse(const Duration(milliseconds: 400));
      expect(configured(), ['stream-2', 'stream-2']);
      expect(sent.last['text'], 'Привет.');

      mgr.handleMessage(audioMsg('stream-2', end: true));
      expect(audio.single.sequenceNumber, 2000001);
      mgr.dispose();
    });
  });

  test('error after partial audio ends the stream instead of re-synthesizing', () {
    fakeAsync((async) {
      setUpMgr();
      mgr.sendPiece(const TextPiece('Привет, мир.', isEnd: true));
      mgr.handleMessage(audioMsg('stream-2'));
      mgr.handleMessage({'stream_id': 'stream-2', 'error_code': 408, 'error_type': 'request_timeout'});
      mgr.handleMessage({'stream_id': 'stream-2', 'terminated': true});
      expect(audio.last.isLast, isTrue);
      expect(audio.last.bytes, isEmpty);
      expect(configured(), ['stream-2']);
      mgr.dispose();
    });
  });

  test('connection reset re-sends streams without audio, ends streams with partial audio', () {
    fakeAsync((async) {
      setUpMgr();
      mgr.sendPiece(const TextPiece('Eins.', isEnd: true)); // stream-2, gets audio
      mgr.sendPiece(const TextPiece('Zwei.', isEnd: true)); // stream-3, no audio yet
      mgr.handleMessage(audioMsg('stream-2'));
      sent.clear();

      mgr.onConnectionReset();
      expect(audio.where((a) => a.streamId == 'stream-2' && a.isLast && a.bytes.isEmpty), hasLength(1));
      expect(configured(), ['stream-3']);
      expect(sent.last['text'], 'Zwei.');
      mgr.dispose();
    });
  });

  test('missing termination is covered by the end fallback', () {
    fakeAsync((async) {
      setUpMgr();
      mgr.sendPiece(const TextPiece('Hallo.', isEnd: true));
      async.elapse(TtsStreamManager.endFallbackTimeout);
      expect(audio.single.isLast, isTrue);
      expect(mgr.activeStreamCount, 0);
      mgr.dispose();
    });
  });

  test('first audio reports the TTS latency once', () {
    fakeAsync((async) {
      setUpMgr();
      mgr.sendPiece(const TextPiece('Hallo '));
      async.elapse(const Duration(milliseconds: 700));
      mgr.handleMessage(audioMsg('stream-2'));
      mgr.handleMessage(audioMsg('stream-2'));
      expect(audio[0].latencySeconds, closeTo(0.7, 0.01));
      expect(audio[1].latencySeconds, isNull);
      mgr.dispose();
    });
  });
}
