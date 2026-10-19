import 'dart:math' as math;

import 'BookDocParser.dart';
import 'ReaderContrast.dart';

// Highlights & notes in the book reader: the plain rules, kept out of the screen so they can be tested alone.
//
// A highlight is a portion of a chapter (any length, inside a paragraph or across paragraphs) with a category
// (GOOD, EXCELLENT, RARE) and an optional note. It is private to the student.
//
// ANCHORING. Every highlight is stored with its position (chapter, start paragraph + character offset, end
// paragraph + character offset) AND the selected text itself. The position draws it instantly; the text lets it
// find its place again if the book file is replaced (paragraphs added, chapters moved). If the text is gone it
// is kept but not drawn (see [resolveAnchor]); nothing ever crashes over a missing highlight.
//
// The character offsets are in the paragraph as the reader draws it: its text runs in order, each picture
// counting as one placeholder character ([kImageChar]) - the same space `RenderParagraph` uses.

/// What a picture inside a paragraph counts as in the offsets.
const String kImageChar = '￼';

/// The text of a paragraph in the offset space of the reader (pictures are one placeholder character).
String renderedParagraphText(List<InlineItem> runs) =>
    runs.map((r) => r is TextRun ? r.text : kImageChar).join();

enum HighlightCategory { good, excellent, rare }

extension HighlightCategoryX on HighlightCategory {
  String get key => name;

  String get label {
    switch (this) {
      case HighlightCategory.good:
        return 'Good';
      case HighlightCategory.excellent:
        return 'Excellent';
      case HighlightCategory.rare:
        return 'Rare';
    }
  }

  /// A medium blue (between sky and dark), a green, and a purple that glows. The same in Light, Dark and Sepia.
  int get argb {
    switch (this) {
      case HighlightCategory.good:
        return 0xFF3D7BD6;
      case HighlightCategory.excellent:
        return 0xFF2FA55A;
      case HighlightCategory.rare:
        return 0xFF9C4DFF;
    }
  }

  /// RARE glows softly.
  bool get glows => this == HighlightCategory.rare;

  /// The soft translucent tint inside the border.
  int get tintArgb => (argb & 0x00FFFFFF) | (kHighlightTintAlpha << 24);

  static HighlightCategory? fromKey(Object? key) {
    for (final c in HighlightCategory.values) {
      if (c.name == key) return c;
    }
    return null;
  }
}

/// Alpha (0-255) of the tint inside a highlight: light enough that the text keeps its contrast.
const int kHighlightTintAlpha = 0x33;

/// The text colour for a run inside a paragraph that carries highlights of [categories]: the run's own colour
/// when it reaches 4.5:1 on the page AND on every tint it may sit on; otherwise the first of the mode's
/// text colours that does (the same contrast rule as the rest of the reader).
int readableOnHighlights(int? runColor, String mode, Iterable<HighlightCategory> categories) {
  final page = backgroundFor(mode);
  final backgrounds = <int>[page, for (final c in categories.toSet()) compositeOver(c.tintArgb, page)];
  bool ok(int color) => backgrounds.every((b) => contrastRatio(color, b) >= kReaderMinContrast);
  final candidates = <int>[
    for (final b in backgrounds) readableColor(runColor, mode: mode, background: b),
    kReaderModeColors[mode]!.text,
    kReaderModeColors[mode]!.onChrome,
  ];
  for (final c in candidates) {
    if (ok(c)) return c;
  }
  final worst = backgrounds.reduce((a, b) => luminance(a) < luminance(b) ? a : b);
  return contrastRatio(kBlackArgb, worst) >= contrastRatio(kWhiteArgb, worst) ? kBlackArgb : kWhiteArgb;
}

// ---------------------------------------------------------------------------------------------------------
// ranges and anchors
// ---------------------------------------------------------------------------------------------------------

/// A portion of ONE chapter: from (start paragraph, offset) to (end paragraph, offset), end exclusive.
/// Always normalised: start before end.
class ReaderRange {
  const ReaderRange(this.startPara, this.startOffset, this.endPara, this.endOffset);

  final int startPara;
  final int startOffset;
  final int endPara;
  final int endOffset;

  bool get isEmpty => startPara == endPara && startOffset >= endOffset;

  @override
  bool operator ==(Object other) =>
      other is ReaderRange &&
      other.startPara == startPara &&
      other.startOffset == startOffset &&
      other.endPara == endPara &&
      other.endOffset == endOffset;

  @override
  int get hashCode => Object.hash(startPara, startOffset, endPara, endOffset);

