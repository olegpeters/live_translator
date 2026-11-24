import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auditorium/core/audio/playout_scheduler.dart';
import 'package:auditorium/core/translation/translation_segmenter.dart';

void main() {
  late List<TextPiece> pieces;
  late TranslationSegmenter seg;

  void setUpSeg() {
    pieces = [];
    seg = TranslationSegmenter(onPiece: pieces.add);
  }

  /// Text of each TTS stream (pieces joined until isEnd).
  List<String> streams() {
    final out = <String>[];
    final cur = StringBuffer();
    for (final p in pieces) {
      cur.write(p.text);
      if (p.isEnd) {
        out.add(cur.toString());
        cur.clear();
      }
    }
    if (cur.isNotEmpty) out.add('${cur.toString()}…(open)');
    return out;
  }

  test('only complete words are forwarded', () {
    fakeAsync((async) {
      setUpSeg();
      for (final t in ['М', 'ы', ' зна', 'ем', ' истори']) {
        seg.addToken(t);
      }
      expect(pieces.map((p) => p.text).join(), 'Мы знаем');
      expect(pieces.any((p) => p.isEnd), isFalse);
      seg.dispose();
    });
  });

  test('log trace: sentence split across a 1.6s translation burst stays one TTS stream', () {
    fakeAsync((async) {
      setUpSeg();
      for (final t in ['М', 'ы', ' зна', 'ем', ' истори', 'ю,', ' в', ' кото', 'рой', ' при', 'су', 'т', 'стви', 'е', ' Бо', 'га']) {
        seg.addToken(t);
      }
      async.elapse(const Duration(milliseconds: 1590)); // gap between translation bursts in the log
      for (final t in [' о', 'чен', 'ь', ' центра', 'ль', 'ное', '.']) {
        seg.addToken(t);
      }
      async.elapse(const Duration(milliseconds: 600));
      seg.addToken(' В');
      seg.addToken(' цент');

      expect(streams().first, 'Мы знаем историю, в которой присутствие Бога очень центральное.');
      expect(pieces.firstWhere((p) => p.isEnd).boundary, SegmentBoundary.sentence);
      seg.dispose();
    });
  });

  test('sentence punctuation is only a boundary when followed by whitespace', () {
    fakeAsync((async) {
      setUpSeg();
      seg.addToken('Версия 3.');
      seg.addToken('5 готова.');
      seg.addToken(' Да');
      expect(streams().first, 'Версия 3.5 готова.');
      seg.dispose();
    });
  });

  test('STT endpoint closes the stream with the pending text', () {
    fakeAsync((async) {
      setUpSeg();
      seg.addToken('На.');
      expect(pieces, isEmpty);
      seg.endOfUtterance();
      expect(streams(), ['На.']);
      expect(pieces.last.boundary, SegmentBoundary.sentence);
      seg.dispose();
    });
  });

  test('idle timeout closes an open stream before Soniox kills it (soft boundary mid-sentence)', () {
    fakeAsync((async) {
      setUpSeg();
      seg.addToken('Народ берёт у Аарона идола');
      async.elapse(TranslationSegmenter.defaultIdleClose);
      expect(streams(), ['Народ берёт у Аарона идола']);
      expect(pieces.last.boundary, SegmentBoundary.soft);
      seg.dispose();
    });
  });

  test('idle timeout after a comma gives a clause boundary', () {
    fakeAsync((async) {
      setUpSeg();
      seg.addToken('В задании ниже,');
      async.elapse(TranslationSegmenter.defaultIdleClose);
      expect(pieces.last.isEnd, isTrue);
      expect(pieces.last.boundary, SegmentBoundary.clause);
      seg.dispose();
    });
  });

  test('normalization: dashes become commas, quotes removed, stream start trimmed', () {
    expect(TranslationSegmenter.normalize(' история — это «правда»', isStreamStart: true), 'история, это правда');
  });
}
