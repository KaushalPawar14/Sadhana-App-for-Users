import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

// Reads a book's .docx into plain data, with no Flutter in it: the reader runs
// it on a background isolate (so opening a book never freezes the screen), the
// result is cached on the device as JSON (so a reopened book opens at once),
// and the contrast check (tool/scan_book_contrast.dart) runs the very same code
// the app does.
//
// The splitting rules are exactly the reader's own: a Heading 1 paragraph opens
// a new chapter, each <w:p> is one paragraph, every run keeps its own bold,
// italic, colour and size, images stay where they were authored.

// Bump when the shape of [ParsedBook] changes, so older cached copies are
// ignored.
const int kParsedBookVersion = 1;

// Word's default text colour in the reader (Colors.black87).
const int kReaderDefaultTextArgb = 0xDD000000;

sealed class InlineItem {
  const InlineItem();
  Map<String, Object?> toJson();

  static InlineItem fromJson(Map<String, dynamic> j) => j.containsKey('img')
      ? ImageRun(j['img'] as String)
      : TextRun(
          j['t'] as String,
          bold: j['b'] == true,
          italic: j['i'] == true,
          color: j['c'] as int?,
          size: (j['s'] as num?)?.toDouble(),
        );
}

// A run of text. [color] is null when the run carried no colour of its own
// (the reader then uses its default / the theme's text colour).
class TextRun extends InlineItem {
  const TextRun(this.text,
      {this.bold = false, this.italic = false, this.color, this.size});

  final String text;
  final bool bold;
  final bool italic;
  final int? color; // ARGB
  final double? size;

  @override
  Map<String, Object?> toJson() => {
        't': text,
        if (bold) 'b': true,
        if (italic) 'i': true,
        if (color != null) 'c': color,
        if (size != null) 's': size,
      };
}

// An inline picture; its bytes are in [ParsedBook.media] under [id].
class ImageRun extends InlineItem {
  const ImageRun(this.id);
  final String id;

  @override
  Map<String, Object?> toJson() => {'img': id};
}

class ParsedBorder {
  const ParsedBorder(this.color, this.width);
  final int color; // ARGB
  final double width;

  Map<String, Object?> toJson() => {'c': color, 'w': width};
  static ParsedBorder? fromJson(Object? j) => j is Map
      ? ParsedBorder(j['c'] as int, (j['w'] as num).toDouble())
      : null;
}

// Shading, borders and alignment of a (heading) paragraph.
class ParsedDecoration {
  const ParsedDecoration({
    this.fill,
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.centered = false,
  });

  final int? fill; // ARGB
  final ParsedBorder? top;
  final ParsedBorder? bottom;
  final ParsedBorder? left;
  final ParsedBorder? right;
  final bool centered;

  bool get isEmpty =>
      fill == null &&
      top == null &&
      bottom == null &&
      left == null &&
      right == null;

  Map<String, Object?> toJson() => {
        if (fill != null) 'f': fill,
        if (top != null) 'bt': top!.toJson(),
        if (bottom != null) 'bb': bottom!.toJson(),
        if (left != null) 'bl': left!.toJson(),
        if (right != null) 'br': right!.toJson(),
        if (centered) 'ce': true,
      };

  static ParsedDecoration? fromJson(Object? j) => j is Map
      ? ParsedDecoration(
          fill: j['f'] as int?,
          top: ParsedBorder.fromJson(j['bt']),
          bottom: ParsedBorder.fromJson(j['bb']),
          left: ParsedBorder.fromJson(j['bl']),
          right: ParsedBorder.fromJson(j['br']),
          centered: j['ce'] == true,
        )
      : null;
}

class ParsedChapter {
  const ParsedChapter({
    required this.title,
    required this.paragraphs,
    this.titleRuns = const [],
    this.titleDecoration,
  });

  final String title;
  final List<InlineItem> titleRuns;
  final ParsedDecoration? titleDecoration;
  final List<List<InlineItem>> paragraphs;

