import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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

  void _setState(TranslationConnectionState state) {
    _currentState = state;
    _stateController.add(state);
  }

  Future<void> connect({
    required String apiKey,
    required String targetLanguage,
    required String voice,
  }) async {
    if (_currentState == TranslationConnectionState.connected ||
        _currentState == TranslationConnectionState.connecting) {
      return;
    }

    _setState(TranslationConnectionState.connecting);

    try {
      final uri = Uri.parse(_baseUrl);
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
      );

      _subscription = _channel!.stream.listen(
        (data) => _handleIncomingMessage(data, targetLanguage, voice),
        onError: (error) {
          _setState(TranslationConnectionState.error);
          close();
        },
        onDone: () {
          _setState(TranslationConnectionState.closed);
        },
      );
    } catch (e) {
      _setState(TranslationConnectionState.error);
      rethrow;
    }
  }

  void _handleIncomingMessage(
      dynamic message, String targetLanguage, String voice) {
    try {
      final Map<String, dynamic> event = jsonDecode(message as String);
      final String type = event['type'] ?? '';

      switch (type) {
        case 'session.created':
          _setState(TranslationConnectionState.connected);
          _sendSessionUpdate(targetLanguage, voice);
          break;

        case 'session.output_audio.delta':
        case 'response.audio.delta':
          final String? deltaBase64 = event['delta'] as String?;
          if (deltaBase64 != null && deltaBase64.isNotEmpty) {
            final Uint8List bytes = base64Decode(deltaBase64);
            _audioDeltaController.add(bytes);
          }
          break;

        case 'session.output_transcript.delta':
        case 'response.audio_transcript.delta':
          final String? textDelta = event['delta'] as String?;
          if (textDelta != null && textDelta.isNotEmpty) {
            _transcriptDeltaController.add(textDelta);
          }
          break;

        case 'session.closed':
          _setState(TranslationConnectionState.closed);
          close();
          break;

        case 'error':
          _setState(TranslationConnectionState.error);
          break;

        default:
          break;
      }
    } catch (e) {
      // Ignore parse errors for unhandled frame formats
    }
  }

  void _sendSessionUpdate(String targetLanguage, String voice) {
    if (_channel == null) return;

    final sessionUpdate = {
      'type': 'session.update',
      'session': {
        'model': 'gpt-realtime-translate',
        'audio': {
          'output': {
            'language': targetLanguage,
            'voice': voice,
          }
        }
      }
    };

    _channel!.sink.add(jsonEncode(sessionUpdate));
  }

  void sendAudioChunk(Uint8List pcm16Chunk) {
    if (_currentState != TranslationConnectionState.connected ||
        _channel == null) {
      return;
    }

    final String base64Audio = base64Encode(pcm16Chunk);
    final appendEvent = {
      'type': 'input_audio_buffer.append',
      'audio': base64Audio,
    };

    _channel!.sink.add(jsonEncode(appendEvent));
  }

  Future<void> gracefulStop() async {
    if (_currentState != TranslationConnectionState.connected ||
        _channel == null) {
      await close();
      return;
    }

    _setState(TranslationConnectionState.closing);

    // Send session.close to allow server to flush pending translated audio
    final closeEvent = {'type': 'session.close'};
    _channel!.sink.add(jsonEncode(closeEvent));

    // Fallback timer to force-close if server does not reply with session.closed in 5s
    Timer(const Duration(seconds: 5), () {
      if (_currentState == TranslationConnectionState.closing) {
        close();
      }
    });
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setState(TranslationConnectionState.disconnected);
  }

  void dispose() {
    close();
    _audioDeltaController.close();
    _transcriptDeltaController.close();
    _stateController.close();
  }
}
