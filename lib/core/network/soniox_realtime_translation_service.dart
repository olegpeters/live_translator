import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../audio/playout_scheduler.dart' show SegmentBoundary;
import '../logging/app_logger.dart';
import '../translation/glossary.dart';
import '../translation/translation_segmenter.dart';
import '../translation/tts_stream_manager.dart';
import 'soniox_region.dart';

export 'soniox_region.dart' show SonioxRegion, WebSocketChannelFactory;

enum TranslationConnectionState {
  disconnected,
  connecting,
  connected,
  closing,
  closed,
  error,
}


/// A chunk of translated PCM16 mono audio together with its sample rate and sequence tracking.
class AudioDelta {
  static const int defaultSampleRate = 24000;

  final Uint8List bytes;
  final int sampleRate;
  final int sequenceNumber;
  final String streamId;
  final double? measuredLatencySeconds;
  final bool isLastInStream;

  /// Segment boundary type (set on the last chunk / end marker of a stream).
  final SegmentBoundary? boundary;

  const AudioDelta(
    this.bytes, {
    this.sampleRate = defaultSampleRate,
    this.sequenceNumber = 0,
    this.streamId = '',
    this.measuredLatencySeconds,
    this.isLastInStream = false,
    this.boundary,
  });
}

/// Incremental transcript update from one STT response.
///
/// Soniox sends final tokens exactly once; non-final tokens are re-sent with every response
/// and replace the previous provisional text.
class TranscriptUpdate {
  final bool isSource;
  final String finalText;
  final String provisionalText;

  const TranscriptUpdate({
    required this.isSource,
    required this.finalText,
    required this.provisionalText,
  });
}

class SonioxRealtimeTranslationService {
  /// 50 ms of 24 kHz PCM16 mono audio (24000 * 0.05 * 2 bytes) for low latency.
  static const int frameBytes = 2400;
  /// Max buffered pending input audio (~3 seconds of 24kHz PCM16 mono = 144,000 bytes)
  static const int maxPendingInputAudioBytes = 144000;
  static const Duration _statsLogInterval = Duration(seconds: 5);
  static const int _levelLoggedFramesLimit = 5;

  /// TTS connection is closed by Soniox after ~40s without any message; keepalive every 20s.
  static const Duration ttsKeepAliveInterval = Duration(seconds: 20);

  /// Gap between consecutive final source tokens that is logged as possible lost speech.
  static const int sttGapLogThresholdMs = 2500;

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
  SonioxRegion _region = SonioxRegion.eu;
  String _targetLanguage = 'ru';
  String _voice = 'Daniel';
  bool _enableSourceTranscription = false;
  String? _sourceLanguage;
  Glossary _glossary = const Glossary();
  bool _speechEnabled = true;
  int _ignoredTokens = 0;
  Timer? _keepAliveTimer;
  int _ttsReconnectAttempts = 0;

  late final TtsStreamManager _tts = TtsStreamManager(
    send: _sendTts,
    configFor: _ttsConfig,
    onAudio: _onTtsAudio,
    log: _log,
  );
  late final TranslationSegmenter _segmenter = TranslationSegmenter(onPiece: _tts.sendPiece);
  DateTime? _lastInputAudioSentTime;
  double _translationLatencySeconds = 0.0;

  final _audioDeltaController = StreamController<AudioDelta>.broadcast();
  final _transcriptDeltaController = StreamController<String>.broadcast();
  final _sourceTranscriptController = StreamController<String>.broadcast();
  final _transcriptUpdateController = StreamController<TranscriptUpdate>.broadcast();
  int? _lastFinalSourceEndMs;
  final _stateController =
      StreamController<TranslationConnectionState>.broadcast();

  TranslationConnectionState _currentState =
      TranslationConnectionState.disconnected;

