import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../logging/app_logger.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(
    Uri uri, Map<String, String>? headers);

/// Soniox data residency region. A project's region is fixed at creation (default: US;
/// EU on request) and its API keys only authenticate at that region's endpoints:
/// a US key at the EU endpoints gets `401 unauthenticated` ("Incorrect API key").
enum SonioxRegion {
  eu('eu', 'wss://stt-rt.eu.soniox.com/transcribe-websocket', 'wss://tts-rt.eu.soniox.com/tts-websocket'),
  us('us', 'wss://stt-rt.soniox.com/transcribe-websocket', 'wss://tts-rt.soniox.com/tts-websocket');

  const SonioxRegion(this.code, this.sttUrl, this.ttsUrl);

  final String code;
  final String sttUrl;
  final String ttsUrl;

  static SonioxRegion? fromCode(String? code) {
    for (final r in values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

/// Opens a Soniox WebSocket. Native: `Authorization: Bearer` header; web: subprotocols
/// (browsers cannot set headers). The key is never sent in a config payload.
WebSocketChannel openSonioxChannel(Uri uri, String apiKey, {WebSocketChannelFactory? factory}) {
  final headers = {'Authorization': 'Bearer $apiKey'};
  if (factory != null) return factory(uri, headers);
  if (kIsWeb) return WebSocketChannel.connect(uri, protocols: ['soniox-api-key', apiKey]);
  return IOWebSocketChannel.connect(uri, headers: headers);
}

/// Result of checking an API key against the Soniox regions.
enum SonioxKeyCheck {
  /// Key belongs to an EU-region project.
  eu,

  /// Key belongs to a US-region project (rejected at the EU endpoints).
  us,

  /// Rejected by both regions.
  invalid,

  /// Could not be determined (offline, timeout, unexpected response).
  unknown;

  SonioxRegion? get region => switch (this) {
        SonioxKeyCheck.eu => SonioxRegion.eu,
        SonioxKeyCheck.us => SonioxRegion.us,
        _ => null,
      };
}

enum _Probe { accepted, unauthorized, failed }

/// Finds the region of an API key: EU first (preferred), then US.
/// Each probe opens an STT connection, sends a config and an immediate end of audio
/// (no audio is transcribed) and reads the first response.
class SonioxRegionDetector {
  SonioxRegionDetector({this.channelFactory, this.timeout = const Duration(seconds: 8)});

  final WebSocketChannelFactory? channelFactory;
  final Duration timeout;

  Future<SonioxKeyCheck> detect(String apiKey) async {
    final eu = await _probe(SonioxRegion.eu, apiKey);
    if (eu == _Probe.accepted) return _done(SonioxKeyCheck.eu);
    if (eu == _Probe.failed) return _done(SonioxKeyCheck.unknown);
    final us = await _probe(SonioxRegion.us, apiKey);
    return _done(switch (us) {
      _Probe.accepted => SonioxKeyCheck.us,
      _Probe.unauthorized => SonioxKeyCheck.invalid,
      _Probe.failed => SonioxKeyCheck.unknown,
    });
  }

  SonioxKeyCheck _done(SonioxKeyCheck result) {
    AppLogger.info('API key region check: ${result.name}', tag: 'SonioxRegion');
    return result;
  }

  Future<_Probe> _probe(SonioxRegion region, String apiKey) async {
    WebSocketChannel? channel;
    try {
      channel = openSonioxChannel(Uri.parse(region.sttUrl), apiKey, factory: channelFactory);
      channel.sink.add(jsonEncode({
        'model': 'stt-rt-v5',
        'audio_format': 'pcm_s16le',
        'sample_rate': 16000,
        'num_channels': 1,
      }));
      channel.sink.add(''); // end of audio: nothing to transcribe
      final first = await channel.stream.first.timeout(timeout);
      if (first is! String) return _Probe.failed;
      final response = jsonDecode(first) as Map<String, dynamic>;
      final code = response['error_code'];
      if (code == null) return _Probe.accepted;
      if (code == 401) return _Probe.unauthorized;
      // Any other error (e.g. billing, rate limit) means the region accepted the key.
      AppLogger.warning('Region probe ${region.code}: error $code ${response['error_type']}', tag: 'SonioxRegion');
      return _Probe.accepted;
    } catch (e) {
      AppLogger.warning('Region probe ${region.code} failed: $e', tag: 'SonioxRegion');
      return _Probe.failed;
    } finally {
      unawaited(channel?.sink.close().catchError((_) {}));
    }
  }
}
