import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/utils/ReaderContrast.dart';

// The rules of book highlights: ranges, anchors, finding a highlight again in a replaced book, the colours.

BookHighlight make(String id, int chapter, ReaderRange range, List<List<String>> book, {HighlightCategory c = HighlightCategory.good, String note = '', int at = 0}) =>
    BookHighlight.create(id: id, chapter: chapter, range: range, paragraphs: book[chapter], category: c, note: note, createdMillis: at);

const para1 = 'Krishna is the Supreme Personality of Godhead. He is eternal, full of knowledge and bliss.';
const para2 = 'The living entity is part and parcel of the Lord. Therefore service is his nature.';
const para3 = 'Chant Hare Krishna and be happy.';

List<List<String>> book() => [
      [para1, para2, para3],
      ['Second chapter opens here.', 'Nothing about the soul at all.'],
    ];

void main() {
  group('the offset space', () {
    test('text runs in order, a picture is one placeholder character', () {
      expect(renderedParagraphText([const TextRun('ab'), const ImageRun('rId1'), const TextRun('cd')]), 'ab￼cd');
      expect(renderedParagraphText(const []), '');
    });
  });

  group('ranges', () {
    test('ordered() puts the earlier point first', () {
      expect(ReaderRange.ordered(2, 5, 0, 3), const ReaderRange(0, 3, 2, 5));
      expect(ReaderRange.ordered(1, 7, 1, 2), const ReaderRange(1, 2, 1, 7));
    });

    test('inside one paragraph', () {
      final b = book()[0];
      final r = ReaderRange(0, 0, 0, 7);
      expect(segmentsOf(r, b), [const ParagraphSegment(0, 0, 7)]);
      expect(textOfRange(r, b), 'Krishna');
    });

    test('across paragraphs: first from its offset, those between whole, the last up to its offset', () {
      final b = book()[0];
      final r = ReaderRange(0, para1.length - 6, 2, 5);
      expect(segmentsOf(r, b), [
        ParagraphSegment(0, para1.length - 6, para1.length),
        ParagraphSegment(1, 0, para2.length),
        const ParagraphSegment(2, 0, 5),
      ]);
      expect(textOfRange(r, b), 'bliss.\n$para2\nChant');
    });

    test('an empty part of a paragraph is left out; offsets beyond the text are clamped', () {
      final b = book()[0];
      expect(segmentsOf(ReaderRange(0, para1.length, 1, 4), b), [const ParagraphSegment(1, 0, 4)]);
      expect(segmentsOf(const ReaderRange(0, 0, 0, 9999), b), [ParagraphSegment(0, 0, para1.length)]);
      expect(segmentsOf(const ReaderRange(5, 0, 6, 3), b), isEmpty, reason: 'paragraphs that do not exist');
    });

    test('whole paragraphs', () {
      final b = book()[0];
      expect(wholeParagraphs(const ReaderRange(0, 3, 1, 4), b), ReaderRange(0, 0, 1, para2.length));
    });

    test('sentence around a point', () {
      final s = sentenceAround(para1, 5);
      expect(para1.substring(s.start, s.end), 'Krishna is the Supreme Personality of Godhead.');
      final t = sentenceAround(para1, para1.length - 3);
      expect(para1.substring(t.start, t.end), 'He is eternal, full of knowledge and bliss.');
      final single = sentenceAround(para3, 2);
      expect(para3.substring(single.start, single.end), para3);
      expect(sentenceAround('', 0), (start: 0, end: 0));
      final danda = sentenceAround('पहला वाक्य। दूसरा वाक्य।', 14);
      expect('पहला वाक्य। दूसरा वाक्य।'.substring(danda.start, danda.end), 'दूसरा वाक्य।');
    });
  });

  group('the stored highlight', () {
    test('create reads the text and the snippets; the fields round-trip', () {
      final b = book();
      final h = make('a', 0, const ReaderRange(0, 0, 0, 7), b, c: HighlightCategory.rare, note: 'my note');
      expect(h.text, 'Krishna');
      expect(h.snippetStart, 'Krishna');
      expect(h.snippetEnd, 'Krishna');
      final back = BookHighlight.fromFields('a', h.toFields())!;
      expect(back.anchor, h.anchor);
      expect(back.category, HighlightCategory.rare);
      expect(back.note, 'my note');
      expect(back.text, 'Krishna');
    });

    test('a very long selection keeps its start and end, and says how long it was', () {
      final long = [List.filled(3, 'word ' * 400).join('\n')];
      final h = BookHighlight.create(id: 'x', chapter: 0, range: ReaderRange(0, 0, 0, long[0].length), paragraphs: long, category: HighlightCategory.good);
      expect(h.text.length, kHighlightTextCap);
      expect(h.textLength, long[0].length);
      expect(h.truncated, isTrue);
      expect(h.snippetStart.length, kSnippetLength);
      expect(h.snippetEnd.length, kSnippetLength);
    });

    test('a note of any length is kept whole', () {
      final note = 'thought ' * 5000;
      final h = make('n', 0, const ReaderRange(0, 0, 0, 7), book(), note: note);
      expect(BookHighlight.fromFields('n', h.toFields())!.note.length, note.length);
    });

    test('a damaged document is not a highlight (it is simply not shown)', () {
      expect(BookHighlight.fromFields('z', {'category': 'good'}), isNull);
      expect(BookHighlight.fromFields('z', {'category': 'epic', 'chapterIndex': 0, 'startParagraph': 0, 'startOffset': 0, 'endParagraph': 0, 'endOffset': 3}), isNull);
    });
  });

  group('finding a highlight again', () {
    test('where it was stored, with the same text: it stays', () {
      final b = book();
      final h = make('a', 0, const ReaderRange(0, 8, 0, 14), b);
      expect(anchorHolds(h, b), isTrue);
      expect(resolveAnchor(h, b), h.anchor);
    });

    test('a paragraph added before it (the book file was replaced): found at its new place', () {
      final old = book();
      final h = make('a', 0, const ReaderRange(1, 4, 1, 17), old);
      expect(h.text, 'living entity');
      final replaced = [
        ['A brand new first paragraph.', para1, para2, para3],
        old[1],
      ];
      final a = resolveAnchor(h, replaced)!;
      expect(a.chapter, 0);
      expect(textOfRange(a.range, replaced[0]), 'living entity');
      expect(a.range.startPara, 2);
    });

    test('text edited around it: still found by the text', () {
      final old = book();
      final h = make('a', 0, const ReaderRange(0, 0, 0, 7), old);
      final replaced = [
        ['Preface: Krishna is the Supreme Personality of Godhead.', para2, para3],
        old[1],
      ];
      final a = resolveAnchor(h, replaced)!;
      expect(textOfRange(a.range, replaced[0]), 'Krishna');
      expect(a.range.startOffset, 9);
    });

    test('the chapter moved: found in the other chapter', () {
      final old = book();
      final h = make('a', 1, const ReaderRange(0, 0, 0, 14), old);
      expect(h.text, 'Second chapter');
      final replaced = [
        ['A new chapter was inserted.'],
        old[0],
        old[1],
      ];
      final a = resolveAnchor(h, replaced)!;
      expect(a.chapter, 2);
      expect(textOfRange(a.range, replaced[2]), 'Second chapter');
    });

    test('a highlight across paragraphs is found across paragraphs', () {
      final old = book();
      final h = make('a', 0, ReaderRange(0, para1.length - 6, 1, 8), old);
      final replaced = [
        ['Added.', para1, para2, para3],
        old[1],
      ];
      final a = resolveAnchor(h, replaced)!;
      expect(a.range.startPara, 1);
      expect(a.range.endPara, 2);
      expect(textOfRange(a.range, replaced[0]), h.text);
    });

    test('the same words twice: the one nearest where it was', () {
      final old = [
        ['alpha beta', 'filler', 'alpha beta', 'filler two'],
      ];
      final h = make('a', 0, const ReaderRange(2, 0, 2, 10), old);
      final replaced = [
        ['alpha beta', 'filler', 'NEW', 'alpha beta', 'filler two'],
      ];
      expect(resolveAnchor(h, replaced)!.range.startPara, 3, reason: 'nearer its old paragraph (2) than the first copy (0)');
    });

    test('a very long highlight is found again by its start and its end', () {
      final text = List.generate(60, (i) => 'Sentence number $i of the long passage.').join(' ');
      final old = [
        [text, 'tail'],
      ];
      final h = BookHighlight.create(id: 'x', chapter: 0, range: ReaderRange(0, 0, 0, text.length), paragraphs: old[0], category: HighlightCategory.excellent);
      expect(h.truncated, isTrue);
      final replaced = [
        ['inserted', text, 'tail'],
      ];
      final a = resolveAnchor(h, replaced)!;
      expect(a.range, ReaderRange(1, 0, 1, text.length));
    });

    test('the text is gone: null (the highlight is kept by the caller and simply not drawn)', () {
      final old = book();
      final h = make('a', 0, const ReaderRange(0, 0, 0, 7), old);
      final replaced = [
        ['A completely different book.'],
      ];
      expect(resolveAnchor(h, replaced), isNull);
    });

    test('never crashes: an anchor outside the book, an empty book, empty text', () {
      final b = book();
      final lost = BookHighlight(
        id: 'q',
        anchor: HighlightAnchor(9, const ReaderRange(40, 0, 41, 5)),
        text: 'Krishna',
        textLength: 7,
        snippetStart: 'Krishna',
        snippetEnd: 'Krishna',
        category: HighlightCategory.good,
      );
      expect(resolveAnchor(lost, b)!.chapter, 0, reason: 'found by its text');
      expect(resolveAnchor(lost, const []), isNull);
      expect(resolveAnchor(lost, [<String>[]]), isNull);
      final blank = lost.copyWith(text: '', textLength: 0, snippetStart: '', snippetEnd: '');
      expect(resolveAnchor(blank, b), isNull);
    });

    test('placeHighlights keeps the ones it can find, drops the others from drawing, oldest first', () {
      final b = book();
      final h1 = make('1', 0, const ReaderRange(0, 0, 0, 7), b, at: 20);
      final h2 = make('2', 0, const ReaderRange(1, 0, 1, 3), b, at: 10);
      final gone = BookHighlight(
        id: '3',
        anchor: HighlightAnchor(0, const ReaderRange(0, 0, 0, 4)),
        text: 'zzzz',
        textLength: 4,
        snippetStart: 'zzzz',
        snippetEnd: 'zzzz',
        category: HighlightCategory.rare,
      );
      final placed = placeHighlights([h1, h2, gone], b);
      expect(placed.map((p) => p.highlight.id), ['2', '1']);
    });

    test('the highlight under a tap: the newest covering that character', () {
      final b = book();
      final older = make('o', 0, const ReaderRange(0, 0, 0, 20), b, at: 1);
      final newer = make('n', 0, const ReaderRange(0, 5, 0, 12), b, at: 2);
      final placed = placeHighlights([older, newer], b);
      expect(highlightAt(placed, b[0], 0, 8)!.highlight.id, 'n');
      expect(highlightAt(placed, b[0], 0, 2)!.highlight.id, 'o');
      expect(highlightAt(placed, b[0], 0, 40), isNull);
      expect(highlightAt(placed, b[0], 1, 2), isNull);
    });
  });

  group('colours', () {
    test('the three categories: a medium blue, a green, a purple that glows; same in every mode', () {
      expect(HighlightCategory.good.argb, 0xFF3D7BD6);
      expect(HighlightCategory.excellent.argb, 0xFF2FA55A);
      expect(HighlightCategory.rare.argb, 0xFF9C4DFF);
      expect([for (final c in HighlightCategory.values) c.glows], [false, false, true]);
      expect([for (final c in HighlightCategory.values) c.label], ['Good', 'Excellent', 'Rare']);
      // medium blue: darker than sky blue, lighter than navy
      expect(luminance(HighlightCategory.good.argb), lessThan(luminance(0xFF87CEEB)));
      expect(luminance(HighlightCategory.good.argb), greaterThan(luminance(0xFF000080)));
      for (final c in HighlightCategory.values) {
        expect((c.tintArgb >> 24) & 0xFF, kHighlightTintAlpha, reason: 'a soft translucent tint');
        expect(c.tintArgb & 0xFFFFFF, c.argb & 0xFFFFFF);
      }
    });

    test('text keeps 4.5:1 on the page AND on every tint, in Light, Dark and Sepia, for any run colour', () {
      final runColors = <int?>[null, 0xFF000000, 0xFFFFFFFF, 0xFF000080, 0xFF00FFFF, 0xFFFFFF00, 0xFFFF0000, 0xFF808080, 0xFF9C4DFF, 0xFF3D7BD6, 0xFF2FA55A];
      for (final mode in ['light', 'dark', 'sepia']) {
        final page = backgroundFor(mode);
        for (final cats in [
          <HighlightCategory>{},
          {HighlightCategory.good},
          {HighlightCategory.excellent},
          {HighlightCategory.rare},
          {...HighlightCategory.values},
        ]) {
          for (final rc in runColors) {
            final color = readableOnHighlights(rc, mode, cats);
            expect(contrastRatio(color, page), greaterThanOrEqualTo(kReaderMinContrast), reason: '$mode page, run $rc, $cats');
            for (final c in cats) {
              expect(contrastRatio(color, compositeOver(c.tintArgb, page)), greaterThanOrEqualTo(kReaderMinContrast), reason: '$mode ${c.label} tint, run $rc');
            }
          }
        }
      }
    });
  });
}
