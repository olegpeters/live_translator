import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum TranslationConnectionState {
  disconnected,
  connecting,
  connected,
  closing,
  closed,
  error,
}

class OpenAiRealtimeTranslationService {
  static const String _baseUrl =
      'wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final _audioDeltaController = StreamController<Uint8List>.broadcast();
  final _transcriptDeltaController = StreamController<String>.broadcast();
  final _stateController =
      StreamController<TranslationConnectionState>.broadcast();

  TranslationConnectionState _currentState =
      TranslationConnectionState.disconnected;

  Stream<Uint8List> get onAudioDelta => _audioDeltaController.stream;
  Stream<String> get onTranscriptDelta => _transcriptDeltaController.stream;
  Stream<TranslationConnectionState> get onStateChanged =>
      _stateController.stream;

  TranslationConnectionState get currentState => _currentState;

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'OpenAiRealtimeTranslationService',
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode) {
      if (error != null) {
        debugPrint('[OpenAiRealtimeTranslationService] $message: $error');
        if (stackTrace != null) {
          debugPrint(stackTrace.toString());
        }
      } else {
        debugPrint('[OpenAiRealtimeTranslationService] $message');
      }
    }
  }

  void _setState(TranslationConnectionState state) {
    _log('State changed: $_currentState -> $state');
    _currentState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  Future<void> connect({
    required String apiKey,
    required String targetLanguage,
    String? voice,
  }) async {
    if (_currentState == TranslationConnectionState.connected ||
        _currentState == TranslationConnectionState.connecting) {
      _log('Connect skipped: already in state $_currentState');
      return;
    }

    _setState(TranslationConnectionState.connecting);
    _log('Connecting to WebSocket at $_baseUrl...');

    try {
      final uri = Uri.parse(_baseUrl);
      if (kIsWeb) {
        _channel = WebSocketChannel.connect(
          uri,
          protocols: [
            'realtime',
            'openai-insecure-api-key.$apiKey',
          ],
        );
      } else {
        _channel = IOWebSocketChannel.connect(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
        );
      }

      _subscription = _channel!.stream.listen(
        (data) => _handleIncomingMessage(data, targetLanguage),
        onError: (error, stackTrace) {
          _log('WebSocket stream error occurred: $error',
              error: error, stackTrace: stackTrace);
          _setState(TranslationConnectionState.error);
          close();
        },
        onDone: () {
          _log(
            'WebSocket stream closed. Close code: ${_channel?.closeCode}, reason: ${_channel?.closeReason}',
          );
          _setState(TranslationConnectionState.closed);
        },
      );
    } catch (e, stackTrace) {
      _log('Failed to initiate WebSocket connection: $e',
          error: e, stackTrace: stackTrace);
      _setState(TranslationConnectionState.error);
      rethrow;
    }
  }

  void _handleIncomingMessage(dynamic message, String targetLanguage) {
    try {
      final Map<String, dynamic> event = jsonDecode(message as String);
      final String type = event['type'] ?? '';

      switch (type) {
        case 'session.created':
          _log('Session created event received: ${event['session']?['id'] ?? ''}');
          _setState(TranslationConnectionState.connected);
          _sendSessionUpdate(targetLanguage);
          break;

        case 'session.output_audio.delta':
        case 'response.output_audio.delta':
        case 'response.audio.delta':
          final String? deltaBase64 = event['delta'] as String?;
          if (deltaBase64 != null && deltaBase64.isNotEmpty) {
            final Uint8List bytes = base64Decode(deltaBase64);
            if (!_audioDeltaController.isClosed) {
              _audioDeltaController.add(bytes);
            }
          }
          break;

        case 'session.output_transcript.delta':
        case 'response.output_audio_transcript.delta':
        case 'response.audio_transcript.delta':
          final String? textDelta = event['delta'] as String?;
          if (textDelta != null && textDelta.isNotEmpty) {
            if (!_transcriptDeltaController.isClosed) {
              _transcriptDeltaController.add(textDelta);
            }
          }
          break;

        case 'session.closed':
          _log('Session closed event received from server');
          _setState(TranslationConnectionState.closed);
          close();
          break;

        case 'error':
          final errorData = event['error'];
          _log('Error event received from OpenAI: $errorData');
          _setState(TranslationConnectionState.error);
          break;

        default:
          break;
      }
    } catch (e, stackTrace) {
      _log('Error parsing incoming WebSocket message: $e (raw: $message)',
          error: e, stackTrace: stackTrace);
    }
  }

  void _sendSessionUpdate(String targetLanguage) {
    if (_channel == null) {
      _log('Cannot send session update: WebSocket channel is null');
      return;
    }

    final sessionUpdate = {
      'type': 'session.update',
      'session': {
        'audio': {
          'output': {
            'language': targetLanguage,
          }
        }
      }
    };

    _log('Sending session.update for language: $targetLanguage');
    _channel!.sink.add(jsonEncode(sessionUpdate));
  }

  void sendAudioChunk(Uint8List pcm16Chunk) {
    if (_currentState != TranslationConnectionState.connected ||
        _channel == null) {
      return;
    }

    final String base64Audio = base64Encode(pcm16Chunk);
    final appendEvent = {
      'type': 'session.input_audio_buffer.append',
      'audio': base64Audio,
    };

    _channel!.sink.add(jsonEncode(appendEvent));
  }

  Future<void> gracefulStop() async {
    if (_currentState != TranslationConnectionState.connected ||
        _channel == null) {
      _log('Graceful stop invoked while not connected (state: $_currentState)');
      await close();
      return;
    }

    _log('Initiating graceful stop...');
    _setState(TranslationConnectionState.closing);

    // Send session.close to allow server to flush pending translated audio
    final closeEvent = {'type': 'session.close'};
    _channel!.sink.add(jsonEncode(closeEvent));

    // Fallback timer to force-close if server does not reply with session.closed in 5s
    Timer(const Duration(seconds: 5), () {
      if (_currentState == TranslationConnectionState.closing) {
        _log('Graceful stop timed out after 5s; forcing close');
        close();
      }
    });
  }

  Future<void> close() async {
    _log('Closing WebSocket connection (current state: $_currentState)');
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setState(TranslationConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await close();
    await _audioDeltaController.close();
    await _transcriptDeltaController.close();
    await _stateController.close();
  }
}