  @override
  String toString() => 'ReaderRange($startPara:$startOffset - $endPara:$endOffset)';

  /// The two points in order, whichever was given first.
  factory ReaderRange.ordered(int paraA, int offA, int paraB, int offB) {
    final aFirst = paraA < paraB || (paraA == paraB && offA <= offB);
    return aFirst ? ReaderRange(paraA, offA, paraB, offB) : ReaderRange(paraB, offB, paraA, offA);
  }
}

/// The part of one paragraph a range covers.
class ParagraphSegment {
  const ParagraphSegment(this.paragraph, this.start, this.end);

  final int paragraph;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is ParagraphSegment && other.paragraph == paragraph && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(paragraph, start, end);

  @override
  String toString() => 'Segment($paragraph: $start-$end)';
}

/// A range split per paragraph: the first from its offset to its end, those between whole, the last from its
/// start to its offset. A paragraph the range barely touches (an empty part) is left out.
List<ParagraphSegment> segmentsOf(ReaderRange r, List<String> paragraphs) {
  final out = <ParagraphSegment>[];
  for (var p = r.startPara; p <= r.endPara && p < paragraphs.length; p++) {
    if (p < 0) continue;
    final len = paragraphs[p].length;
    final s = p == r.startPara ? r.startOffset.clamp(0, len) : 0;
    final e = p == r.endPara ? r.endOffset.clamp(0, len) : len;
    if (e > s) out.add(ParagraphSegment(p, s, e));
  }
  return out;
}

/// The text a range covers, paragraphs joined by a line break.
String textOfRange(ReaderRange r, List<String> paragraphs) =>
    segmentsOf(r, paragraphs).map((s) => paragraphs[s.paragraph].substring(s.start, s.end)).join('\n');

/// The whole paragraph(s) a range touches.
ReaderRange wholeParagraphs(ReaderRange r, List<String> paragraphs) {
  final last = math.max(0, math.min(r.endPara, paragraphs.length - 1));
  return ReaderRange(r.startPara, 0, last, paragraphs.isEmpty ? 0 : paragraphs[last].length);
}

/// The sentence around [offset] in [paragraph]: from after the previous sentence end to the next one (a full
/// stop, ?, !, or the Devanagari danda, followed by a space or the end).
({int start, int end}) sentenceAround(String paragraph, int offset) {
  if (paragraph.isEmpty) return (start: 0, end: 0);
  final at = offset.clamp(0, paragraph.length);
  bool endsSentence(int i) {
    final c = paragraph[i];
    if (c != '.' && c != '?' && c != '!' && c != '।' && c != '॥') return false;
    return i + 1 >= paragraph.length || paragraph[i + 1] == ' ' || paragraph[i + 1] == '\n' || paragraph[i + 1] == '"' || paragraph[i + 1] == '”';
  }

  var start = 0;
  for (var i = at - 1; i >= 0; i--) {
    if (endsSentence(i)) {
      start = i + 1;
      break;
    }
  }
  var end = paragraph.length;
  for (var i = math.max(at, start); i < paragraph.length; i++) {
    if (endsSentence(i)) {
      end = i + 1;
      // include a closing quote
      if (end < paragraph.length && (paragraph[end] == '"' || paragraph[end] == '”')) end++;
      break;
    }
  }
  while (start < end && (paragraph[start] == ' ' || paragraph[start] == '\n')) {
    start++;
  }
  return (start: start, end: end);
}

// ---------------------------------------------------------------------------------------------------------
// the highlight
// ---------------------------------------------------------------------------------------------------------

/// Where a highlight sits: its chapter and range.
class HighlightAnchor {
  const HighlightAnchor(this.chapter, this.range);

  final int chapter;
  final ReaderRange range;

  @override
  bool operator ==(Object other) => other is HighlightAnchor && other.chapter == chapter && other.range == range;

  @override
  int get hashCode => Object.hash(chapter, range);

  @override
  String toString() => 'Anchor(ch $chapter ${range.toString()})';
}

/// The most of the selected text kept whole; longer selections keep their start and end.
const int kHighlightTextCap = 2000;
const int kSnippetLength = 120;

class BookHighlight {
  const BookHighlight({
    required this.id,
    required this.anchor,
    required this.text,
    required this.textLength,
    required this.snippetStart,
    required this.snippetEnd,
    required this.category,
    this.note = '',
    this.createdMillis = 0,
  });

  final String id;
  final HighlightAnchor anchor;

  /// The selected text (up to [kHighlightTextCap] characters).
  final String text;

