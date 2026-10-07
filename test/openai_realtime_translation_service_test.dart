import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_translator/core/network/openai_realtime_translation_service.dart';
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

  void serverSend(Map<String, dynamic> event) =>
      incoming.add(jsonEncode(event));

  List<Map<String, dynamic>> get sentEvents => fakeSink.sent
      .map((e) => jsonDecode(e as String) as Map<String, dynamic>)
      .toList();

  List<Map<String, dynamic>> sentOfType(String type) =>
      sentEvents.where((e) => e['type'] == type).toList();
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('OpenAiRealtimeTranslationService basics', () {
    test('initial state is disconnected', () async {
      final service = OpenAiRealtimeTranslationService();
      expect(service.currentState, TranslationConnectionState.disconnected);
      await service.dispose();
    });

    test('dispose cleans up controllers without throwing', () async {
      final service = OpenAiRealtimeTranslationService();
      await expectLater(service.dispose(), completes);
    });
  });

  group('OpenAiRealtimeTranslationService with fake channel', () {
    late FakeWebSocketChannel channel;
    late OpenAiRealtimeTranslationService service;

    /// Connects and walks through the full handshake until the service is ready.
    Future<void> connectAndCreateSession({bool enableSourceTranscription = false}) async {
      final connected = service.connect(
        apiKey: 'sk-test',
        targetLanguage: 'ru',
        enableSourceTranscription: enableSourceTranscription,
      );
      channel.serverSend({
        'type': 'session.created',
        'session': {'id': 'sess_1'},
      });
      await pump();
      channel.serverSend({
        'type': 'session.updated',
        'session': {'audio': {}},
      });
      await connected;
    }

    setUp(() {
      channel = FakeWebSocketChannel();
      service = OpenAiRealtimeTranslationService(
        channelFactory: (uri, apiKey) => channel,
      );
    });

    tearDown(() async {
      await service.dispose();
      await channel.incoming.close();
    });

    test('session.created sends session.update with transcription null by default',
        () async {
      await connectAndCreateSession();

      expect(service.currentState, TranslationConnectionState.connected);
      expect(service.isReady, isTrue);
      final updates = channel.sentOfType('session.update');
      expect(updates, hasLength(1));
      expect(updates.first['session']['audio']['output']['language'], 'ru');
      expect(updates.first['session']['audio']['input']['transcription'], isNull);
      expect(updates.first['session']['audio']['input']['noise_reduction'],
          {'type': 'near_field'});
    });

    test('session.created sends session.update with whisper model when source transcription enabled',
        () async {
      await connectAndCreateSession(enableSourceTranscription: true);

      expect(service.currentState, TranslationConnectionState.connected);
      expect(service.isReady, isTrue);
      final updates = channel.sentOfType('session.update');
      expect(updates, hasLength(1));
      expect(updates.first['session']['audio']['output']['language'], 'ru');
      expect(updates.first['session']['audio']['input']['transcription'],
          {'model': 'gpt-realtime-whisper'});
      expect(updates.first['session']['audio']['input']['noise_reduction'],
          {'type': 'near_field'});
    });

    test('three 3200 byte chunks produce exactly one 9600 byte frame',
        () async {
      await connectAndCreateSession();

      for (var i = 0; i < 3; i++) {
        service.sendAudioChunk(Uint8List(3200)..fillRange(0, 3200, i + 1));
      }

      final appends = channel.sentOfType('session.input_audio_buffer.append');
      expect(appends, hasLength(1));
      final decoded = base64Decode(appends.first['audio'] as String);
      expect(decoded.length, 9600);
      expect(decoded[0], 1);
      expect(decoded[3200], 2);
      expect(decoded[6400], 3);
    });

    test('a 20000 byte chunk produces 2 frames and keeps the rest buffered',
        () async {
      await connectAndCreateSession();

      service.sendAudioChunk(Uint8List(20000));
      expect(
          channel.sentOfType('session.input_audio_buffer.append'), hasLength(2));

      // 800 bytes remain; 8800 more complete a third frame.
      service.sendAudioChunk(Uint8List(8800));
      expect(
          channel.sentOfType('session.input_audio_buffer.append'), hasLength(3));
    });

    test('small chunks are buffered until a full frame is available',
        () async {
      await connectAndCreateSession();

      service.sendAudioChunk(Uint8List(100));
      expect(channel.sentOfType('session.input_audio_buffer.append'), isEmpty);
    });

    test('sendAudioChunk is ignored and buffer cleared when not connected',
        () async {
      service.sendAudioChunk(Uint8List(5000));
      expect(channel.sentEvents, isEmpty);

      await connectAndCreateSession();
      // The 5000 bytes sent before connecting must have been dropped.
      service.sendAudioChunk(Uint8List(5000));
      expect(channel.sentOfType('session.input_audio_buffer.append'), isEmpty);
    });

    test('gracefulStop flushes padded rest before session.close', () async {
      await connectAndCreateSession();

      service.sendAudioChunk(Uint8List(1000)..fillRange(0, 1000, 7));
      await service.gracefulStop();

      final events = channel.sentEvents;
      final appendIndex =
          events.indexWhere((e) => e['type'] == 'session.input_audio_buffer.append');
      final closeIndex = events.indexWhere((e) => e['type'] == 'session.close');
      expect(appendIndex, isNonNegative);
      expect(closeIndex, greaterThan(appendIndex));

      final decoded = base64Decode(events[appendIndex]['audio'] as String);
      expect(decoded.length, 9600);
      expect(decoded[999], 7);
      expect(decoded[1000], 0);
      expect(service.currentState, TranslationConnectionState.closing);
    });

    test('gracefulStop without buffered audio only sends session.close',
        () async {
      await connectAndCreateSession();
      await service.gracefulStop();

      expect(channel.sentOfType('session.input_audio_buffer.append'), isEmpty);
      expect(channel.sentOfType('session.close'), hasLength(1));
    });

    test('session.input_transcript.delta is exposed as source transcript',
        () async {
      await connectAndCreateSession();

      final future = service.onSourceTranscriptDelta.first;
      channel.serverSend({
        'type': 'session.input_transcript.delta',
        'delta': 'Guten Tag',
      });
      expect(await future, 'Guten Tag');
    });

    test('session.output_transcript.delta is exposed as target transcript',
        () async {
      await connectAndCreateSession();

      final future = service.onTranscriptDelta.first;
      channel.serverSend({
        'type': 'session.output_transcript.delta',
        'delta': 'Добрый день',
      });
      expect(await future, 'Добрый день');
    });

    test('session.output_audio.delta is decoded and forwarded', () async {
      await connectAndCreateSession();

      final future = service.onAudioDelta.first;
      channel.serverSend({
        'type': 'session.output_audio.delta',
        'delta': base64Encode([1, 2, 3, 4]),
        'sample_rate': 24000,
      });
      final delta = await future;
      expect(delta.bytes, [1, 2, 3, 4]);
      expect(delta.sampleRate, 24000);
    });

    test('session.output_audio.delta honors a custom sample_rate', () async {
      await connectAndCreateSession();

      final future = service.onAudioDelta.first;
      channel.serverSend({
        'type': 'session.output_audio.delta',
        'delta': base64Encode([9, 9]),
        'sample_rate': 16000,
      });
      expect((await future).sampleRate, 16000);
    });

    test('session.output_audio.delta defaults to 24000 without sample_rate',
        () async {
      await connectAndCreateSession();

      final future = service.onAudioDelta.first;
      channel.serverSend({
        'type': 'session.output_audio.delta',
        'delta': base64Encode([9, 9]),
      });
      expect((await future).sampleRate, 24000);
    });

    test('a repeated session.updated keeps the service ready', () async {
      await connectAndCreateSession();

      channel.serverSend({
        'type': 'session.updated',
        'session': {'audio': {}},
      });
      await pump();
      expect(service.currentState, TranslationConnectionState.connected);
      expect(service.isReady, isTrue);
    });

    test('error event after ready sets the state to error and stops sending',
        () async {
      await connectAndCreateSession();

      channel.serverSend({
        'type': 'error',
        'error': {
          'type': 'invalid_request_error',
          'code': 'invalid_audio',
          'message': 'Bad audio',
        },
      });
      await pump();
      expect(service.currentState, TranslationConnectionState.error);
      expect(service.isReady, isFalse);

      service.sendAudioChunk(Uint8List(9600));
      expect(channel.sentOfType('session.input_audio_buffer.append'), isEmpty);
    });
  });

  group('OpenAiRealtimeTranslationService ready handshake', () {
    late FakeWebSocketChannel channel;
    late OpenAiRealtimeTranslationService service;

    OpenAiRealtimeTranslationService createService(
        {Duration readyTimeout = const Duration(seconds: 8)}) {
      return OpenAiRealtimeTranslationService(
        channelFactory: (uri, apiKey) => channel,
        readyTimeout: readyTimeout,
      );
    }

    setUp(() {
      channel = FakeWebSocketChannel();
      service = createService();
    });

    tearDown(() async {
      await service.dispose();
      await channel.incoming.close();
    });

    test('connect completes only after session.updated', () async {
      var completed = false;
      final connected =
          service.connect(apiKey: 'sk-test', targetLanguage: 'ru').then((_) {
        completed = true;
      });

      channel.serverSend({
        'type': 'session.created',
        'session': {'id': 'sess_1'},
      });
      await pump();
      await pump();

      expect(completed, isFalse);
      expect(service.isReady, isFalse);
      expect(service.currentState, TranslationConnectionState.connecting);
      expect(channel.sentOfType('session.update'), hasLength(1));

      channel.serverSend({'type': 'session.updated', 'session': {}});
      await connected;

      expect(completed, isTrue);
      expect(service.isReady, isTrue);
      expect(service.currentState, TranslationConnectionState.connected);
    });

    test('audio sent before ready is dropped and never sent later', () async {
      final connected =
          service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      channel.serverSend({'type': 'session.created', 'session': {}});
      await pump();

      service.sendAudioChunk(Uint8List(5000)..fillRange(0, 5000, 9));
      service.sendAudioChunk(Uint8List(20000)..fillRange(0, 20000, 9));
      expect(channel.sentOfType('session.input_audio_buffer.append'), isEmpty);

      channel.serverSend({'type': 'session.updated', 'session': {}});
      await connected;

      // Exactly one frame worth of fresh audio -> exactly one frame, without
      // any leftover from the pre-ready audio.
      service.sendAudioChunk(Uint8List(9600)..fillRange(0, 9600, 5));
      final appends = channel.sentOfType('session.input_audio_buffer.append');
      expect(appends, hasLength(1));
      final decoded = base64Decode(appends.first['audio'] as String);
      expect(decoded.length, 9600);
      expect(decoded.every((b) => b == 5), isTrue);
    });

    test('falls back to ready after timeout when only session.created arrived',
        () async {
      service = createService(readyTimeout: const Duration(milliseconds: 50));

      final connected =
          service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      channel.serverSend({'type': 'session.created', 'session': {}});

      await connected;
      expect(service.isReady, isTrue);
      expect(service.currentState, TranslationConnectionState.connected);
    });

    test('throws when nothing arrives before the timeout', () async {
      service = createService(readyTimeout: const Duration(milliseconds: 50));

      await expectLater(
        service.connect(apiKey: 'sk-test', targetLanguage: 'ru'),
        throwsA(isA<TimeoutException>()),
      );
      expect(service.isReady, isFalse);
      expect(service.currentState, TranslationConnectionState.error);
    });

    test('error event before ready makes connect throw', () async {
      final connected =
          service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      final expectation = expectLater(connected, throwsA(isA<StateError>()));

      channel.serverSend({'type': 'session.created', 'session': {}});
      await pump();
      channel.serverSend({
        'type': 'error',
        'error': {'code': 'invalid_api_key', 'message': 'Bad key'},
      });

      await expectation;
      expect(service.isReady, isFalse);
      expect(service.currentState, TranslationConnectionState.error);
    });

    test('stream error before ready makes connect throw', () async {
      final connected =
          service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      final expectation = expectLater(connected, throwsA(isA<Exception>()));

      channel.incoming.addError(Exception('socket failure'));

      await expectation;
      expect(service.isReady, isFalse);
    });

    test('stream closing before ready makes connect throw', () async {
      final connected =
          service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      final expectation = expectLater(connected, throwsA(isA<StateError>()));

      await channel.incoming.close();

      await expectation;
      expect(service.isReady, isFalse);
    });

    test('close while waiting for ready completes connect without error',
        () async {
      final connected =
          service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      await pump();

      await service.close();
      await expectLater(connected, completes);
      expect(service.isReady, isFalse);
      expect(service.currentState, TranslationConnectionState.disconnected);
    });

    test('reconnecting after close starts not ready with an empty buffer',
        () async {
      // First session: ready, then buffer some audio and close.
      var connected = service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      channel.serverSend({'type': 'session.created', 'session': {}});
      await pump();
      channel.serverSend({'type': 'session.updated', 'session': {}});
      await connected;
      service.sendAudioChunk(Uint8List(5000));
      await service.close();
      expect(service.isReady, isFalse);

      // Second session on a fresh channel.
      channel = FakeWebSocketChannel();
      connected = service.connect(apiKey: 'sk-test', targetLanguage: 'ru');
      expect(service.isReady, isFalse);
      channel.serverSend({'type': 'session.created', 'session': {}});
      await pump();
      channel.serverSend({'type': 'session.updated', 'session': {}});
      await connected;

      service.sendAudioChunk(Uint8List(5000));
      expect(channel.sentOfType('session.input_audio_buffer.append'), isEmpty);
    });
  });
}
