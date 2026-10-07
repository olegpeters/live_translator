import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
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

typedef WebSocketChannelFactory = WebSocketChannel Function(
    Uri uri, String apiKey);

/// A chunk of translated PCM16 mono audio together with its sample rate.
class AudioDelta {
  static const int defaultSampleRate = 24000;

  final Uint8List bytes;
  final int sampleRate;

  const AudioDelta(this.bytes, {this.sampleRate = defaultSampleRate});
}

class OpenAiRealtimeTranslationService {
  static const String _baseUrl =
      'wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate';

  /// 200 ms of 24 kHz PCM16 mono audio (24000 * 0.2 * 2 bytes).
  static const int frameBytes = 9600;
  static const Duration _statsLogInterval = Duration(seconds: 5);
  static const int _levelLoggedFramesLimit = 5;

  /// Maximum time to wait for the server to confirm the session configuration.
  final Duration readyTimeout;

  final WebSocketChannelFactory? channelFactory;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _stopTimer;

  final BytesBuilder _pending = BytesBuilder();
  int _sentFrames = 0;
  int _sentBytes = 0;
  DateTime? _lastStatsLog;
  int _levelLoggedFrames = 0;

  Completer<void>? _readyCompleter;
  bool _isReady = false;
  bool _sessionCreated = false;
  Stopwatch? _connectWatch;

  final _audioDeltaController = StreamController<AudioDelta>.broadcast();
  final _transcriptDeltaController = StreamController<String>.broadcast();
  final _sourceTranscriptController = StreamController<String>.broadcast();
  final _stateController =
      StreamController<TranslationConnectionState>.broadcast();

  TranslationConnectionState _currentState =
      TranslationConnectionState.disconnected;

  Stream<AudioDelta> get onAudioDelta => _audioDeltaController.stream;
  Stream<String> get onTranscriptDelta => _transcriptDeltaController.stream;
  Stream<String> get onSourceTranscriptDelta =>
      _sourceTranscriptController.stream;
  Stream<TranslationConnectionState> get onStateChanged =>
      _stateController.stream;

  TranslationConnectionState get currentState => _currentState;

  /// True once the server confirmed the session configuration
  /// (`session.updated`). Audio is only sent while ready.
  bool get isReady => _isReady;

  OpenAiRealtimeTranslationService({
    this.channelFactory,
    this.readyTimeout = const Duration(seconds: 8),
  });

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