  Map<String, Object?> toJson() => {
        'title': title,
        'tr': [for (final r in titleRuns) r.toJson()],
        if (titleDecoration != null) 'td': titleDecoration!.toJson(),
        'p': [
          for (final p in paragraphs) [for (final r in p) r.toJson()]
        ],
      };

  static ParsedChapter fromJson(Map<String, dynamic> j) => ParsedChapter(
        title: j['title'] as String,
        titleRuns: [
          for (final r in (j['tr'] as List)) InlineItem.fromJson(r as Map<String, dynamic>)
        ],
        titleDecoration: ParsedDecoration.fromJson(j['td']),
        paragraphs: [
          for (final p in (j['p'] as List))
            [for (final r in (p as List)) InlineItem.fromJson(r as Map<String, dynamic>)]
        ],
      );
}

class ParsedBook {
  const ParsedBook(this.chapters, this.media);

  final List<ParsedChapter> chapters;

  // Relationship id -> image bytes. Empty for nearly every book.
  final Map<String, Uint8List> media;

  Map<String, Object?> toJson() => {
        'v': kParsedBookVersion,
        'chapters': [for (final c in chapters) c.toJson()],
        if (media.isNotEmpty)
          'media': {for (final e in media.entries) e.key: base64Encode(e.value)},
      };

  static ParsedBook fromJson(Map<String, dynamic> j) {
    if (j['v'] != kParsedBookVersion) {
      throw const FormatException('parsed book version mismatch');
    }
    final media = <String, Uint8List>{};
    final m = j['media'];
    if (m is Map) {
      for (final e in m.entries) {
        media[e.key as String] = base64Decode(e.value as String);
      }
    }
    return ParsedBook([
      for (final c in (j['chapters'] as List)) ParsedChapter.fromJson(c as Map<String, dynamic>)
    ], media);
  }

  String encode() => jsonEncode(toJson());
  static ParsedBook decode(String source) =>
      fromJson(jsonDecode(source) as Map<String, dynamic>);
}

// Unzips the DOCX and splits `word/document.xml` into chapters.
//
// [onFirstChapter] is called as soon as the first chapter is complete (when the
// second Heading 1 is met), so a caller can show it before the rest is read.
ParsedBook parseDocx(
  Uint8List bytes, {
  required String fallbackTitle,
  void Function(ParsedChapter first, Map<String, Uint8List> media)?
      onFirstChapter,
}) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final entry = archive.files.firstWhere(
    (f) => f.name == 'word/document.xml',
    orElse: () => throw const FormatException('word/document.xml not found'),
  );

  // document.xml is UTF-8. Decoding byte-by-byte would split multi-byte
  // sequences and turn IAST diacritics into mojibake.
  final xmlString = utf8.decode(entry.content as List<int>, allowMalformed: true);
  final document = XmlDocument.parse(xmlString);

  final media = _buildMediaMap(archive);

  final chapters = <ParsedChapter>[];
  var currentTitle = fallbackTitle;
  var currentTitleRuns = <InlineItem>[];
  ParsedDecoration? currentTitleDecoration;
  var currentParagraphs = <List<InlineItem>>[];

  void close() {
    final chapter = ParsedChapter(
      title: currentTitle,
      titleRuns: List<InlineItem>.from(currentTitleRuns),
      titleDecoration: currentTitleDecoration,
      paragraphs: List<List<InlineItem>>.from(currentParagraphs),
    );
    chapters.add(chapter);
    if (chapters.length == 1) onFirstChapter?.call(chapter, media);
  }

  for (final p in document.findAllElements('p', namespace: '*')) {
    String? styleVal;
    for (final style in p.findAllElements('pStyle', namespace: '*')) {
      styleVal = style.getAttribute('val', namespace: '*') ??
          style.getAttribute('w:val');
      break;
    }

    final isHeading1 = styleVal != null &&
        styleVal.replaceAll(' ', '').toLowerCase() == 'heading1';

    final runs = _extractRuns(p, media);
    final plain = runsToPlainText(runs).trim();

    if (isHeading1) {
      // The page-break / "Next Chapter" boundary: unchanged.
      if (currentParagraphs.isNotEmpty) {
        close();
        currentParagraphs = <List<InlineItem>>[];
      }
      currentTitle = plain.isEmpty ? 'Untitled chapter' : plain;
      currentTitleRuns = runs;
      currentTitleDecoration = _readParagraphDecoration(p);
    } else if (plain.isNotEmpty || runs.any((r) => r is ImageRun)) {
      currentParagraphs.add(runs);
    }
  }

  if (currentParagraphs.isNotEmpty) close();

  // A document with no Heading 1 styles still reads as one chapter.
  if (chapters.isEmpty) {
    chapters.add(ParsedChapter(title: fallbackTitle, paragraphs: const []));
  }

  // Only pictures that are actually used.
  return ParsedBook(chapters, media);
}

