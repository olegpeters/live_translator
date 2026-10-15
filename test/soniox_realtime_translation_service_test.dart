import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/network/soniox_realtime_translation_service.dart';
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
  final StreamController<dynamic> incoming = StreamController<dynamic>();
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
      expect(sttConfigs.first['api_key'], 'soniox-test-key');
      expect(sttConfigs.first['model'], 'stt-rt-v5');
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
      expect(binaryFrames, hasLength(1));
      expect(binaryFrames.first.length, 9600);
      expect(binaryFrames.first[0], 1);
      expect(binaryFrames.first[3200], 2);
      expect(binaryFrames.first[6400], 3);
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
            'text': 'Доброе утро',
            'translation_status': 'translation',
          }
        ],
      });

      expect(await future, 'Доброе утро');

      final ttsSent = ttsChannel.jsonSent;
      // Index 0 is the initial config; subsequent entries are the forwarded text tokens
      expect(ttsSent.length, greaterThanOrEqualTo(2));
      final combinedTtsText = ttsSent
          .skip(1)
          .map((m) => m['text'] as String? ?? '')
          .join();
      expect(combinedTtsText, 'Доброе утро');
      expect(ttsSent.last['text_end'], isFalse);
    });

    test('TTS incoming audio is base64 decoded and emitted on onAudioDelta', () async {
      await service.connect(
        apiKey: 'soniox-test-key',
        targetLanguage: 'ru',
      );

      final future = service.onAudioDelta.first;
      final payload = base64Encode([10, 20, 30, 40]);
      ttsChannel.serverSend({
        'audio': payload,
        'audio_end': false,
      });

      final delta = await future;
      expect(delta.bytes, [10, 20, 30, 40]);
      expect(delta.sampleRate, 24000);
    });

    test('text with punctuation sends text_end false and maintains active stream', () async {
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

      sttChannel.serverSend({
        'tokens': [
          {
            'text': ' Эм,',
            'translation_status': 'translation',
          }
        ],
      });
      await pump();

      final ttsSent = ttsChannel.jsonSent;
      // Index 0: config for stream-2
      // Index 1: "Здравствуйте." (text_end: false)
      // Index 2: " Эм," (text_end: false)
      final textMessages = ttsSent.where((msg) => msg.containsKey('text')).toList();
      expect(textMessages.length, equals(2));
      expect(textMessages[0]['text'], equals('Здравствуйте.'));
      expect(textMessages[0]['text_end'], isFalse);
      expect(textMessages[0]['stream_id'], equals('stream-2'));
      expect(textMessages[1]['text'], equals(' Эм,'));
      expect(textMessages[1]['text_end'], isFalse);
      expect(textMessages[1]['stream_id'], equals('stream-2'));
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

      // New utterance token should start stream-3
      sttChannel.serverSend({
        'tokens': [
          {
            'text': ' Понятно.',
            'translation_status': 'translation',
          }
        ],
      });
      await pump();

      final ttsSent2 = ttsChannel.jsonSent;
      final lastTextMsg = ttsSent2.last;
      expect(lastTextMsg['stream_id'], equals('stream-3'));
      expect(lastTextMsg['text'], equals(' Понятно.'));
      expect(lastTextMsg['text_end'], isFalse);
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

      // Verify emitted sequence is [1,1,1] -> [1,1,2] -> [2,2,2] -> [2,2,3]
      expect(receivedAudio, hasLength(4));
      expect(receivedAudio[0], equals([1, 1, 1]));
      expect(receivedAudio[1], equals([1, 1, 2]));
      expect(receivedAudio[2], equals([2, 2, 2]));
      expect(receivedAudio[3], equals([2, 2, 3]));

      await sub.cancel();
    });

    test('late audio arriving for an already completed stream is discarded', () async {
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

      // Complete stream-2
      ttsChannel.serverSend({
        'stream_id': 'stream-2',
        'audio': base64Encode([10, 10]),
        'audio_end': true,
      });
      await pump();

      expect(receivedAudio, hasLength(1));

      // Start stream-3
      sttChannel.serverSend({
        'tokens': [
          {'text': '<end>'}
        ],
      });
      sttChannel.serverSend({
        'tokens': [
          {'text': 'Sentence two.', 'translation_status': 'translation'}
        ],
      });
      await pump();

      // Send late audio for completed stream-2
      ttsChannel.serverSend({
        'stream_id': 'stream-2',
        'audio': base64Encode([99, 99]),
      });
      await pump();

      // Send valid audio for stream-3
      ttsChannel.serverSend({
        'stream_id': 'stream-3',
        'audio': base64Encode([20, 20]),
        'audio_end': true,
      });
      await pump();

      // Verify late chunk [99, 99] was discarded!
      expect(receivedAudio, hasLength(2));
      expect(receivedAudio[0], equals([10, 10]));
      expect(receivedAudio[1], equals([20, 20]));

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

      expect(sttChannel.rawSent.contains(''), isTrue);

      final ttsSent = ttsChannel.jsonSent;
      expect(ttsSent.any((msg) => msg['text'] == '' && msg['text_end'] == true), isTrue);
      expect(service.currentState, TranslationConnectionState.closing);
    });
  });
}
