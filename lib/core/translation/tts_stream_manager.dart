import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

import '../audio/playout_scheduler.dart' show SegmentBoundary;
import 'translation_segmenter.dart';

/// Audio (or end marker) of one TTS stream, with a sequence number for playout ordering.
class TtsAudioEvent {
  final String streamId;

  /// `streamIndex * 1000000 + chunkIndex`; monotonic within a session (also across reconnects).
  final int sequenceNumber;
  final Uint8List bytes;
  final bool isLast;
  final SegmentBoundary? boundary;

  /// First text sent -> first audio received, reported once per stream.
  final double? latencySeconds;

  const TtsAudioEvent({
    required this.streamId,
    required this.sequenceNumber,
    required this.bytes,
    this.isLast = false,
    this.boundary,
    this.latencySeconds,
  });
}

class _TtsStream {
  final String id;
  final int index;
  final StringBuffer text = StringBuffer();
  bool textEnded = false;
  SegmentBoundary boundary = SegmentBoundary.sentence;
  bool configured = false;
  bool audioReceived = false;
  bool endEmitted = false;
  bool retryPending = false;
  int retries = 0;
  int chunkCounter = 0;
  DateTime? firstTextAt;
  bool latencyReported = false;
  Timer? endFallback;

  _TtsStream(this.id, this.index);
}

/// Manages Soniox realtime TTS streams on one WebSocket connection.
///
/// - One stream per [TextPiece] segment (opened on the first piece, closed by `isEnd`).
/// - At most [maxConcurrentStreams] streams are configured at once (Soniox limit: 5);
///   further streams wait and are configured when one terminates.
/// - Errors without audio yet (429 / 408 / 5xx) are retried with the *same* stream id after
///   termination, so playout order is preserved. Otherwise the stream gets an end marker.
/// - [onConnectionReset] re-sends streams that produced no audio yet; streams with partial
///   audio are ended (re-synthesizing would duplicate speech).
class TtsStreamManager {
  static const int maxConcurrentStreams = 4;
  static const int maxRetries = 2;
  static const Duration endFallbackTimeout = Duration(seconds: 8);
  static const Set<int> retryableErrors = {408, 429, 500, 503};

  final void Function(Map<String, dynamic> message) send;
  final Map<String, dynamic> Function(String streamId) configFor;
  final void Function(TtsAudioEvent event) onAudio;
  final void Function(String message) log;

  int _streamIndex = 1;
  _TtsStream? _open;
  final Map<String, _TtsStream> _streams = {};
  final List<_TtsStream> _waiting = [];

  TtsStreamManager({
    required this.send,
    required this.configFor,
    required this.onAudio,
    void Function(String message)? log,
  }) : log = log ?? ((_) {});

  bool get hasOpenStream => _open != null;
  int get activeStreamCount => _streams.values.where((s) => s.configured).length;
  int get nextStreamIndex => _streamIndex + 1;

  /// New translation session: stream indices restart.
  void resetSession() {
    for (final s in _streams.values) {
      s.endFallback?.cancel();
    }
    _streams.clear();
    _waiting.clear();
    _open = null;
    _streamIndex = 1;
  }

  void sendPiece(TextPiece piece) {
    var stream = _open;
    if (stream == null) {
      if (piece.text.trim().isEmpty) return; // nothing to synthesize
      _streamIndex++;
      stream = _TtsStream('stream-$_streamIndex', _streamIndex);
      _streams[stream.id] = stream;
      _open = stream;
      if (activeStreamCount < maxConcurrentStreams) {
        _configure(stream);
      } else {
        _waiting.add(stream);
        log('TTS concurrency limit reached; ${stream.id} waiting (${_waiting.length} queued)');
      }
    }

    stream.firstTextAt ??= clock.now();
    stream.text.write(piece.text);
    if (piece.isEnd) {
      stream.textEnded = true;
      if (piece.boundary != null) stream.boundary = piece.boundary!;
      _open = null;
      _armEndFallback(stream);
    }
    if (stream.configured) {
      _sendText(stream, piece.text, piece.isEnd);
    }
  }

  void _configure(_TtsStream stream) {
    stream.configured = true;
    send(configFor(stream.id));
    // Replay text accumulated while waiting (or for a retry) in one message.
    final text = stream.text.toString();
    if (text.isNotEmpty || stream.textEnded) {
      _sendText(stream, text, stream.textEnded);
    }
  }