String runsToPlainText(List<InlineItem> runs) =>
    runs.map((r) => r is TextRun ? r.text : '').join();

Map<String, Uint8List> _buildMediaMap(Archive archive) {
  final out = <String, Uint8List>{};

  ArchiveFile? relsEntry;
  for (final f in archive.files) {
    if (f.name == 'word/_rels/document.xml.rels') {
      relsEntry = f;
      break;
    }
  }
  if (relsEntry == null) return out;

  final byPath = <String, Uint8List>{};
  for (final f in archive.files) {
    if (f.name.startsWith('word/media/')) {
      byPath[f.name] = Uint8List.fromList(f.content as List<int>);
    }
  }
  if (byPath.isEmpty) return out;

  try {
    final rels = XmlDocument.parse(
      utf8.decode(relsEntry.content as List<int>, allowMalformed: true),
    );

    for (final rel in rels.findAllElements('Relationship', namespace: '*')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null) continue;

      final clean =
          target.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
      final candidates = <String>[
        'word/$clean',
        clean,
        'word/${clean.split('/').last}',
        'word/media/${clean.split('/').last}',
      ];

      for (final c in candidates) {
        final bytes = byPath[c];
        if (bytes != null) {
          out[id] = bytes;
          break;
        }
      }
    }
  } catch (_) {
    // A malformed relationships part only means images cannot be resolved.
  }

  return out;
}

ParsedDecoration? _readParagraphDecoration(XmlElement paragraph) {
  XmlElement? pPr;
  for (final e in paragraph.findElements('pPr', namespace: '*')) {
    pPr = e;
    break;
  }
  if (pPr == null) return null;

  int? fill;
  for (final shd in pPr.findElements('shd', namespace: '*')) {
    final val =
        shd.getAttribute('fill', namespace: '*') ?? shd.getAttribute('w:fill');
    final parsed = _hexColor(val);
    if (parsed != null) fill = parsed;
    break;
  }

  ParsedBorder? side(XmlElement pBdr, String name) {
    for (final b in pBdr.findElements(name, namespace: '*')) {
      final style = (b.getAttribute('val', namespace: '*') ??
              b.getAttribute('w:val') ??
              '')
          .toLowerCase();
      if (style == 'none' || style == 'nil') return null;

      final colour = _hexColor(b.getAttribute('color', namespace: '*') ??
              b.getAttribute('w:color')) ??
          kReaderDefaultTextArgb;

      // w:sz on a border is in EIGHTHS of a point.
      final szRaw =
          b.getAttribute('sz', namespace: '*') ?? b.getAttribute('w:sz');
      final eighths = int.tryParse(szRaw ?? '') ?? 8;
      final width = (eighths / 8.0).clamp(0.5, 12.0).toDouble();

      return ParsedBorder(colour, width);
    }
    return null;
  }

  ParsedBorder? top, bottom, left, right;
  for (final pBdr in pPr.findElements('pBdr', namespace: '*')) {
    top = side(pBdr, 'top');
    bottom = side(pBdr, 'bottom');
    left = side(pBdr, 'left');
    right = side(pBdr, 'right');
    break;
  }

  var centered = false;
  for (final jc in pPr.findElements('jc', namespace: '*')) {
    final val =
        jc.getAttribute('val', namespace: '*') ?? jc.getAttribute('w:val');
    centered = (val ?? '').toLowerCase() == 'center';
    break;
  }

  final decoration = ParsedDecoration(
    fill: fill,
    top: top,
    bottom: bottom,
    left: left,
    right: right,
    centered: centered,
  );

  if (decoration.isEmpty && !centered) return null;
  return decoration;
}

