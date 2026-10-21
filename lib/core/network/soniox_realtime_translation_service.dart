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
    Uri uri, Map<String, String>? headers);

/// A chunk of translated PCM16 mono audio together with its sample rate and sequence tracking.
class AudioDelta {
  static const int defaultSampleRate = 24000;

  final Uint8List bytes;
  final int sampleRate;
  final int sequenceNumber;
  final String streamId;

  const AudioDelta(
    this.bytes, {
    this.sampleRate = defaultSampleRate,
    this.sequenceNumber = 0,
    this.streamId = '',
  });
}

class SonioxRealtimeTranslationService {
  static const String _sttBaseUrl =
      'wss://stt-rt.soniox.com/transcribe-websocket';
  static const String _ttsBaseUrl =
      'wss://tts-rt.soniox.com/tts-websocket';

  /// 200 ms of 24 kHz PCM16 mono audio (24000 * 0.2 * 2 bytes).
  static const int frameBytes = 9600;
  static const Duration _statsLogInterval = Duration(seconds: 5);
  static const int _levelLoggedFramesLimit = 5;

  final Duration readyTimeout;
  final WebSocketChannelFactory? channelFactory;

  WebSocketChannel? _sttChannel;
  WebSocketChannel? _ttsChannel;
  StreamSubscription? _sttSubscription;
  StreamSubscription? _ttsSubscription;
  Timer? _stopTimer;

  final BytesBuilder _pending = BytesBuilder();
  int _sentFrames = 0;
  int _sentBytes = 0;
  DateTime? _lastStatsLog;
  int _levelLoggedFrames = 0;

  Completer<void>? _readyCompleter;
  bool _isReady = false;

  Stopwatch? _connectWatch;
  String _apiKey = '';
  String _targetLanguage = 'ru';
  String _voice = 'Daniel';
  bool _enableSourceTranscription = false;
  int _ttsStreamIndex = 1;
  String _currentTtsStreamId = 'stream-1';
  bool _currentTtsStreamActive = false;
  Timer? _ttsInactivityTimer;
  Timer? _keepAliveTimer;

  final List<String> _streamOrder = [];
  final Map<String, List<Uint8List>> _streamAudioBuffers = {};
  final Set<String> _completedStreams = {};

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
  bool get isReady => _isReady;
  bool get enableSourceTranscription => _enableSourceTranscription;