  void _sendText(_TtsStream stream, String text, bool end) {
    if (text.isEmpty && !end) return;
    // Release builds never log translated text (privacy policy: log holds no translations).
    final shown = kReleaseMode ? '${text.length} chars' : '"$text"';
    log('Sending text to TTS (${stream.id}): $shown (textEnd: $end)');
    send({'stream_id': stream.id, 'text': text, 'text_end': end});
  }

  void _armEndFallback(_TtsStream stream) {
    stream.endFallback?.cancel();
    stream.endFallback = Timer(endFallbackTimeout, () {
      log('TTS ${stream.id}: no termination within ${endFallbackTimeout.inSeconds}s; ending it');
      _emitEnd(stream);
      _remove(stream);
    });
  }

  /// Handles a JSON message from the TTS WebSocket.
  void handleMessage(Map<String, dynamic> msg) {
    final id = msg['stream_id'] as String?;
    final stream = id == null ? null : _streams[id];
    if (stream == null) {
      if (msg['audio'] != null) log('TTS audio for unknown/finished stream $id dropped');
      return;
    }

    final errorCode = (msg['error_code'] as num?)?.toInt();
    if (errorCode != null) {
      log('Soniox TTS error ($id): $errorCode ${msg['error_type'] ?? ''} - ${msg['error_message'] ?? ''}');
      if (retryableErrors.contains(errorCode) && !stream.audioReceived && stream.retries < maxRetries) {
        stream.retryPending = true;
        stream.retries++;
        stream.configured = false;
      } else {
        _emitEnd(stream);
      }
      // The server follows up with {"terminated": true}; the retry / removal happens there.
      return;
    }

    final audio = msg['audio'] as String?;
    final audioEnd = msg['audio_end'] == true;
    if (audio != null && audio.isNotEmpty) {
      final bytes = base64Decode(audio);
      double? latency;
      if (!stream.latencyReported && stream.firstTextAt != null) {
        stream.latencyReported = true;
        latency = clock.now().difference(stream.firstTextAt!).inMilliseconds / 1000.0;
        log('Measured TTS latency for ${stream.id}: ${latency.toStringAsFixed(2)} s');
      }
      stream.audioReceived = true;
      if (stream.textEnded) _armEndFallback(stream);
      _emitAudio(stream, bytes, isLast: audioEnd, latency: latency);
      if (audioEnd) stream.endEmitted = true;
    } else if (audioEnd) {
      _emitEnd(stream);
    }

    if (msg['terminated'] == true) {
      if (stream.retryPending) {
        stream.retryPending = false;
        final delayMs = 300 * stream.retries;
        log('Retrying TTS ${stream.id} in ${delayMs}ms (attempt ${stream.retries})');
        Timer(Duration(milliseconds: delayMs), () {
          if (_streams.containsKey(stream.id) && !stream.configured) _configure(stream);
        });
        return;
      }
      log('TTS stream finished (${stream.id})');
      _emitEnd(stream);
      _remove(stream);
    }
  }

  /// The TTS WebSocket was replaced by a new connection.
  void onConnectionReset() {
    for (final stream in _streams.values.toList()) {
      if (stream.audioReceived) {
        log('TTS reconnect: ending ${stream.id} (partial audio already played)');
        _emitEnd(stream);
        _remove(stream, configureNext: false);
        if (identical(_open, stream)) _open = null;
      } else {
        stream.configured = false;
        stream.retryPending = false;
        if (!_waiting.contains(stream)) _waiting.add(stream);
      }
    }
    _waiting.sort((a, b) => a.index.compareTo(b.index));
    _configureWaiting();
  }

  void _emitAudio(_TtsStream stream, Uint8List bytes, {bool isLast = false, double? latency}) {
    stream.chunkCounter++;
    onAudio(TtsAudioEvent(
      streamId: stream.id,
      sequenceNumber: stream.index * 1000000 + stream.chunkCounter,
      bytes: bytes,
      isLast: isLast,
      boundary: isLast ? stream.boundary : null,
      latencySeconds: latency,
    ));
  }

  void _emitEnd(_TtsStream stream) {
    if (stream.endEmitted) return;
    stream.endEmitted = true;
    _emitAudio(stream, Uint8List(0), isLast: true);
  }

  void _remove(_TtsStream stream, {bool configureNext = true}) {
    stream.endFallback?.cancel();
    _streams.remove(stream.id);
    _waiting.remove(stream);
    if (identical(_open, stream)) _open = null;
    if (configureNext) _configureWaiting();
  }

  void _configureWaiting() {
    while (_waiting.isNotEmpty && activeStreamCount < maxConcurrentStreams) {
      _configure(_waiting.removeAt(0));
    }
  }

  void dispose() => resetSession();
}