// A Word `RRGGBB` hex value as opaque ARGB; null for "auto" or malformed.
int? _hexColor(String? value) {
  if (value == null) return null;
  final v = value.trim().replaceAll('#', '');
  if (v.isEmpty || v.toLowerCase() == 'auto') return null;
  if (v.length != 6) return null;
  final parsed = int.tryParse(v, radix: 16);
  if (parsed == null) return null;
  return 0xFF000000 | parsed;
}

// One <w:p> as runs. Every property is read per run, never inherited from the
// run before it.
List<InlineItem> _extractRuns(XmlElement paragraph, Map<String, Uint8List> media) {
  final out = <InlineItem>[];

  for (final run in paragraph.findAllElements('r', namespace: '*')) {
    var bold = false;
    var italic = false;
    int? colour;
    double? fontSize;

    for (final rPr in run.findElements('rPr', namespace: '*')) {
      bold = _isToggleOn(rPr, 'b');
      italic = _isToggleOn(rPr, 'i');

      for (final c in rPr.findElements('color', namespace: '*')) {
        colour = _hexColor(
            c.getAttribute('val', namespace: '*') ?? c.getAttribute('w:val'));
        break;
      }

      for (final sz in rPr.findElements('sz', namespace: '*')) {
        final raw =
            sz.getAttribute('val', namespace: '*') ?? sz.getAttribute('w:sz');
        final halfPoints = int.tryParse(raw ?? '');
        if (halfPoints != null && halfPoints > 0) {
          // w:sz on a run is HALF-points; clamped so a stray value cannot blow
          // the layout apart.
          fontSize = (halfPoints / 2.0).clamp(8.0, 40.0).toDouble();
        }
        break;
      }
      break;
    }

    TextRun text(String s) => TextRun(s,
        bold: bold, italic: italic, color: colour, size: fontSize);

    for (final node in run.children.whereType<XmlElement>()) {
      switch (node.name.local) {
        case 't':
          if (node.innerText.isNotEmpty) out.add(text(node.innerText));
          break;
        case 'br':
          out.add(text('\n'));
          break;
        case 'tab':
          out.add(text('\t'));
          break;
        case 'drawing':
        case 'pict':
        case 'AlternateContent':
          final image = _imageRunFrom(node, media);
          if (image != null) out.add(image);
          break;
      }
    }
  }

  return out;
}

// Modern DrawingML (<a:blip r:embed>) first, then legacy VML
// (<v:imagedata r:id>); returns on the first id that resolves.
ImageRun? _imageRunFrom(XmlElement source, Map<String, Uint8List> media) {
  for (final blip in source.findAllElements('blip', namespace: '*')) {
    final id = blip.getAttribute('embed', namespace: '*') ??
        blip.getAttribute('r:embed');
    if (id != null && media.containsKey(id)) return ImageRun(id);
  }
  for (final data in source.findAllElements('imagedata', namespace: '*')) {
    final id =
        data.getAttribute('id', namespace: '*') ?? data.getAttribute('r:id');
    if (id != null && media.containsKey(id)) return ImageRun(id);
  }
  return null;
}

bool _isToggleOn(XmlElement runProperties, String tag) {
  for (final el in runProperties.findElements(tag, namespace: '*')) {
    final val =
        el.getAttribute('val', namespace: '*') ?? el.getAttribute('w:val');
    if (val == null) return true;
    final normalized = val.toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'on';
  }
  return false;
}