  /// The full length of the selected text (more than `text.length` when it was cut).
  final int textLength;

  /// The first and last characters of the selected text: they find the place again in a replaced book.
  final String snippetStart;
  final String snippetEnd;
  final HighlightCategory category;
  final String note;
  final int createdMillis;

  bool get truncated => textLength > text.length;

  BookHighlight copyWith({HighlightAnchor? anchor, String? text, int? textLength, String? snippetStart, String? snippetEnd, HighlightCategory? category, String? note}) =>
      BookHighlight(
        id: id,
        anchor: anchor ?? this.anchor,
        text: text ?? this.text,
        textLength: textLength ?? this.textLength,
        snippetStart: snippetStart ?? this.snippetStart,
        snippetEnd: snippetEnd ?? this.snippetEnd,
        category: category ?? this.category,
        note: note ?? this.note,
        createdMillis: createdMillis,
      );

  /// A new highlight for [range] of [chapter], reading its text from [paragraphs].
  static BookHighlight create({
    required String id,
    required int chapter,
    required ReaderRange range,
    required List<String> paragraphs,
    required HighlightCategory category,
    String note = '',
    int createdMillis = 0,
  }) {
    final text = textOfRange(range, paragraphs);
    return BookHighlight(
      id: id,
      anchor: HighlightAnchor(chapter, range),
      text: text.length > kHighlightTextCap ? text.substring(0, kHighlightTextCap) : text,
      textLength: text.length,
      snippetStart: text.substring(0, math.min(kSnippetLength, text.length)),
      snippetEnd: text.substring(math.max(0, text.length - kSnippetLength)),
      category: category,
      note: note,
      createdMillis: createdMillis,
    );
  }

  /// The anchor and text fields as stored (the document also carries uid, book and level; see the store).
  Map<String, Object?> toFields() => {
        'chapterIndex': anchor.chapter,
        'startParagraph': anchor.range.startPara,
        'startOffset': anchor.range.startOffset,
        'endParagraph': anchor.range.endPara,
        'endOffset': anchor.range.endOffset,
        'text': text,
        'textLength': textLength,
        'snippetStart': snippetStart,
        'snippetEnd': snippetEnd,
        'category': category.key,
        'note': note,
      };

  /// Reads a stored document; null when it is too damaged to mean anything (it is then simply not shown).
  static BookHighlight? fromFields(String id, Map<String, dynamic> d, {int createdMillis = 0}) {
    int? i(Object? v) => v is num ? v.toInt() : null;
    final category = HighlightCategoryX.fromKey(d['category']);
    final chapter = i(d['chapterIndex']);
    final sp = i(d['startParagraph']);
    final so = i(d['startOffset']);
    final ep = i(d['endParagraph']);
    final eo = i(d['endOffset']);
    final text = (d['text'] ?? '').toString();
    if (category == null || chapter == null || sp == null || so == null || ep == null || eo == null) return null;
    return BookHighlight(
      id: id,
      anchor: HighlightAnchor(chapter, ReaderRange.ordered(sp, so, ep, eo)),
      text: text,
      textLength: i(d['textLength']) ?? text.length,
      snippetStart: (d['snippetStart'] ?? (text.length > kSnippetLength ? text.substring(0, kSnippetLength) : text)).toString(),
      snippetEnd: (d['snippetEnd'] ?? (text.length > kSnippetLength ? text.substring(text.length - kSnippetLength) : text)).toString(),
      category: category,
      note: (d['note'] ?? '').toString(),
      createdMillis: createdMillis,
    );
  }
}

// ---------------------------------------------------------------------------------------------------------
// finding a highlight again
// ---------------------------------------------------------------------------------------------------------

/// Does [h] still sit exactly where it was stored, with the same text? ([book] is every chapter's paragraphs.)
bool anchorHolds(BookHighlight h, List<List<String>> book) {
  final a = h.anchor;
  if (a.chapter < 0 || a.chapter >= book.length) return false;
  final paras = book[a.chapter];
  final r = a.range;
  if (r.startPara < 0 || r.endPara >= paras.length || r.isEmpty) return false;
  if (r.startOffset < 0 || r.startOffset > paras[r.startPara].length) return false;
  if (r.endOffset < 0 || r.endOffset > paras[r.endPara].length) return false;
  final now = textOfRange(r, paras);
  if (!h.truncated) return now == h.text;
  return now.length == h.textLength && now.startsWith(h.snippetStart) && now.endsWith(h.snippetEnd);
}