  SonioxRealtimeTranslationService({
    this.channelFactory,
    this.readyTimeout = const Duration(seconds: 8),
  });

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'SonioxRealtimeTranslationService',
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode) {
      if (error != null) {
        debugPrint('[SonioxRealtimeTranslationService] $message: $error');
        if (stackTrace != null) {
          debugPrint(stackTrace.toString());
        }
      } else {
        debugPrint('[SonioxRealtimeTranslationService] $message');
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
    String voice = 'Daniel',
    bool enableSourceTranscription = false,
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

    _apiKey = apiKey;
    _targetLanguage = targetLanguage;
    _voice = voice;
    _enableSourceTranscription = enableSourceTranscription;
    _ttsStreamIndex = 1;
    _currentTtsStreamId = 'stream-1';
    _currentTtsStreamActive = false;
    _streamChunkCounters.clear();
    _streamOrder.clear();
    _streamAudioBuffers.clear();
    _completedStreams.clear();
    _pending.clear();
    _isReady = false;
    _levelLoggedFrames = 0;
    _connectWatch = Stopwatch()..start();
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;

    _setState(TranslationConnectionState.connecting);
    _log('Connecting to Soniox STT & TTS WebSockets...');

    try {
      final headers = {'Authorization': 'Bearer $apiKey'};
      final protocols = ['soniox-api-key', apiKey];

      // 1. Establish STT + Translation WebSocket connection
      final sttUri = Uri.parse(_sttBaseUrl);
      final factory = channelFactory;
      if (factory != null) {
        _sttChannel = factory(sttUri, headers);
      } else if (kIsWeb) {
        _sttChannel = WebSocketChannel.connect(
          sttUri,
          protocols: protocols,
        );
      } else {
        _sttChannel = IOWebSocketChannel.connect(sttUri, headers: headers);
      }

      // 2. Establish TTS WebSocket connection
      final ttsUri = Uri.parse(_ttsBaseUrl);
      if (factory != null) {
        _ttsChannel = factory(ttsUri, headers);
      } else if (kIsWeb) {
        _ttsChannel = WebSocketChannel.connect(
          ttsUri,
          protocols: protocols,
        );
      } else {
        _ttsChannel = IOWebSocketChannel.connect(ttsUri, headers: headers);
      }

      // Listen to STT stream
      _sttSubscription = _sttChannel!.stream.listen(
        (data) => _handleSttMessage(data),
        onError: (error, stackTrace) {
          _log('STT WebSocket error: $error', error: error, stackTrace: stackTrace);
          _failReady(error, stackTrace);
          _setState(TranslationConnectionState.error);
          close();
        },
        onDone: () {
          _log('STT WebSocket closed (code: ${_sttChannel?.closeCode})');
          if (!_isReady) {
            _failReady(StateError('STT WebSocket closed before session was ready'));
          }
          _setState(TranslationConnectionState.closed);
        },
      );

      // Listen to TTS stream
      _ttsSubscription = _ttsChannel!.stream.listen(
        (data) => _handleTtsMessage(data),
        onError: (error, stackTrace) {
          _log('TTS WebSocket error: $error', error: error, stackTrace: stackTrace);
          _reconnectTtsChannel();
        },
        onDone: () {
          _log('TTS WebSocket closed (code: ${_ttsChannel?.closeCode})');
          _reconnectTtsChannel();
        },
      );

      // Send initial STT configuration
      _sendSttConfig();

      _markReady();

      await readyCompleter.future.timeout(readyTimeout, onTimeout: () {
        throw TimeoutException('Soniox session failed to connect within ${readyTimeout.inSeconds} s', readyTimeout);
      });
    } catch (e, stackTrace) {
      _log('Failed to establish Soniox translation session: $e',
          error: e, stackTrace: stackTrace);
      await close();
      _setState(TranslationConnectionState.error);
      rethrow;
    }
  }

  void _sendSttConfig() {
    final config = {
      'api_key': _apiKey,
      'model': 'stt-rt-v5',
      'audio_format': 'pcm_s16le',
      'sample_rate': 24000,
      'num_channels': 1,
      'enable_endpoint_detection': true,
      'translation': {
        'type': 'one_way',
        'target_language': _targetLanguage,
      },
    };
    _log('Sending STT config for targetLanguage: $_targetLanguage');
    _sttChannel?.sink.add(jsonEncode(config));
  }

  void _sendTtsConfig([String? streamId]) {
    final id = streamId ?? _currentTtsStreamId;
    final config = {
      'stream_id': id,
      'model': 'tts-rt-v2',
      'language': _targetLanguage,
      'voice': _voice,
      'audio_format': 'pcm_s16le',
      'sample_rate': 24000,
    };
    _log('Sending TTS config: stream_id=$id, model=tts-rt-v2, language=$_targetLanguage, voice=$_voice');
    _ttsChannel?.sink.add(jsonEncode(config));
  }

  void _registerStream(String streamId) {
    if (_completedStreams.contains(streamId)) return;
    if (!_streamOrder.contains(streamId)) {
      _streamOrder.add(streamId);
      _streamAudioBuffers[streamId] = [];
    }
  }

  void _startNewTtsStream() {
    _ttsStreamIndex++;
    _currentTtsStreamId = 'stream-$_ttsStreamIndex';
    _currentTtsStreamActive = true;
    _registerStream(_currentTtsStreamId);
    _sendTtsConfig(_currentTtsStreamId);
  }

  final StringBuffer _ttsTextBuffer = StringBuffer();
  int _ttsBufferWordCount = 0;

  void _restartTtsInactivityTimer() {
    _ttsInactivityTimer?.cancel();
    _ttsInactivityTimer = Timer(const Duration(milliseconds: 2700), () {
      if (_currentTtsStreamActive) {
        _log('TTS stream inactivity timeout; closing stream $_currentTtsStreamId');
        _flushTtsBuffer(force: true, isEnd: true);
      }
    });
  }

  void _bufferAndSendTtsText(String text) {
    _ttsTextBuffer.write(text);
    if (text.contains(' ')) {
      _ttsBufferWordCount += text.split(' ').length - 1;
    }

    final currentStr = _ttsTextBuffer.toString();
    final bool hasBoundary = currentStr.contains(',') ||
        currentStr.contains('.') ||
        currentStr.contains('!') ||
        currentStr.contains('?') ||
        currentStr.contains(';') ||
        currentStr.contains(':') ||
        currentStr.contains('-') ||
        currentStr.contains('»') ||
        currentStr.contains('"');

    if (hasBoundary || _ttsBufferWordCount >= 1) {
      _flushTtsBuffer(force: false);
    }
  }

  void _flushTtsBuffer({bool force = false, bool isEnd = false}) {
    final str = _ttsTextBuffer.toString();
    if (str.isEmpty) {
      if (isEnd && _currentTtsStreamActive) {
        _sendTextToTts('', textEnd: true);
      }
      return;
    }

    if (force || isEnd) {
      if (str.trim().isNotEmpty) {
        _sendTextToTts(str, textEnd: isEnd);
      } else if (isEnd && _currentTtsStreamActive) {
        _sendTextToTts('', textEnd: true);
      }
      _ttsTextBuffer.clear();
      _ttsBufferWordCount = 0;
      return;
    }

    int lastBoundary = -1;

    for (int i = str.length - 1; i >= 0; i--) {
      final char = str[i];
      if (char == ',' ||
          char == '.' ||
          char == '!' ||
          char == '?' ||
          char == ';' ||
          char == ':' ||
          char == '-' ||
          char == '»' ||
          char == '"') {
        lastBoundary = i;
        break;
      } else if (char == ' ' && lastBoundary == -1) {
        lastBoundary = i;
      }
    }

    if (lastBoundary != -1) {
      final toSend = str.substring(0, lastBoundary + 1);
      final remainder = str.substring(lastBoundary + 1);

      if (toSend.trim().isNotEmpty) {
        _sendTextToTts(toSend, textEnd: false);
      }
      _ttsTextBuffer.clear();
      _ttsBufferWordCount = 0;
      if (remainder.isNotEmpty) {
        _ttsTextBuffer.write(remainder);
        _ttsBufferWordCount = remainder.split(' ').length - 1;
      }
    } else if (str.trim().isNotEmpty) {
      _sendTextToTts(str, textEnd: false);
      _ttsTextBuffer.clear();
      _ttsBufferWordCount = 0;
    }
  }

  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_currentState == TranslationConnectionState.connected) {
        try {
          _sttChannel?.sink.add(jsonEncode({'type': 'ping'}));
          _ttsChannel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          _log('Error sending keep-alive ping: $e');
        }
      }
    });
  }

  Future<void> _reconnectTtsChannel() async {
    if (_currentState != TranslationConnectionState.connected || _apiKey.isEmpty) return;
    _log('Attempting to reconnect TTS WebSocket...');
    try {
      await _ttsSubscription?.cancel();
      _ttsSubscription = null;
      final ttsUri = Uri.parse(_ttsBaseUrl);
      final headers = {'Authorization': 'Bearer $_apiKey'};
      final protocols = ['soniox-api-key', _apiKey];
      final factory = channelFactory;
      if (factory != null) {
        _ttsChannel = factory(ttsUri, headers);
      } else if (kIsWeb) {
        _ttsChannel = WebSocketChannel.connect(ttsUri, protocols: protocols);
      } else {
        _ttsChannel = IOWebSocketChannel.connect(ttsUri, headers: headers);
      }
      _ttsSubscription = _ttsChannel!.stream.listen(
        (data) => _handleTtsMessage(data),
        onError: (error, stackTrace) {
          _log('Reconnected TTS WebSocket error: $error');
        },
        onDone: () {
          _log('Reconnected TTS WebSocket closed');
        },
      );
      _currentTtsStreamActive = false;
      _startNewTtsStream();
      _log('TTS WebSocket successfully reconnected');
    } catch (e) {
      _log('Failed to reconnect TTS WebSocket: $e');
    }
  }

  void _markReady() {
    if (_isReady) return;
    _pending.clear();
    _isReady = true;
    _startKeepAliveTimer();
    _log('Soniox session ready after ${_connectWatch?.elapsedMilliseconds} ms');
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

  void _handleSttMessage(dynamic message) {
    if (_currentState == TranslationConnectionState.disconnected ||
        _currentState == TranslationConnectionState.closed) {
      return;
    }
    try {
      if (message is! String) return;
      final Map<String, dynamic> response = jsonDecode(message);

      if (response.containsKey('error_code') && response['error_code'] != null) {
        _log('Soniox STT Error: ${response['error_code']} - ${response['error_message']}');
        _failReady(StateError('Soniox error: ${response['error_message']}'));
        _setState(TranslationConnectionState.error);
        return;
      }

      // Check if STT response contains audio directly
      final String? sttAudio =
          response['audio'] as String? ?? response['audio_base64'] as String?;
      if (sttAudio != null && sttAudio.isNotEmpty) {
        final Uint8List audioBytes = base64Decode(sttAudio);
        _emitAudioDelta(audioBytes, sampleRate: 24000);
      }

      final List<dynamic>? tokens = response['tokens'] as List<dynamic>?;
      if (tokens != null) {
        for (final tokenObj in tokens) {
          if (tokenObj is! Map<String, dynamic>) continue;
          final String text = tokenObj['text'] as String? ?? '';
          final String translationStatus =
              tokenObj['translation_status'] as String? ?? '';

          // Check if token contains audio
          final String? tokenAudio = tokenObj['audio'] as String? ??
              tokenObj['audio_base64'] as String?;
          if (tokenAudio != null && tokenAudio.isNotEmpty) {
            final Uint8List audioBytes = base64Decode(tokenAudio);
            _emitAudioDelta(audioBytes, sampleRate: 24000);
          }

          final bool isFinal = tokenObj['is_final'] as bool? ??
              tokenObj['final'] as bool? ??
              true;

          if (text == '<end>') {
            _log('Utterance end detected; flushing TTS buffer');
            _flushTtsBuffer(force: true, isEnd: true);
          } else if (translationStatus == 'original' && text.isNotEmpty) {
            if (!_sourceTranscriptController.isClosed) {
              _sourceTranscriptController.add(text);
            }
          } else if (translationStatus == 'translation' && text.isNotEmpty) {
            if (!_transcriptDeltaController.isClosed) {
              _transcriptDeltaController.add(text);
            }
            if (isFinal) {
              _bufferAndSendTtsText(text);
            }
          }
        }
      }
    } catch (e, stackTrace) {
      _log('Error handling STT message: $e', error: e, stackTrace: stackTrace);
    }
  }

  final Map<String, int> _streamChunkCounters = {};

  int _getStreamIndex(String streamId) {
    if (streamId.startsWith('stream-')) {
      final parsed = int.tryParse(streamId.substring(7));
      if (parsed != null) return parsed;
    }
    return _ttsStreamIndex;
  }

  void _emitAudioDelta(Uint8List bytes, {int sampleRate = 24000, String streamId = ''}) {
    if (!_audioDeltaController.isClosed && bytes.isNotEmpty) {
      final id = streamId.isNotEmpty ? streamId : _currentTtsStreamId;
      final streamIdx = _getStreamIndex(id);
      final chunkIdx = (_streamChunkCounters[id] ?? 0) + 1;
      _streamChunkCounters[id] = chunkIdx;

      final sequenceNumber = streamIdx * 1000000 + chunkIdx;

      _audioDeltaController.add(
        AudioDelta(
          bytes,
          sampleRate: sampleRate,
          sequenceNumber: sequenceNumber,
          streamId: id,
        ),
      );
    }
  }

  void _processIncomingTtsAudio(String streamId, Uint8List audioBytes) {
    if (_audioDeltaController.isClosed) return;
    _emitAudioDelta(audioBytes, sampleRate: 24000, streamId: streamId);
  }

  void _markStreamCompleted(String streamId) {
    _completedStreams.add(streamId);
    if (_completedStreams.length > 100) {
      _completedStreams.remove(_completedStreams.first);
    }
  }

  void _scheduleStreamCompletionFallback(String streamId) {
    Timer(const Duration(milliseconds: 5000), () {
      if (_streamOrder.contains(streamId) && !_completedStreams.contains(streamId)) {
        _log('Fallback stream completion timeout for $streamId');
        _markStreamCompleted(streamId);
      }
    });
  }

  void _sendTextToTts(String text, {bool textEnd = false}) {
    if (_ttsChannel == null) return;

    if (!_currentTtsStreamActive) {
      if (text.isEmpty && textEnd) {
        // Stream is already inactive/closed; ignore sending empty text_end
        return;
      }
      _startNewTtsStream();
    }

    final payload = {
      'stream_id': _currentTtsStreamId,
      'text': text,
      'text_end': textEnd,
    };
    _log('Sending text to TTS ($_currentTtsStreamId): "$text" (textEnd: $textEnd)');
    _ttsChannel?.sink.add(jsonEncode(payload));

    if (textEnd) {
      _scheduleStreamCompletionFallback(_currentTtsStreamId);
      _currentTtsStreamActive = false;
      _ttsInactivityTimer?.cancel();
      _ttsInactivityTimer = null;
    } else {
      _restartTtsInactivityTimer();
    }
  }

  void _handleTtsMessage(dynamic message) {
    if (_currentState == TranslationConnectionState.disconnected ||
        _currentState == TranslationConnectionState.closed) {
      return;
    }
    try {
      if (message == null) return;

      Uint8List? rawBytes;
      if (message is Uint8List) {
        rawBytes = message;
      } else if (message is ByteBuffer) {
        rawBytes = message.asUint8List();
      } else if (message is TypedData) {
        rawBytes = message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes);
      } else if (message is List<int>) {
        rawBytes = Uint8List.fromList(message);
      }

      if (rawBytes != null) {
        _processIncomingTtsAudio(_currentTtsStreamId, rawBytes);
        return;
      }

      if (message is String) {
        final Map<String, dynamic> response = jsonDecode(message);
        final String msgStreamId = response['stream_id'] as String? ?? _currentTtsStreamId;

        if (response.containsKey('error_code') && response['error_code'] != null) {
          _log('Soniox TTS Error: ${response['error_code']} - ${response['error_message']}');
          _markStreamCompleted(msgStreamId);
          if (msgStreamId == _currentTtsStreamId) {
            _currentTtsStreamActive = false;
          }
          return;
        }

        if (response.containsKey('error') && response['error'] != null) {
          _log('Soniox TTS Error: ${response['error']}');
          _markStreamCompleted(msgStreamId);
          if (msgStreamId == _currentTtsStreamId) {
            _currentTtsStreamActive = false;
          }
          return;
        }

        final String? base64Audio = response['audio'] as String?;
        if (base64Audio != null && base64Audio.isNotEmpty) {
          final Uint8List audioBytes = base64Decode(base64Audio);
          _processIncomingTtsAudio(msgStreamId, audioBytes);
        }

        final bool audioEnd = response['audio_end'] == true;
        final bool terminated = response['terminated'] == true;

        if (audioEnd || terminated) {
          _log('TTS stream finished ($msgStreamId): audioEnd=$audioEnd, terminated=$terminated');
          _markStreamCompleted(msgStreamId);
          if (msgStreamId == _currentTtsStreamId) {
            _currentTtsStreamActive = false;
          }
        }
      }
    } catch (e, stackTrace) {
      _log('Error handling TTS message: $e', error: e, stackTrace: stackTrace);
    }
  }

  /// Sends raw PCM16 (24 kHz, mono) audio chunks to the STT WebSocket as binary frames.
  void sendAudioChunk(Uint8List pcm16Chunk) {
    if (!_isReady ||
        _currentState != TranslationConnectionState.connected ||
        _sttChannel == null) {
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
    _sttChannel?.sink.add(frame);
    _sentFrames++;
    _sentBytes += frame.length;
    _logFirstFrameLevel(frame);
  }

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
    _log('Frame #$_levelLoggedFrames sent, RMS level: ${rms.toStringAsFixed(4)}');
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
      _log('Audio sent so far: $_sentFrames frames, $_sentBytes bytes');
    }
  }

  void _flushPending() {
    if (_pending.isEmpty || _sttChannel == null) {
      _pending.clear();
      return;
    }
    final Uint8List rest = _pending.takeBytes();
    final Uint8List frame = Uint8List(frameBytes);
    frame.setRange(0, rest.length, rest);
    _sendFrame(frame);
  }

  Future<void> gracefulStop() async {
    if (_currentState != TranslationConnectionState.connected) {
      await close();
      return;
    }

    _log('Initiating graceful stop...');
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _ttsInactivityTimer?.cancel();
    _ttsInactivityTimer = null;
    _flushPending();
    _flushTtsBuffer(force: true, isEnd: true);
    _isReady = false;
    _setState(TranslationConnectionState.closing);

    // Signal end of audio to STT WebSocket by sending empty frame
    _sttChannel?.sink.add('');
    if (_currentTtsStreamActive) {
      _sendTextToTts('', textEnd: true);
    }

    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(seconds: 3), () {
      if (_currentState == TranslationConnectionState.closing) {
        _log('Graceful stop timeout; forcing close');
        close();
      }
    });
  }

  Future<void> close() async {
    _log('Closing Soniox WebSocket connections...');
    _currentState = TranslationConnectionState.disconnected;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _ttsTextBuffer.clear();
    _ttsBufferWordCount = 0;
    _ttsInactivityTimer?.cancel();
    _ttsInactivityTimer = null;
    _streamChunkCounters.clear();
    _streamOrder.clear();
    _streamAudioBuffers.clear();
    _completedStreams.clear();
    _stopTimer?.cancel();
    _stopTimer = null;
    _pending.clear();
    _isReady = false;
    _levelLoggedFrames = 0;
    final readyCompleter = _readyCompleter;
    _readyCompleter = null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete();
    }
    _sentFrames = 0;
    _sentBytes = 0;
    _lastStatsLog = null;

    await _sttSubscription?.cancel();
    _sttSubscription = null;
    await _ttsSubscription?.cancel();
    _ttsSubscription = null;

    await _sttChannel?.sink.close();
    _sttChannel = null;
    await _ttsChannel?.sink.close();
    _ttsChannel = null;

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