  Stream<AudioDelta> get onAudioDelta => _audioDeltaController.stream;
  Stream<String> get onTranscriptDelta => _transcriptDeltaController.stream;
  Stream<String> get onSourceTranscriptDelta =>
      _sourceTranscriptController.stream;
  /// Final + provisional transcript updates (source and target), one event per kind and STT response.
  Stream<TranscriptUpdate> get onTranscriptUpdate => _transcriptUpdateController.stream;
  Stream<TranslationConnectionState> get onStateChanged =>
      _stateController.stream;

  TranslationConnectionState get currentState => _currentState;
  bool get isReady => _isReady;
  bool get enableSourceTranscription => _enableSourceTranscription;
  double get translationLatencySeconds => _translationLatencySeconds;

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
    AppLogger.log(
      message,
      tag: 'SonioxService',
      level: error != null ? LogLevel.error : LogLevel.info,
      error: error,
      stackTrace: stackTrace,
    );
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
    bool newSession = true,
    String? sourceLanguage,
    Glossary glossary = const Glossary(),
    /// Region of the API key's Soniox project; null keeps the previous one (reconnects).
    SonioxRegion? region,
    /// Read the translation aloud (TTS connection); without it only text is produced.
    bool speechEnabled = true,
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
    if (region != null) _region = region;
    _targetLanguage = targetLanguage;
    _voice = voice;
    _enableSourceTranscription = enableSourceTranscription;
    _sourceLanguage = sourceLanguage;
    _glossary = glossary;
    _speechEnabled = speechEnabled;
    if (newSession) {
      // Stream indices stay monotonic across reconnects within a session:
      // the playout scheduler drops audio of segments it has already finished.
      _tts.resetSession();
      _segmenter.reset();
      _pending.clear();
    } else {
      _log('Reconnecting within session (next TTS stream index ${_tts.nextStreamIndex}, '
          '${_pending.length} bytes mic audio pending)');
    }
    _ttsReconnectAttempts = 0;
    _lastFinalSourceEndMs = null; // STT audio timeline restarts with every connection
    _lastInputAudioSentTime = null;
    _translationLatencySeconds = 0.0;
    _isReady = false;
    _levelLoggedFrames = 0;
    _connectWatch = Stopwatch()..start();
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;

    _setState(TranslationConnectionState.connecting);
    _log('Connecting to Soniox STT & TTS WebSockets (region ${_region.code})...');