  /// Opens the WebSocket and completes once the session is fully configured
  /// (`session.updated` received). If the server does not confirm within
  /// [readyTimeout] but `session.created` was received, a warning is logged
  /// and the service continues as ready. Errors before ready are thrown.
  Future<void> connect({
    required String apiKey,
    required String targetLanguage,
  }) async {
    if (_currentState == TranslationConnectionState.connecting) {
      _log('Connect already in progress; waiting for ready');
      await _readyCompleter?.future;
      return;
    }
    if (_currentState == TranslationConnectionState.connected) {
      _log('Connect skipped: already in state $_currentState');
      return;
    }

    _pending.clear();
    _isReady = false;
    _sessionCreated = false;
    _levelLoggedFrames = 0;
    _connectWatch = Stopwatch()..start();
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;

    _setState(TranslationConnectionState.connecting);
    _log('Connecting to WebSocket at $_baseUrl...');

    try {
      final uri = Uri.parse(_baseUrl);
      final factory = channelFactory;
      if (factory != null) {
        _channel = factory(uri, apiKey);
      } else if (kIsWeb) {
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
          _failReady(error, stackTrace);
          _isReady = false;
          _setState(TranslationConnectionState.error);
          close();
        },
        onDone: () {
          _log(
            'WebSocket stream closed. Close code: ${_channel?.closeCode}, reason: ${_channel?.closeReason}',
          );
          _failReady(StateError(
              'WebSocket closed before the session was ready '
              '(code: ${_channel?.closeCode}, reason: ${_channel?.closeReason})'));
          _isReady = false;
          _setState(TranslationConnectionState.closed);
        },
      );

      await readyCompleter.future.timeout(readyTimeout, onTimeout: () {
        if (_sessionCreated && !_isReady) {
          _log('WARNING: session.updated not received within '
              '${readyTimeout.inSeconds} s; continuing with session.created only');
          _markReady();
          return;
        }
        throw TimeoutException(
            'Session was not created within ${readyTimeout.inSeconds} s',
            readyTimeout);
      });
    } catch (e, stackTrace) {
      _log('Failed to establish translation session: $e',
          error: e, stackTrace: stackTrace);
      await close();
      _setState(TranslationConnectionState.error);
      rethrow;
    }
  }

  void _markReady() {
    if (_isReady) return;
    // Audio recorded before the session was configured must never be sent.
    _pending.clear();
    _isReady = true;
    _log('Session ready after ${_connectWatch?.elapsedMilliseconds} ms');
    _setState(TranslationConnectionState.connected);
    final completer = _readyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _failReady(Object error, [StackTrace? stackTrace]) {
    final completer = _readyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  void _handleIncomingMessage(dynamic message, String targetLanguage) {
    try {
      final Map<String, dynamic> event = jsonDecode(message as String);
      final String type = event['type'] ?? '';

      switch (type) {
        case 'session.created':
          _log('Session created event received: ${event['session']?['id'] ?? ''} '
              'after ${_connectWatch?.elapsedMilliseconds} ms');
          _sessionCreated = true;
          _sendSessionUpdate(targetLanguage);
          break;

        case 'session.updated':
          _log('Session updated after ${_connectWatch?.elapsedMilliseconds} ms, '
              'effective config: ${jsonEncode(event['session'])}');
          if (_currentState == TranslationConnectionState.connecting) {
            _markReady();
          }
          break;

        case 'session.input_transcript.delta':
          final String? sourceDelta = event['delta'] as String?;
          if (sourceDelta != null && sourceDelta.isNotEmpty) {
            _log('Source transcript delta: $sourceDelta');
            if (!_sourceTranscriptController.isClosed) {
              _sourceTranscriptController.add(sourceDelta);
            }
          }
          break;

        case 'session.output_audio.delta':
        case 'response.output_audio.delta':
        case 'response.audio.delta':
          final String? deltaBase64 = event['delta'] as String?;
          if (deltaBase64 != null && deltaBase64.isNotEmpty) {
            final Uint8List bytes = base64Decode(deltaBase64);
            final rate = event['sample_rate'];
            final int sampleRate =
                rate is int && rate > 0 ? rate : AudioDelta.defaultSampleRate;
            if (!_audioDeltaController.isClosed) {
              _audioDeltaController.add(AudioDelta(bytes, sampleRate: sampleRate));
            }
          }
          break;

        case 'response.audio.done':
        case 'response.output_audio.done':
        case 'response.done':
        case 'session.output_audio.done':
          if (!_audioDeltaController.isClosed) {
            _audioDeltaController.add(
                AudioDelta(Uint8List(0), sampleRate: AudioDelta.defaultSampleRate));
          }
          break;

        case 'response.created':
          _log('Response created by server');
          break;

        case 'response.cancelled':
          _log('WARNING: Response was cancelled by server VAD interruption!');
          break;

        case 'input_audio_buffer.speech_started':
          _log('Server VAD: speech_started in input audio');
          break;

        case 'input_audio_buffer.speech_stopped':
          _log('Server VAD: speech_stopped in input audio');
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
          _failReady(StateError('Session closed before it was ready'));
          _setState(TranslationConnectionState.closed);
          close();
          break;

        case 'error':
          final errorData = event['error'];
          final errorMap = errorData is Map ? errorData : const {};
          _log('Error event received from OpenAI: '
              'code=${errorMap['code']}, type=${errorMap['type']}, '
              'message=${errorMap['message'] ?? errorData}');
          _failReady(StateError(
              'OpenAI error: ${errorMap['message'] ?? errorData}'));
          _isReady = false;
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
          'input': {
            // Enables session.input_transcript.delta so the recognized source
            // text can be used to verify what the model actually hears.
            'transcription': {'model': 'gpt-realtime-whisper'},
            'noise_reduction': {'type': 'near_field'},
          },
          'output': {
            'language': targetLanguage,
          }
        }
      }
    };

    _log('Sending session.update for language: $targetLanguage');
    _channel!.sink.add(jsonEncode(sessionUpdate));
  }

  /// Buffers PCM16 (24 kHz, mono) audio and sends it to the API in 200 ms
  /// frames of [frameBytes] bytes each.
  void sendAudioChunk(Uint8List pcm16Chunk) {
    if (!_isReady ||
        _currentState != TranslationConnectionState.connected ||
        _channel == null) {
      _pending.clear();
      return;
    }

    _pending.add(pcm16Chunk);
    if (_pending.length < frameBytes) return;

    final Uint8List all = _pending.takeBytes();
    int offset = 0;
    while (all.length - offset >= frameBytes) {
      _sendFrame(Uint8List.sublistView(all, offset, offset + frameBytes));
      offset += frameBytes;
    }
    if (offset < all.length) {
      _pending.add(Uint8List.fromList(all.sublist(offset)));
    }
    _logStatsIfDue();
  }

  void _sendFrame(Uint8List frame) {
    final appendEvent = {
      'type': 'session.input_audio_buffer.append',
      'audio': base64Encode(frame),
    };
    _channel!.sink.add(jsonEncode(appendEvent));
    _sentFrames++;
    _sentBytes += frame.length;
    _logFirstFrameLevel(frame);
  }

  /// Logs the RMS level (0..1) of the first few frames to help diagnose
  /// noisy or silent microphone start-up.
  void _logFirstFrameLevel(Uint8List frame) {
    if (_levelLoggedFrames >= _levelLoggedFramesLimit) return;
    _levelLoggedFrames++;
    final data = ByteData.sublistView(frame);
    final sampleCount = frame.length ~/ 2;
    if (sampleCount == 0) return;
    double sumSquares = 0;
    for (int i = 0; i < sampleCount; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += s * s;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    _log('Frame #$_levelLoggedFrames sent, RMS level: '
        '${rms.toStringAsFixed(4)} '
        '(${_connectWatch?.elapsedMilliseconds} ms since connect)');
  }

  void _logStatsIfDue() {
    final now = DateTime.now();
    final last = _lastStatsLog;
    if (last == null) {
      _lastStatsLog = now;
      return;
    }
    if (now.difference(last) >= _statsLogInterval) {
      _lastStatsLog = now;
      _log('Audio sent so far: $_sentFrames frames, $_sentBytes bytes '
          '(${(_sentBytes / 48000).toStringAsFixed(1)} s @ 24 kHz PCM16), '
          'buffered: ${_pending.length} bytes');
    }
  }

  /// Sends the remaining buffered audio, padded with silence to a full frame.
  void _flushPending() {
    if (_pending.isEmpty || _channel == null) {
      _pending.clear();
      return;
    }
    final Uint8List rest = _pending.takeBytes();
    final Uint8List frame = Uint8List(frameBytes);
    frame.setRange(0, rest.length, rest);
    _sendFrame(frame);
  }

  Future<void> gracefulStop() async {
    if (_currentState != TranslationConnectionState.connected ||
        _channel == null) {
      _log('Graceful stop invoked while not connected (state: $_currentState)');
      await close();
      return;
    }

    _log('Initiating graceful stop...');
    _flushPending();
    _isReady = false;
    _setState(TranslationConnectionState.closing);

    // Send session.close to allow server to flush pending translated audio
    final closeEvent = {'type': 'session.close'};
    _channel!.sink.add(jsonEncode(closeEvent));

    // Fallback timer to force-close if server does not reply with session.closed in 5s
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(seconds: 5), () {
      if (_currentState == TranslationConnectionState.closing) {
        _log('Graceful stop timed out after 5s; forcing close');
        close();
      }
    });
  }

  Future<void> close() async {
    _log('Closing WebSocket connection (current state: $_currentState, '
        'sent $_sentFrames frames / $_sentBytes bytes)');
    _stopTimer?.cancel();
    _stopTimer = null;
    _pending.clear();
    _isReady = false;
    _sessionCreated = false;
    _levelLoggedFrames = 0;
    final readyCompleter = _readyCompleter;
    _readyCompleter = null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete();
    }
    _sentFrames = 0;
    _sentBytes = 0;
    _lastStatsLog = null;
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
    await _sourceTranscriptController.close();
    await _stateController.close();
  }
}