/// One chapter as a single string (paragraphs joined by a line break) and where each paragraph starts in it.
class _Flat {
  _Flat(List<String> paragraphs) {
    final b = StringBuffer();
    for (var i = 0; i < paragraphs.length; i++) {
      starts.add(b.length);
      b.write(paragraphs[i]);
      if (i < paragraphs.length - 1) b.write('\n');
    }
    text = b.toString();
  }

  late final String text;
  final List<int> starts = [];

  ({int para, int offset}) position(int index) {
    var lo = 0;
    var hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (starts[mid] <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (para: lo, offset: index - starts[lo]);
  }
}

List<int> _occurrences(String hay, String needle) {
  final out = <int>[];
  if (needle.isEmpty) return out;
  var from = 0;
  while (true) {
    final i = hay.indexOf(needle, from);
    if (i < 0) break;
    out.add(i);
    from = i + 1;
  }
  return out;
}

/// Finds [h] in one chapter by its text, nearest to its old paragraph.
ReaderRange? _findInChapter(BookHighlight h, List<String> paragraphs) {
  if (paragraphs.isEmpty) return null;
  final flat = _Flat(paragraphs);
  final oldPara = h.anchor.range.startPara.clamp(0, paragraphs.length - 1);
  final oldIndex = flat.starts[oldPara] + h.anchor.range.startOffset;
  int distance(int i) => (i - oldIndex).abs();

  int? bestStart;
  int? bestEnd;
  if (!h.truncated) {
    for (final i in _occurrences(flat.text, h.text)) {
      if (bestStart == null || distance(i) < distance(bestStart)) {
        bestStart = i;
        bestEnd = i + h.text.length;
      }
    }
  } else {
    for (final i in _occurrences(flat.text, h.snippetStart)) {
      final endAt = flat.text.indexOf(h.snippetEnd, i + math.max(0, h.textLength - h.snippetEnd.length - 1));
      if (endAt < 0) continue;
      if (bestStart == null || distance(i) < distance(bestStart)) {
        bestStart = i;
        bestEnd = endAt + h.snippetEnd.length;
      }
    }
  }
  if (bestStart == null || bestEnd == null || bestEnd <= bestStart) return null;
  final s = flat.position(bestStart);
  final e = flat.position(bestEnd);
  // an end that lands on the break between two paragraphs is the end of the earlier one
  var endPara = e.para;
  var endOffset = e.offset;
  if (endOffset == 0 && endPara > s.para) {
    endPara--;
    endOffset = paragraphs[endPara].length;
  }
  return ReaderRange(s.para, s.offset, endPara, endOffset);
}

/// Where [h] is NOW: where it was stored if the text is still there; otherwise wherever its text is (same chapter
/// first, then the nearest chapters) - which is how a highlight survives a replaced book file. Null when the text
/// cannot be found: the highlight is kept (never deleted) and simply not drawn.
HighlightAnchor? resolveAnchor(BookHighlight h, List<List<String>> book) {
  if (h.text.isEmpty && h.snippetStart.isEmpty) return null;
  if (anchorHolds(h, book)) return h.anchor;
  final order = <int>[
    for (var c = 0; c < book.length; c++) c,
  ]..sort((a, b) => (a - h.anchor.chapter).abs().compareTo((b - h.anchor.chapter).abs()));
  for (final c in order) {
    final r = _findInChapter(h, book[c]);
    if (r != null) return HighlightAnchor(c, r);
  }
  return null;
}

/// The highlights of a chapter, with where each sits now, oldest first (so the newest is drawn last).
class PlacedHighlight {
  const PlacedHighlight(this.highlight, this.anchor);

  final BookHighlight highlight;
  final HighlightAnchor anchor;
}

List<PlacedHighlight> placeHighlights(List<BookHighlight> all, List<List<String>> book) {
  final out = <PlacedHighlight>[];
  for (final h in all) {
    final a = resolveAnchor(h, book);
    if (a != null) out.add(PlacedHighlight(h, a));
  }
  out.sort((a, b) => a.highlight.createdMillis.compareTo(b.highlight.createdMillis));
  return out;
}

/// The highlight under a tap at [offset] in [paragraph] of the chapter: the newest one covering that character.
PlacedHighlight? highlightAt(List<PlacedHighlight> inChapter, List<String> paragraphs, int paragraph, int offset) {
  PlacedHighlight? hit;
  for (final p in inChapter) {
    for (final s in segmentsOf(p.anchor.range, paragraphs)) {
      if (s.paragraph == paragraph && offset >= s.start && offset < s.end) hit = p;
    }
  }
  return hit;
}