    try {
      // 1. STT + translation, 2. TTS
      _sttChannel = openSonioxChannel(Uri.parse(_region.sttUrl), apiKey, factory: channelFactory);
      if (_speechEnabled) {
        _ttsChannel = openSonioxChannel(Uri.parse(_region.ttsUrl), apiKey, factory: channelFactory);
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

      if (_speechEnabled) {
        _listenTts();
        if (!newSession) {
          // New TTS connection: re-send streams that had not produced audio yet.
          _tts.onConnectionReset();
        }
      }

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
    // Authentication happens via Authorization header / WebSocket protocol only;
    // 'api_key' in the config is deprecated and must not be sent in addition.
    final config = {
      'model': 'stt-rt-v5',
      'audio_format': 'pcm_s16le',
      'sample_rate': 24000,
      'num_channels': 1,
      'enable_endpoint_detection': true,
      // Expected spoken language: improves recognition and keeps the target-language echo of
      // our own playback (speaker mode) from being treated as source speech.
      if (_sourceLanguage != null) 'language_hints': [_sourceLanguage],
      if (_glossary.toSonioxContext() != null) 'context': _glossary.toSonioxContext(),
      'translation': {
        'type': 'one_way',
        'target_language': _targetLanguage,
      },
    };
    _log('Sending STT config (source: ${_sourceLanguage ?? 'auto'}, target: $_targetLanguage, '
        'glossary: ${_glossary.terms.length} terms / ${_glossary.translationTerms.length} translations, '
        '~${_glossary.estimatedTokens} tokens)');
    if (_glossary.estimatedTokens > 7000) {
      _log('Warning: glossary context is close to the Soniox limit of 8000 tokens');
    }
    _sttChannel?.sink.add(jsonEncode(config));
  }

  Map<String, dynamic> _ttsConfig(String streamId) {
    _log('Sending TTS config: stream_id=$streamId, model=tts-rt-v2, language=$_targetLanguage, voice=$_voice');
    return {
      'stream_id': streamId,
      'model': 'tts-rt-v2',
      'language': _targetLanguage,
      'voice': _voice,
      'audio_format': 'pcm_s16le',
      'sample_rate': 24000,
    };
  }

  void _sendTts(Map<String, dynamic> message) {
    final channel = _ttsChannel;
    if (channel == null) {
      // Streams without audio are re-sent by TtsStreamManager.onConnectionReset().
      _log('TTS channel unavailable; message for ${message['stream_id']} deferred to reconnect');
      return;
    }
    channel.sink.add(jsonEncode(message));
  }

  void _onTtsAudio(TtsAudioEvent event) {
    if (_audioDeltaController.isClosed) return;
    _audioDeltaController.add(AudioDelta(
      event.bytes,
      sampleRate: 24000,
      sequenceNumber: event.sequenceNumber,
      streamId: event.streamId,
      measuredLatencySeconds: event.latencySeconds,
      isLastInStream: event.isLast,
      boundary: event.boundary,
    ));
  }

  void _listenTts() {
    final channel = _ttsChannel!;
    _ttsSubscription = channel.stream.listen(
      (data) => _handleTtsMessage(data),
      onError: (error, stackTrace) {
        _log('TTS WebSocket error: $error', error: error, stackTrace: stackTrace);
        _reconnectTtsChannel();
      },
      onDone: () {
        _log('TTS WebSocket closed (code: ${channel.closeCode})');
        if (identical(_ttsChannel, channel)) _reconnectTtsChannel();
      },
    );
  }

  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    // Soniox TTS closes the connection after ~40s without any client message (e.g. long pauses
    // between utterances). Keepalives don't extend per-stream text timeouts, so they're always safe.
    _keepAliveTimer = Timer.periodic(ttsKeepAliveInterval, (_) {
      if (_currentState == TranslationConnectionState.connected) {
        _ttsChannel?.sink.add(jsonEncode({'keep_alive': true}));
      }
    });
  }

  Future<void> _reconnectTtsChannel() async {
    if (!_speechEnabled || _currentState != TranslationConnectionState.connected || _apiKey.isEmpty) return;
    if (_ttsReconnectAttempts >= 5) {
      _log('TTS reconnect: giving up after $_ttsReconnectAttempts attempts');
      return;
    }
    _ttsReconnectAttempts++;
    final delay = Duration(milliseconds: 300 * _ttsReconnectAttempts);
    _log('Attempting to reconnect TTS WebSocket in ${delay.inMilliseconds} ms (attempt $_ttsReconnectAttempts)...');
    final oldSub = _ttsSubscription;
    final oldChannel = _ttsChannel;
    _ttsSubscription = null;
    _ttsChannel = null;
    await oldSub?.cancel();
    try {
      await oldChannel?.sink.close();
    } catch (_) {}
    await Future<void>.delayed(delay);
    if (_currentState != TranslationConnectionState.connected) return;

    try {
      _ttsChannel = openSonioxChannel(Uri.parse(_region.ttsUrl), _apiKey, factory: channelFactory);
      _listenTts();
      _log('TTS WebSocket reconnected');
      _tts.onConnectionReset();
    } catch (e) {
      _log('Failed to reconnect TTS WebSocket: $e');
      _reconnectTtsChannel();
    }
  }

