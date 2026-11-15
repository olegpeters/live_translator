import 'dart:async';

import '../audio/playout_scheduler.dart' show SegmentBoundary;

/// A piece of text for TTS. [isEnd] closes the current TTS stream (`text_end: true`).
class TextPiece {
  final String text;
  final bool isEnd;

  /// Boundary type when [isEnd] is set (controls the pause after this segment).
  final SegmentBoundary? boundary;

  const TextPiece(this.text, {this.isEnd = false, this.boundary});

  @override
  String toString() => 'TextPiece("$text", isEnd: $isEnd, boundary: $boundary)';
}

/// Turns streamed, final translation tokens into TTS text units.
///
/// - Only complete words are forwarded (tokens are sub-words like "зна" + "ем").
/// - A TTS stream (segment) spans one sentence: it ends at confirmed sentence punctuation,
///   at the STT endpoint (`<end>`), or when no text arrives for [idleClose] (Soniox kills
///   streams after a few seconds without text). Commas never end a stream, so prosody
///   across clauses is kept even when the translation arrives in bursts.
/// - Very long sentences are split at the next clause boundary after [maxSegmentChars].
class TranslationSegmenter {
  /// Below the Soniox per-stream text timeout ("a few seconds", observed 408 after ~2–3 s).
  /// Translation bursts are often ~1.6 s apart, so this must stay above that.
  static const Duration defaultIdleClose = Duration(milliseconds: 1800);
  static const int maxSegmentChars = 600;

  final void Function(TextPiece piece) onPiece;
  final Duration idleClose;

  /// Text received but not yet forwarded (incomplete word / unconfirmed sentence end).
  String _pending = '';

  /// Characters forwarded in the currently open stream.
  int _openChars = 0;
  bool _streamOpen = false;
  Timer? _idleTimer;

  static final RegExp _sentenceEnd = RegExp(r'[.!?…]+[»"”’)\]]*$');
  static final RegExp _clauseEnd = RegExp(r'[,;:]+[»"”’)\]]*$');
  // Sentence punctuation followed by whitespace inside the pending text = confirmed boundary.
  static final RegExp _confirmedSentence = RegExp(r'[.!?…]+[»"”’)\]]*(?=\s)');

  TranslationSegmenter({required this.onPiece, this.idleClose = defaultIdleClose});

  bool get hasOpenStream => _streamOpen;

  /// Adds a final translation token.
  void addToken(String token) {
    if (token.isEmpty) return;
    _pending += token;
    _process();
    _restartIdleTimer();
  }

  /// STT utterance end (`<end>`): close the current stream with everything pending.
  void endOfUtterance() => _closeStream(defaultBoundary: SegmentBoundary.sentence);

  /// Flushes everything and closes the stream (e.g. stop).
  void flush() => _closeStream(defaultBoundary: SegmentBoundary.sentence);

  void reset() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _pending = '';
    _openChars = 0;
    _streamOpen = false;
  }

  void dispose() => reset();

  void _process() {
    while (true) {
      // 1. Confirmed sentence end (punctuation followed by whitespace) -> end stream there.
      final m = _confirmedSentence.firstMatch(_pending);
      if (m != null) {
        final head = _pending.substring(0, m.end);
        _pending = _pending.substring(m.end);
        _emit(head, isEnd: true, boundary: SegmentBoundary.sentence);
        continue;
      }

      // 2. Forward complete words: everything up to the last whitespace. A trailing
      //    sentence punctuation stays pending until confirmed (could be "т.е." / "3.5").
      final lastSpace = _pending.lastIndexOf(RegExp(r'\s'));
      String ready;
      if (_clauseEnd.hasMatch(_pending)) {
        ready = _pending; // word complete: ends with a clause punctuation
      } else if (lastSpace > 0) {
        ready = _pending.substring(0, lastSpace);
      } else {
        ready = '';
      }
      if (ready.trim().isEmpty) return;
      _pending = _pending.substring(ready.length);

      // 3. Overlong sentence: split at a clause boundary.
      if (_openChars + ready.length >= maxSegmentChars && _clauseEnd.hasMatch(ready)) {
        _emit(ready, isEnd: true, boundary: SegmentBoundary.clause);
      } else {
        _emit(ready, isEnd: false);
      }
      return;
    }
  }

  void _closeStream({required SegmentBoundary defaultBoundary}) {
    _idleTimer?.cancel();
    _idleTimer = null;
    final text = _pending;
    _pending = '';
    if (text.trim().isEmpty && !_streamOpen) return;
    final trimmed = text.trimRight();
    final boundary = _sentenceEnd.hasMatch(trimmed)
        ? SegmentBoundary.sentence
        : _clauseEnd.hasMatch(trimmed)
            ? SegmentBoundary.clause
            : defaultBoundary;
    _emit(text, isEnd: true, boundary: boundary);
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleClose, () {
      _idleTimer = null;
      if (!_streamOpen && _pending.trim().isEmpty) return;
      final trimmed = _pending.trimRight();
      final endsSentence = _sentenceEnd.hasMatch(trimmed);
      final endsClause = _clauseEnd.hasMatch(trimmed) || (trimmed.isEmpty && _streamOpen);
      _closeStream(
        defaultBoundary: endsSentence
            ? SegmentBoundary.sentence
            : endsClause
                ? SegmentBoundary.clause
                : SegmentBoundary.soft,
      );
    });
  }

  void _emit(String text, {required bool isEnd, SegmentBoundary? boundary}) {
    final normalized = normalize(text, isStreamStart: !_streamOpen);
    if (normalized.trim().isEmpty && !isEnd) return;
    if (normalized.trim().isEmpty && isEnd && !_streamOpen) return;
    _streamOpen = !isEnd;
    _openChars = isEnd ? 0 : _openChars + normalized.length;
    onPiece(TextPiece(normalized, isEnd: isEnd, boundary: isEnd ? boundary : null));
  }

  /// Light text normalization for TTS.
  static String normalize(String text, {bool isStreamStart = false}) {
    var t = text
        .replaceAll(RegExp(r'\s+[—–]\s+'), ', ')
        .replaceAll(RegExp(r'^[—–]\s+'), '')
        .replaceAll(RegExp(r'[«»“”„"]'), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    if (isStreamStart) t = t.trimLeft();
    return t;
  }
}
