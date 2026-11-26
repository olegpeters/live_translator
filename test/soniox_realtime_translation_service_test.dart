import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:auditorium/core/network/soniox_realtime_translation_service.dart';
import 'package:auditorium/core/translation/glossary.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> sent = [];
  bool closed = false;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWebSocketChannel implements WebSocketChannel {
  final StreamController<dynamic> incoming = StreamController<dynamic>.broadcast();
  final FakeWebSocketSink fakeSink = FakeWebSocketSink();

  @override
  Stream get stream => incoming.stream;

  @override
  WebSocketSink get sink => fakeSink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void serverSend(dynamic data) {
    if (data is Map<String, dynamic>) {
      incoming.add(jsonEncode(data));
    } else {
      incoming.add(data);
    }
  }

  List<dynamic> get rawSent => fakeSink.sent;

  List<Map<String, dynamic>> get jsonSent {
    final list = <Map<String, dynamic>>[];
    for (final item in fakeSink.sent) {
      if (item is String) {
        try {
          list.add(jsonDecode(item) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    return list;
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void sendTranslation(FakeWebSocketChannel stt, String text) => stt.serverSend({
      'tokens': [
        {'text': text, 'translation_status': 'translation', 'is_final': true}
      ],
    });

void sendEnd(FakeWebSocketChannel stt) => stt.serverSend({
      'tokens': [
        {'text': '<end>', 'is_final': true}
      ],
    });

void main() {
  group('SonioxRealtimeTranslationService basics', () {
    test('initial state is disconnected', () async {
      final service = SonioxRealtimeTranslationService();
      expect(service.currentState, TranslationConnectionState.disconnected);
      await service.dispose();
    });

    test('dispose cleans up controllers without throwing', () async {
      final service = SonioxRealtimeTranslationService();
      await expectLater(service.dispose(), completes);
    });
  });

  group('SonioxRealtimeTranslationService with fake channels', () {
    late FakeWebSocketChannel sttChannel;
    late FakeWebSocketChannel ttsChannel;
    late SonioxRealtimeTranslationService service;

    setUp(() {
      sttChannel = FakeWebSocketChannel();
      ttsChannel = FakeWebSocketChannel();

      service = SonioxRealtimeTranslationService(
        channelFactory: (uri, headers) {
          if (uri.host.contains('stt-rt')) {
            return sttChannel;
          } else {
            return ttsChannel;
          }
        },
      );
    });

    tearDown(() async {
      await service.dispose();
      await sttChannel.incoming.close();
      await ttsChannel.incoming.close();
    });

    test('connect uses the endpoints of the given region, reconnect keeps it', () async {
      final hosts = <String>[];
      final regional = SonioxRealtimeTranslationService(
        channelFactory: (uri, headers) {
          hosts.add(uri.host);
          return uri.host.contains('stt-rt') ? sttChannel : ttsChannel;
        },
      );
      await regional.connect(apiKey: 'k', targetLanguage: 'ru', region: SonioxRegion.us);
      expect(hosts, ['stt-rt.soniox.com', 'tts-rt.soniox.com']);
      await regional.dispose();
    });

    test('default region is EU', () async {
      final hosts = <String>[];
      final regional = SonioxRealtimeTranslationService(
        channelFactory: (uri, headers) {
          hosts.add(uri.host);
          return uri.host.contains('stt-rt') ? sttChannel : ttsChannel;
        },
      );
      await regional.connect(apiKey: 'k', targetLanguage: 'ru');
      expect(hosts, ['stt-rt.eu.soniox.com', 'tts-rt.eu.soniox.com']);
      await regional.dispose();
    });

    test('reading aloud off: no TTS connection, translations are text only', () async {
      final hosts = <String>[];
      final textOnly = SonioxRealtimeTranslationService(
        channelFactory: (uri, headers) {
          hosts.add(uri.host);
          return uri.host.contains('stt-rt') ? sttChannel : ttsChannel;
        },
      );
      await textOnly.connect(apiKey: 'k', targetLanguage: 'ru', speechEnabled: false);
      expect(hosts, ['stt-rt.eu.soniox.com']);

      final text = textOnly.onTranscriptDelta.first;
      sendTranslation(sttChannel, 'Доброе утро. ');
      sendEnd(sttChannel);
      expect(await text, 'Доброе утро. ');
      await pump();
      expect(ttsChannel.rawSent, isEmpty);
      await textOnly.dispose();
    });

    test('switching reading aloud on speaks the resume text first, then continues live', () async {
      await service.connect(apiKey: 'k', targetLanguage: 'ru', speechEnabled: false);
      sendTranslation(sttChannel, 'Первое. Второе предложение. Третье ');
      await pump();
      expect(ttsChannel.rawSent, isEmpty);

      await service.setSpeechEnabled(true, resumeText: 'Второе предложение. Третье ');
      sendTranslation(sttChannel, 'идёт дальше.');
      sendEnd(sttChannel);
      await pump();

      final texts = ttsChannel.jsonSent.where((m) => m.containsKey('text')).toList();
      final streams = <String, String>{};
      for (final m in texts) {
        streams[m['stream_id'] as String] = (streams[m['stream_id']] ?? '') + (m['text'] as String);
      }
      expect(streams.values.toList(), ['Второе предложение.', 'Третье идёт дальше.']);
    });

    test('switching reading aloud off closes the TTS connection and stops feeding it', () async {
      await service.connect(apiKey: 'k', targetLanguage: 'ru');
      sendTranslation(sttChannel, 'Раз два ');
      await pump();
      final sentBefore = ttsChannel.rawSent.length;
      expect(sentBefore, greaterThan(0));

      await service.setSpeechEnabled(false);
      expect(ttsChannel.fakeSink.closed, isTrue);
      sendTranslation(sttChannel, 'три. Четыре. ');
      sendEnd(sttChannel);
      await pump();
      expect(ttsChannel.rawSent.length, sentBefore);
      expect(service.speechEnabled, isFalse);
    });

    test('connect sends STT config and TTS config', () async {
      final connected = service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
        voice: 'Daniel',
      );
      await connected;

      expect(service.currentState, TranslationConnectionState.connected);
      expect(service.isReady, isTrue);

      final sttConfigs = sttChannel.jsonSent;
      expect(sttConfigs, hasLength(1));
      expect(sttConfigs.first.containsKey('api_key'), isFalse);
      expect(sttConfigs.first['model'], 'stt-rt-v6');
      expect(sttConfigs.first['translation']['target_language'], 'ru');

      sttChannel.serverSend({
        'tokens': [
          {
            'text': 'Доброе утро',
            'translation_status': 'translation',
          }
        ],
      });
      await pump();

      final ttsConfigs = ttsChannel.jsonSent;
      expect(ttsConfigs.length, greaterThanOrEqualTo(1));
      expect(ttsConfigs.first['model'], 'tts-rt-v2');
      expect(ttsConfigs.first['language'], 'ru');
      expect(ttsConfigs.first['voice'], 'Daniel');
    });

    test('audio chunks are buffered and sent as binary frames to STT', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      for (var i = 0; i < 3; i++) {
        service.sendAudioChunk(Uint8List(3200)..fillRange(0, 3200, i + 1));
      }

      final binaryFrames = sttChannel.rawSent.whereType<Uint8List>().toList();
      // Total bytes sent: 3 * 3200 = 9600 bytes. At frameBytes = 2400 (50ms), yields 4 frames.
      expect(binaryFrames, hasLength(4));
      expect(binaryFrames.first.length, 2400);
      expect(binaryFrames.first[0], 1);
    });

    test('STT original tokens emit source transcript', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      final future = service.onSourceTranscriptDelta.first;
      sttChannel.serverSend({
        'tokens': [
          {
            'text': 'Guten Morgen',
            'translation_status': 'original',
          }
        ],
      });

      expect(await future, 'Guten Morgen');
    });

    test('STT translation tokens emit target transcript and pipe to TTS', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      final future = service.onTranscriptDelta.first;
      sttChannel.serverSend({
        'tokens': [
          {
            'text': 'Доброе утро.',
            'translation_status': 'translation',
          }
        ],
      });

      expect(await future, 'Доброе утро.');

      // Sentence end is only confirmed by following whitespace or the STT endpoint.
      sendEnd(sttChannel);
      await pump();

      final ttsSent = ttsChannel.jsonSent;
      expect(ttsSent.first['model'], 'tts-rt-v2');
      final combinedTtsText = ttsSent
          .where((m) => m.containsKey('text'))
          .map((m) => m['text'] as String)
          .join();
      expect(combinedTtsText, 'Доброе утро.');
      expect(ttsSent.last['text_end'], isTrue);
    });

    test('TTS incoming audio is base64 decoded and emitted on onAudioDelta', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      sendTranslation(sttChannel, 'Привет,');
      await pump();
      final future = service.onAudioDelta.first;
      final payload = base64Encode([10, 20, 30, 40]);
      ttsChannel.serverSend({
        'stream_id': 'stream-2',
        'audio': payload,
        'audio_end': false,
      });

      final delta = await future;
      expect(delta.bytes, [10, 20, 30, 40]);
      expect(delta.sampleRate, 24000);
    });

    test('confirmed sentence end closes the TTS stream; commas keep it open', () async {
      await service.connect(apiKey: 'soniox-test-key', targetLanguage: 'ru');

      sendTranslation(sttChannel, 'Здравствуйте.');
      await pump();
      sendTranslation(sttChannel, ' Эм,');
      await pump();
      sendTranslation(sttChannel, ' да');
      await pump();

      final textMessages = ttsChannel.jsonSent.where((m) => m.containsKey('text')).toList();
      expect(textMessages, hasLength(2));
      expect(textMessages[0]['text'], 'Здравствуйте.');
      expect(textMessages[0]['text_end'], isTrue);
      expect(textMessages[0]['stream_id'], 'stream-2');
      expect(textMessages[1]['text'], 'Эм,');
      expect(textMessages[1]['text_end'], isFalse);
      expect(textMessages[1]['stream_id'], 'stream-3');
    });

    test('utterance end sends text_end true and new utterance starts new stream', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      sttChannel.serverSend({
        'tokens': [
          {
            'text': 'Здравствуйте.',
            'translation_status': 'translation',
          }
        ],
      });
      await pump();

      // Signal utterance end
      sttChannel.serverSend({
        'tokens': [
          {
            'text': '<end>',
          }
        ],
      });
      await pump();

      final ttsSent1 = ttsChannel.jsonSent;
      final endMsg = ttsSent1.last;
      expect(endMsg['text_end'], isTrue);
      expect(endMsg['stream_id'], equals('stream-2'));

      // New utterance starts stream-3
      sendTranslation(sttChannel, ' Понятно.');
      sendEnd(sttChannel);
      await pump();

      final lastTextMsg = ttsChannel.jsonSent.last;
      expect(lastTextMsg['stream_id'], equals('stream-3'));
      expect(lastTextMsg['text'], equals('Понятно.'));
      expect(lastTextMsg['text_end'], isTrue);
    });

    test('interleaved audio chunks from stream-2 and stream-3 are emitted in strict stream sequence', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      final receivedAudio = <Uint8List>[];
      final sub = service.onAudioDelta.listen((delta) {
        receivedAudio.add(delta.bytes);
      });

      // Start stream-2
      sttChannel.serverSend({
        'tokens': [
          {'text': 'Sentence one.', 'translation_status': 'translation'}
        ],
      });
      await pump();

      // Signal utterance end to start stream-3 on next text
      sttChannel.serverSend({
        'tokens': [
          {'text': '<end>'}
        ],
      });
      await pump();

      // Start stream-3
      sttChannel.serverSend({
        'tokens': [
          {'text': 'Sentence two.', 'translation_status': 'translation'}
        ],
      });
      sendEnd(sttChannel);
      await pump();

      // Interleaved server response: stream-2 chunk A, stream-3 chunk 1, stream-2 chunk B (final), stream-3 chunk 2
      ttsChannel.serverSend({
        'stream_id': 'stream-2',
        'audio': base64Encode([1, 1, 1]),
      });
      ttsChannel.serverSend({
        'stream_id': 'stream-3',
        'audio': base64Encode([2, 2, 2]),
      });
      ttsChannel.serverSend({
        'stream_id': 'stream-2',
        'audio': base64Encode([1, 1, 2]),
        'audio_end': true,
      });
      ttsChannel.serverSend({
        'stream_id': 'stream-3',
        'audio': base64Encode([2, 2, 3]),
        'audio_end': true,
      });
      await pump();

      // Verify all audio deltas are emitted with their corresponding stream_id
      expect(receivedAudio, hasLength(4));
      expect(receivedAudio[0], equals([1, 1, 1]));
      expect(receivedAudio[1], equals([2, 2, 2]));
      expect(receivedAudio[2], equals([1, 1, 2]));
      expect(receivedAudio[3], equals([2, 2, 3]));

      await sub.cancel();
    });

    test('audio after stream termination is dropped; audio before termination is kept', () async {
      await service.connect(apiKey: 'soniox-test-key', targetLanguage: 'ru');
      final received = <AudioDelta>[];
      final sub = service.onAudioDelta.listen(received.add);

      sendTranslation(sttChannel, 'Sentence one.');
      sendEnd(sttChannel);
      await pump();

      ttsChannel.serverSend({'stream_id': 'stream-2', 'audio': base64Encode([10, 10]), 'audio_end': true});
      ttsChannel.serverSend({'stream_id': 'stream-2', 'terminated': true});
      await pump();
      ttsChannel.serverSend({'stream_id': 'stream-2', 'audio': base64Encode([99, 99])});
      await pump();

      expect(received.map((d) => d.bytes.toList()), [
        [10, 10],
      ]);
      expect(received.single.isLastInStream, isTrue);
      expect(received.single.sequenceNumber, 2000001);
      await sub.cancel();
    });

    test('gracefulStop sends close markers to both STT and active TTS stream', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      // Send a translation token to activate a TTS stream
      sttChannel.serverSend({
        'tokens': [
          {
            'text': 'Привет',
            'translation_status': 'translation',
          }
        ],
      });
      await pump();

      service.sendAudioChunk(Uint8List(1000)..fillRange(0, 1000, 5));
      await service.gracefulStop();

      expect(sttChannel.rawSent.any((e) => e is String && e.isEmpty), isTrue);

      final ttsSent = ttsChannel.jsonSent;
      expect(ttsSent.any((msg) => msg['text_end'] == true), isTrue);
      expect(service.currentState, TranslationConnectionState.closing);
    });

    test('reconnect within session keeps TTS stream sequence numbers monotonic', () async {
      await service.connect(apiKey: 'k', targetLanguage: 'ru');
      final deltas = <AudioDelta>[];
      final sub = service.onAudioDelta.listen(deltas.add);

      sttChannel.serverSend({
        'tokens': [
          {'text': 'Привет.', 'translation_status': 'translation', 'is_final': true},
        ],
      });
      sendEnd(sttChannel);
      await pump();
      final firstStream = ttsChannel.jsonSent.firstWhere((m) => m.containsKey('model'))['stream_id'];
      ttsChannel.serverSend({'audio': base64Encode([1, 2]), 'stream_id': firstStream});
      await pump();

      await service.close();
      await service.connect(apiKey: 'k', targetLanguage: 'ru', newSession: false);

      sttChannel.serverSend({
        'tokens': [
          {'text': 'Снова.', 'translation_status': 'translation', 'is_final': true},
        ],
      });
      sendEnd(sttChannel);
      await pump();
      final secondStream = ttsChannel.jsonSent.lastWhere((m) => m.containsKey('model'))['stream_id'];
      expect(secondStream, isNot(firstStream));
      ttsChannel.serverSend({'audio': base64Encode([3, 4]), 'stream_id': secondStream});
      await pump();

      // stream-2 had partial audio when the connection was replaced -> it gets an end marker.
      expect(deltas.where((d) => d.bytes.isEmpty && d.isLastInStream && d.streamId == firstStream), hasLength(1));
      final audio = deltas.where((d) => d.bytes.isNotEmpty).toList();
      expect(audio, hasLength(2));
      expect(audio[1].sequenceNumber, greaterThan(audio[0].sequenceNumber));
      await sub.cancel();
    });

    test('non-final tokens are provisional and replaced, final tokens appended once', () async {
      await service.connect(apiKey: 'k', targetLanguage: 'ru');
      final updates = <TranscriptUpdate>[];
      final sub = service.onTranscriptUpdate.listen(updates.add);

      sttChannel.serverSend({
        'tokens': [
          {'text': 'Gu', 'translation_status': 'original', 'is_final': false},
        ],
      });
      sttChannel.serverSend({
        'tokens': [
          {'text': 'Guten', 'translation_status': 'original', 'is_final': true},
          {'text': ' Mor', 'translation_status': 'original', 'is_final': false},
        ],
      });
      await pump();

      final source = updates.where((u) => u.isSource).toList();
      expect(source[0].finalText, '');
      expect(source[0].provisionalText, 'Gu');
      expect(source[1].finalText, 'Guten');
      expect(source[1].provisionalText, ' Mor');
      await sub.cancel();
    });

    test('binary TTS frames without stream_id are dropped', () async {
      await service.connect(apiKey: 'k', targetLanguage: 'ru');
      final deltas = <AudioDelta>[];
      final sub = service.onAudioDelta.listen(deltas.add);
      ttsChannel.serverSend(Uint8List.fromList([1, 2, 3, 4]));
      await pump();
      expect(deltas, isEmpty);
      await sub.cancel();
    });

    test('STT config carries language hints and glossary context', () async {
      await service.connect(
        apiKey: 'k',
        targetLanguage: 'ru',
        sourceLanguage: 'de',
        glossary: Glossary.parse('Aaron\nAnbetung = поклонение'),
      );
      final config = sttChannel.jsonSent.first;
      expect(config['language_hints'], ['de']);
      expect(config['context']['terms'], ['Aaron', 'Anbetung']);
      expect(config['context']['translation_terms'], [
        {'source': 'Anbetung', 'target': 'поклонение'},
      ]);
    });
  });
}
