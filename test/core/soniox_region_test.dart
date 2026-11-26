import 'dart:async';
import 'dart:convert';

import 'package:auditorium/core/network/soniox_region.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Sink implements WebSocketSink {
  final sent = <dynamic>[];
  @override
  void add(dynamic data) => sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Channel answering with one fixed message (or none / an error).
class _ProbeChannel implements WebSocketChannel {
  _ProbeChannel(this._stream);
  final Stream<dynamic> _stream;
  final _sink = _Sink();
  @override
  Stream get stream => _stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _ok = {'tokens': [], 'final_audio_proc_ms': 0, 'total_audio_proc_ms': 0};
const _unauthorized = {
  'tokens': [],
  'error_code': 401,
  'error_type': 'unauthenticated',
  'error_message': 'Incorrect API key provided.',
};

/// Detector whose EU / US endpoints answer with [eu] / [us]
/// (a Map = that JSON message, null = closes without answering).
({SonioxRegionDetector detector, List<Uri> uris, List<_ProbeChannel> channels}) _setup(
    Map<String, Object>? eu, Map<String, Object>? us) {
  final uris = <Uri>[];
  final channels = <_ProbeChannel>[];
  final detector = SonioxRegionDetector(
    timeout: const Duration(milliseconds: 200),
    channelFactory: (uri, headers) {
      uris.add(uri);
      final answer = uri.host.contains('.eu.') ? eu : us;
      final channel = _ProbeChannel(answer == null ? const Stream.empty() : Stream.value(jsonEncode(answer)));
      channels.add(channel);
      return channel;
    },
  );
  return (detector: detector, uris: uris, channels: channels);
}

void main() {
  test('EU key is detected at the EU endpoint without probing the US', () async {
    final s = _setup(_ok, _ok);
    expect(await s.detector.detect('key'), SonioxKeyCheck.eu);
    expect(s.uris.map((u) => u.host), ['stt-rt.eu.soniox.com']);
  });

  test('US key: 401 at EU, accepted at US', () async {
    final s = _setup(_unauthorized, _ok);
    final check = await s.detector.detect('key');
    expect(check, SonioxKeyCheck.us);
    expect(check.region, SonioxRegion.us);
    expect(s.uris.map((u) => u.host), ['stt-rt.eu.soniox.com', 'stt-rt.soniox.com']);
  });

  test('key rejected by both regions is invalid', () async {
    final s = _setup(_unauthorized, _unauthorized);
    final check = await s.detector.detect('key');
    expect(check, SonioxKeyCheck.invalid);
    expect(check.region, isNull);
  });

  test('no answer (offline) is unknown, not invalid', () async {
    final s = _setup(null, _ok);
    expect(await s.detector.detect('key'), SonioxKeyCheck.unknown);
  });

  test('other errors still prove the region accepted the key', () async {
    final s = _setup({'error_code': 402, 'error_type': 'payment_required'}, _ok);
    expect(await s.detector.detect('key'), SonioxKeyCheck.eu);
  });

  test('probe sends a config without api_key and an immediate end of audio', () async {
    final s = _setup(_ok, _ok);
    await s.detector.detect('key');
    final sent = s.channels.single._sink.sent;
    final config = jsonDecode(sent.first as String) as Map<String, dynamic>;
    expect(config.containsKey('api_key'), isFalse);
    expect(config['model'], 'stt-rt-v6');
    expect(sent.last, '');
  });

  test('region endpoints', () {
    expect(SonioxRegion.eu.sttUrl, 'wss://stt-rt.eu.soniox.com/transcribe-websocket');
    expect(SonioxRegion.us.ttsUrl, 'wss://tts-rt.soniox.com/tts-websocket');
    expect(SonioxRegion.fromCode('us'), SonioxRegion.us);
    expect(SonioxRegion.fromCode(null), isNull);
  });
}