  void _markReady() {
    if (_isReady) return;
    _isReady = true;
    _startKeepAliveTimer();
    _log('Soniox session ready after ${_connectWatch?.elapsedMilliseconds} ms');
    _setState(TranslationConnectionState.connected);
    _flushPending();
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

      final List<dynamic>? tokens = response['tokens'] as List<dynamic>?;
      if (tokens != null) {
        _handleSttTokens(tokens);
      }
    } catch (e, stackTrace) {
      _log('Error handling STT message: $e', error: e, stackTrace: stackTrace);
    }
  }

  void _handleSttTokens(List<dynamic> tokens) {
    final finalSource = StringBuffer();
    final provisionalSource = StringBuffer();
    final finalTarget = StringBuffer();
    final provisionalTarget = StringBuffer();

    for (final tokenObj in tokens) {
      if (tokenObj is! Map<String, dynamic>) continue;
      final String text = tokenObj['text'] as String? ?? '';
      final String translationStatus = tokenObj['translation_status'] as String? ?? '';
      final bool isFinal = tokenObj['is_final'] as bool? ?? tokenObj['final'] as bool? ?? true;

      if (text == '<end>') {
        if (_speechEnabled) {
          _log('Utterance end marker <end> detected; closing TTS segment');
          _segmenter.endOfUtterance();
        }
        continue;
      }
      if (text.isEmpty) continue;

      if (translationStatus == 'original') {
        // Original-language text is intentionally not logged (only timing for gap diagnostics).
        if (isFinal) {
          finalSource.write(text);
          _trackSourceTiming(tokenObj);
        } else {
          provisionalSource.write(text);
        }
      } else if (translationStatus == 'none') {
        // Spoken text not translated, typically already in the target language
        // (e.g. echo of our own TTS output in speaker mode).
        if (isFinal && ++_ignoredTokens % 20 == 1) {
          _log('STT: $_ignoredTokens final token(s) with translation_status "none" ignored '
              '(target-language speech / possible playback echo)');
        }
      } else if (translationStatus == 'translation') {
        if (isFinal) {
          _log('STT Token: "$text" [status: translation, isFinal: true]');
          if (_lastInputAudioSentTime != null) {
            _translationLatencySeconds =
                DateTime.now().difference(_lastInputAudioSentTime!).inMilliseconds / 1000.0;
          }
          finalTarget.write(text);
          if (_speechEnabled) _segmenter.addToken(text);
        } else {
          provisionalTarget.write(text);
        }
      }
    }

    void emit(bool isSource, StringBuffer fin, StringBuffer prov,
        StreamController<String> deltaController) {
      final f = fin.toString();
      if (f.isNotEmpty && !deltaController.isClosed) {
        deltaController.add(f);
      }
      if (!_transcriptUpdateController.isClosed) {
        _transcriptUpdateController.add(TranscriptUpdate(
          isSource: isSource,
          finalText: f,
          provisionalText: prov.toString(),
        ));
      }
    }

    emit(true, finalSource, provisionalSource, _sourceTranscriptController);
    emit(false, finalTarget, provisionalTarget, _transcriptDeltaController);
  }

  /// Logs gaps between consecutive final source tokens (audio timeline of the STT session),
  /// to correlate lost speech with playback activity. Text itself is not logged.
  void _trackSourceTiming(Map<String, dynamic> token) {
    final startMs = (token['start_ms'] as num?)?.toInt();
    final endMs = (token['end_ms'] as num?)?.toInt();
    if (startMs == null || endMs == null) return;
    final lastEnd = _lastFinalSourceEndMs;
    if (lastEnd != null && startMs - lastEnd >= sttGapLogThresholdMs) {
      _log('STT source gap: no recognized words between audio ${(lastEnd / 1000).toStringAsFixed(1)}s '
          'and ${(startMs / 1000).toStringAsFixed(1)}s (${((startMs - lastEnd) / 1000).toStringAsFixed(1)}s)');
    }
    if (lastEnd == null || endMs > lastEnd) {
      _lastFinalSourceEndMs = endMs;
    }
  }

  void _handleTtsMessage(dynamic message) {
    if (_currentState == TranslationConnectionState.disconnected ||
        _currentState == TranslationConnectionState.closed) {
      return;
    }
    try {
      if (message is String) {
        _tts.handleMessage(jsonDecode(message) as Map<String, dynamic>);
      } else if (message != null) {
        // Soniox TTS sends JSON with base64 audio and a stream_id. A raw binary frame carries no
        // stream_id, and guessing the stream would corrupt playout ordering -> drop it.
        _log('Unexpected binary TTS frame without stream_id; dropped');
      }
    } catch (e, stackTrace) {
      _log('Error handling TTS message: $e', error: e, stackTrace: stackTrace);
    }
  }

  /// Sends raw PCM16 (24 kHz, mono) audio chunks to the STT WebSocket as binary frames.
  void sendAudioChunk(Uint8List pcm16Chunk) {
    if (pcm16Chunk.isEmpty) return;

    if (!_isReady ||
        _currentState != TranslationConnectionState.connected ||
        _sttChannel == null) {
      _pending.add(pcm16Chunk);
      if (_pending.length > maxPendingInputAudioBytes) {
        final all = _pending.takeBytes();
        final overflow = all.length - maxPendingInputAudioBytes;
        _pending.add(Uint8List.sublistView(all, overflow));
        _log('STT channel not ready; input audio overflow, discarded $overflow oldest bytes');
      } else {
        _log('STT channel not ready; buffering input audio chunk (${pcm16Chunk.length} bytes, pending: ${_pending.length} bytes)');
      }
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
    _lastInputAudioSentTime = DateTime.now();
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

  bool get speechEnabled => _speechEnabled;

  /// Switches reading aloud on or off during a session.
  ///
  /// Off: closes the TTS connection and forgets its streams (no further TTS cost).
  /// On: opens the TTS connection and speaks [resumeText] first (typically the last translated
  /// sentence plus the sentence in progress), then continues with new translations.
  Future<void> setSpeechEnabled(bool enabled, {String resumeText = ''}) async {
    if (enabled == _speechEnabled) return;
    _speechEnabled = enabled;
    _log('Reading aloud ${enabled ? 'on' : 'off'}');
    if (!enabled) {
      final sub = _ttsSubscription;
      final channel = _ttsChannel;
      _ttsSubscription = null;
      _ttsChannel = null;
      _segmenter.reset();
      _tts.abandonAll();
      await sub?.cancel();
      try {
        await channel?.sink.close();
      } catch (_) {}
      return;
    }
    if (_currentState != TranslationConnectionState.connected) return; // next connect opens TTS
    _ttsReconnectAttempts = 0;
    _segmenter.reset();
    _ttsChannel = openSonioxChannel(Uri.parse(_region.ttsUrl), _apiKey, factory: channelFactory);
    _listenTts();
    if (resumeText.trim().isNotEmpty) _segmenter.addToken(resumeText);
  }

  Future<void> gracefulStop() async {
    if (_currentState != TranslationConnectionState.connected) {
      await close();
      return;
    }

    _log('Initiating graceful stop...');
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _flushPending();
    _segmenter.flush(); // closes the open TTS stream with everything pending
    _isReady = false;
    _setState(TranslationConnectionState.closing);

    // Signal end of audio to STT WebSocket by sending empty frame
    _sttChannel?.sink.add('');

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
    // TTS stream state, segmenter text and pending mic audio are kept so a reconnect continues
    // the session; connect(newSession: true) resets them.
    _lastInputAudioSentTime = null;
    _translationLatencySeconds = 0.0;
    _stopTimer?.cancel();
    _stopTimer = null;
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
    _segmenter.dispose();
    _tts.dispose();
    await _audioDeltaController.close();
    await _transcriptDeltaController.close();
    await _sourceTranscriptController.close();
    await _transcriptUpdateController.close();
    await _stateController.close();
  }
}
