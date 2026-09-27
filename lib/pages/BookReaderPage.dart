import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:xml/xml.dart';


/// Paragraph-level decoration read from `<w:pPr>`.
///
/// Covers the shaded/bordered banner styling Word applies to headings:
/// `<w:shd w:fill="RRGGBB"/>` for the fill, `<w:pBdr>` for per-side rules, and
/// `<w:jc w:val="center"/>` for alignment.
///
/// Verified against the real library: every Heading 1 in
/// *Beyond Birth and Death* carries `fill="008080"` (teal) with 3pt
/// `800000` (maroon) top and bottom borders.
class ParagraphDecoration {
  final Color? fill;
  final BorderSide? top;
  final BorderSide? bottom;
  final BorderSide? left;
  final BorderSide? right;
  final bool centered;

  const ParagraphDecoration({
    this.fill,
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.centered = false,
  });

  bool get isEmpty =>
      fill == null &&
      top == null &&
      bottom == null &&
      left == null &&
      right == null;

  Border? get border {
    if (top == null && bottom == null && left == null && right == null) {
      return null;
    }
    return Border(
      top: top ?? BorderSide.none,
      bottom: bottom ?? BorderSide.none,
      left: left ?? BorderSide.none,
      right: right ?? BorderSide.none,
    );
  }
}

/// A single chapter, delimited by a Heading 1 paragraph in the DOCX.
///
/// Each paragraph is a list of [InlineSpan]s rather than a plain string, so
/// bold/italic/coloured runs, in-paragraph line breaks **and inline images**
/// survive parsing.
///
/// ⚠️ `InlineSpan`, not `TextSpan` (widened 2026-08-19): an embedded image
/// renders as a [WidgetSpan], which is an `InlineSpan` but not a `TextSpan`.
/// Keeping the narrower type would have forced images out of the run sequence
/// and into separate blocks, losing their authored position.
class BookChapter {
  final String title;

  /// The heading's own formatted runs. Empty for a synthetic chapter (a
  /// document with no Heading 1, or the text before the first one), in which
  /// case [title] is rendered as plain text exactly as before.
  final List<InlineSpan> titleSpans;

  /// Shading/border/alignment for the heading, when Word authored any.
  final ParagraphDecoration? titleDecoration;

  final List<List<InlineSpan>> paragraphs;

  const BookChapter({
    required this.title,
    required this.paragraphs,
    this.titleSpans = const [],
    this.titleDecoration,
  });
}

/// Base style shared by every run of body text.
const TextStyle kReaderParagraphStyle = TextStyle(
  // Device serif face: full Unicode coverage for IAST diacritics.
  fontFamily: 'serif',
  fontSize: 16,
  height: 1.6,
  color: Colors.black87,
);

/// Flattens formatted spans back to plain text (bookmark previews, headings).
///
/// A [WidgetSpan] (an inline image) contributes nothing, so an image never
/// corrupts a bookmark preview or a chapter title.
String spansToPlainText(List<InlineSpan> spans) => spans
    .map((s) => s is TextSpan ? (s.text ?? '') : '')
    .join();

/// Reader background/text colours for one reading theme.
///
/// Sepia is a genuine warm-paper palette, not an inverted default: `F4ECD8`
/// is a low-blue-light parchment tone (the same family Kindle/iBooks use for
/// their "sepia" mode), paired with a dark warm brown — not black — so
/// contrast stays comfortable (~8:1) without the harsher black-on-tan glare
/// pure black text would give on a warm background.
class ReaderPalette {
  final Color background;
  final Color text;
  final Color secondaryText;
  final Color chrome;
  final Color onChrome;

  const ReaderPalette({
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.chrome,
    required this.onChrome,
  });
}

const Map<String, ReaderPalette> kReaderPalettes = {
  'light': ReaderPalette(
    background: Colors.white,
    text: Color(0xFF1D1D1D),
    secondaryText: Colors.black54,
    chrome: Colors.white,
    onChrome: Colors.black87,
  ),
  // Material's own dark surface (0xFF121212), text lifted to E0E0E0 rather
  // than pure white — full-white-on-near-black is the "inverted default"
  // this reader deliberately avoids; it is harsher on the eyes than a
  // slightly dimmed foreground for sustained reading.
  'dark': ReaderPalette(
    background: Color(0xFF121212),
    text: Color(0xFFE0E0E0),
    secondaryText: Colors.white60,
    chrome: Color(0xFF1E1E1E),
    onChrome: Color(0xFFE0E0E0),
  ),
  'sepia': ReaderPalette(
    background: Color(0xFFF4ECD8),
    text: Color(0xFF4B3621),
    secondaryText: Color(0xFF7A6650),
    chrome: Color(0xFFF4ECD8),
    onChrome: Color(0xFF4B3621),
  ),
};

const List<double> kReaderFontScaleSteps = [0.85, 1.0, 1.15, 1.3, 1.45, 1.6];

/// In-app DOCX reader.
///
/// Downloads (and caches) the .docx from [dropboxUrl], unzips it, reads
/// `word/document.xml`, and splits the document into chapters on Heading 1
/// paragraphs. Reading time is measured only while readable content is on
/// screen and is returned to the caller via `Navigator.pop(elapsedSeconds)`.
class BookReaderPage extends StatefulWidget {
  final String dropboxUrl;
  final String bookTitle;
  final String bookKey;
  final String level;
  final String uid;

  /// RDUA Modules reuse this entire reader unmodified (Rule 1) — DOCX
  /// parsing, chapter split, bookmarks, font/theme prefs are all identical
  /// regardless of content type and need no awareness of this flag at all.
  /// The ONLY place this matters is completion tracking: a book's finish
  /// state belongs in `booksRead` with its existing schema
  /// (endDate/finishedViaButton/isCurrentBook); an RDUA chapter's belongs in
  /// the separate `rduaProgress` collection with its own simpler schema
  /// (isRead/readAt) — these must never cross-contaminate each other's
  /// tracking, so which one this instance writes to is explicit here rather
  /// than inferred.
  final bool isRdua;

  const BookReaderPage({
    super.key,
    required this.dropboxUrl,
    required this.bookTitle,
    required this.bookKey,
    required this.level,
    required this.uid,
    this.isRdua = false,
  });

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  List<BookChapter> _chapters = [];
  int _currentChapter = 0;

  /// Relationship id -> image bytes for the open document. Populated by
  /// [_buildMediaMap] during parsing; empty when the book has no images.
  Map<String, Uint8List> _media = const {};

  bool _loading = true;
  String? _error;

  /// Persisted bookmark position, if any.
  int? _bookmarkChapter;
  int? _bookmarkParagraph;

  /// True while the reader is waiting for the user to pick a paragraph.
  bool _selectionMode = false;

  /// One key per paragraph of the chapter on screen, used to scroll a
  /// bookmarked paragraph into view. Rebuilt whenever the chapter changes.
  List<GlobalKey> _paragraphKeys = [];

  /// Set once parsing finishes and content becomes visible.
  DateTime? _readingStartedAt;

  /// Reading preferences (Part 3/4 of the Book Reader redesign). Device
  /// setting, but the source of truth is `users/{uid}.readingPrefs` — the
  /// same nested-map location `notificationPrefs` already uses on this
  /// document, so a student sees the same font/theme choice on any device
  /// they sign into, and a book reopened elsewhere isn't stuck on a stale
  /// default.
  String _theme = 'light';
  double _fontScale = 1.0;

  ReaderPalette get _palette => kReaderPalettes[_theme] ?? kReaderPalettes['light']!;

  /// True once this content's completion doc (`booksRead` for a book,
  /// `rduaProgress` for an RDUA chapter — see [BookReaderPage.isRdua])
  /// already marks it finished/read — loaded once so the Finish/Mark-read
  /// button doesn't re-fire for content already completed in an earlier
  /// session.
  bool _finished = false;
  bool _finishing = false;

  String get _bookmarkDocId => '${widget.uid}_${widget.bookKey}';

  /// `booksRead/{uid}_{level}_{bookKey}` for a book, or
  /// `rduaProgress/{uid}_{topicId}_{chapterNum}` for an RDUA chapter — same
  /// composition, `level`/`bookKey` simply carry `topicId`/`chapterNum` in
  /// the RDUA case (see the RDUA screen's call site).
  String get _progressDocId =>
      '${widget.uid}_${widget.level}_${widget.bookKey}';

  bool get _hasBookmark =>
      _bookmarkChapter != null && _bookmarkParagraph != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading & parsing
  // ---------------------------------------------------------------------------

  /// Dropbox share links serve an HTML preview page unless the download flag is
  /// set, which would make the archive decode fail.
  String _normalizeDropboxUrl(String url) {
    final trimmed = url.trim();
    if (!trimmed.contains('dropbox.com')) return trimmed;

    if (trimmed.contains('dl=0')) return trimmed.replaceAll('dl=0', 'dl=1');
    if (trimmed.contains('dl=1') || trimmed.contains('raw=1')) return trimmed;

    return trimmed.contains('?') ? '$trimmed&dl=1' : '$trimmed?dl=1';
  }

  Future<void> _load() async {
    try {
      final file = await DefaultCacheManager()
          .getSingleFile(_normalizeDropboxUrl(widget.dropboxUrl));

      final bytes = await file.readAsBytes();
      final chapters = _parseDocx(bytes);

      final results = await Future.wait([
        _fetchBookmark(),
        _fetchReadingPrefs(),
        _fetchFinishedState(),
      ]);
      final bookmark = results[0] as Map<String, int>?;
      final prefs = results[1] as Map<String, Object?>;
      final finished = results[2] as bool;

      if (!mounted) return;

      final bookmarkChapter = bookmark?['chapter'];
      final startChapter =
          (bookmarkChapter != null && bookmarkChapter < chapters.length)
              ? bookmarkChapter
              : 0;

      setState(() {
        _chapters = chapters;
        _bookmarkChapter = bookmarkChapter;
        _bookmarkParagraph = bookmark?['paragraph'];
        _currentChapter = startChapter;
        _rebuildParagraphKeys();
        _theme = (prefs['theme'] as String?) ?? 'light';
        _fontScale = (prefs['fontScale'] as double?) ?? 1.0;
        _finished = finished;
        _loading = false;
        // Timer starts only now that readable content is on screen.
        _readingStartedAt = DateTime.now();
      });

      // Once the chapter has laid out, bring the bookmarked paragraph on screen.
      if (_bookmarkChapter == _currentChapter) {
        _scrollToBookmarkedParagraph();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Could not open this book.";
      });
    }
  }

  /// Unzips the DOCX and splits `word/document.xml` into chapters.
  List<BookChapter> _parseDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final entry = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw const FormatException('word/document.xml not found'),
    );

    // document.xml is UTF-8. Decoding byte-by-byte (String.fromCharCodes)
    // splits multi-byte sequences into separate Latin-1 characters, which is
    // what turned IAST diacritics into mojibake like "á¹›" and "â€".
    final content = entry.content as List<int>;
    final xmlString = utf8.decode(content, allowMalformed: true);

    final document = XmlDocument.parse(xmlString);

    // Image support: relationship id -> media bytes, resolved once up front.
    //
    // `word/_rels/document.xml.rels` maps the `r:embed` id on an `<a:blip>` to
    // a target path like `media/image1.png`, which is relative to `word/`.
    _media = _buildMediaMap(archive);

    final chapters = <BookChapter>[];
    String currentTitle = widget.bookTitle;
    var currentTitleSpans = <InlineSpan>[];
    ParagraphDecoration? currentTitleDecoration;
    var currentParagraphs = <List<InlineSpan>>[];

    // Each <w:p> stays its own paragraph — one entry per element, so
    // consecutive paragraphs are never merged.
    for (final p in document.findAllElements('p', namespace: '*')) {
      // Heading style, if any: <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      String? styleVal;
      for (final style in p.findAllElements('pStyle', namespace: '*')) {
        styleVal = style.getAttribute('val', namespace: '*') ??
            style.getAttribute('w:val');
        break;
      }

      final isHeading1 = styleVal != null &&
          styleVal.replaceAll(' ', '').toLowerCase() == 'heading1';

      final spans = _extractSpans(p);
      final plain = spansToPlainText(spans).trim();

      if (isHeading1) {
        // Close the previous chapter before starting a new one.
        // ⚠️ Unchanged: this is the page-break / "Next Chapter" boundary, and
        // the condition that opens a new chapter is exactly what it was.
        if (currentParagraphs.isNotEmpty) {
          chapters.add(BookChapter(
            title: currentTitle,
            titleSpans: List<InlineSpan>.from(currentTitleSpans),
            titleDecoration: currentTitleDecoration,
            paragraphs: List<List<InlineSpan>>.from(currentParagraphs),
          ));
          currentParagraphs = <List<InlineSpan>>[];
        }
        currentTitle = plain.isEmpty ? 'Untitled chapter' : plain;
        // The heading's own runs and banner styling now travel with it. The
        // plain title is still kept — it is what the bookmark UI and the
        // chapter list use.
        currentTitleSpans = spans;
        currentTitleDecoration = _readParagraphDecoration(p);
      } else if (plain.isNotEmpty || _containsImage(spans)) {
        // A paragraph whose only content is an image has no text, so the
        // original `plain.isNotEmpty` test alone would have dropped it.
        currentParagraphs.add(spans);
      }
    }

    if (currentParagraphs.isNotEmpty) {
      chapters.add(BookChapter(
        title: currentTitle,
        titleSpans: currentTitleSpans,
        titleDecoration: currentTitleDecoration,
        paragraphs: currentParagraphs,
      ));
    }

    // A document with no Heading 1 styles still reads as one chapter.
    if (chapters.isEmpty) {
      chapters.add(BookChapter(title: widget.bookTitle, paragraphs: const []));
    }

    return chapters;
  }

  /// True when any span in the paragraph is an inline image.
  bool _containsImage(List<InlineSpan> spans) =>
      spans.any((s) => s is WidgetSpan);

  /// Relationship id -> image bytes, for every embedded picture.
  ///
  /// Returns an empty map when the document has no relationships part or no
  /// media, which is the common case in this library — verified 2026-08-19:
  /// **neither book currently contains a single image.**
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

    // Index the media entries by their in-zip path once.
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

        // Targets are relative to `word/`, and may be written "media/x.png"
        // or "/word/media/x.png". Both are normalised here.
        final clean = target.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
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
      // A malformed relationships part must not stop the book from opening —
      // it only means images cannot be resolved.
    }

    return out;
  }

  /// Reads `<w:shd>`, `<w:pBdr>` and `<w:jc>` off a paragraph's `<w:pPr>`.
  ///
  /// Returns null when the paragraph carries none of them, so an undecorated
  /// heading renders exactly as it did before this change.
  ParagraphDecoration? _readParagraphDecoration(XmlElement paragraph) {
    XmlElement? pPr;
    for (final e in paragraph.findElements('pPr', namespace: '*')) {
      pPr = e;
      break;
    }
    if (pPr == null) return null;

    Color? fill;
    for (final shd in pPr.findElements('shd', namespace: '*')) {
      final val = shd.getAttribute('fill', namespace: '*') ??
          shd.getAttribute('w:fill');
      final parsed = _hexColor(val);
      if (parsed != null) fill = parsed;
      break;
    }

    BorderSide? side(XmlElement pBdr, String name) {
      for (final b in pBdr.findElements(name, namespace: '*')) {
        final style = (b.getAttribute('val', namespace: '*') ??
                b.getAttribute('w:val') ??
                '')
            .toLowerCase();
        // "none" and "nil" both mean no rule on that edge.
        if (style == 'none' || style == 'nil') return null;

        final colour = _hexColor(b.getAttribute('color', namespace: '*') ??
                b.getAttribute('w:color')) ??
            Colors.black87;

        // w:sz on a border is in EIGHTHS of a point (unlike w:sz on a run,
        // which is half-points). 24 -> 3pt.
        final szRaw =
            b.getAttribute('sz', namespace: '*') ?? b.getAttribute('w:sz');
        final eighths = int.tryParse(szRaw ?? '') ?? 8;
        final width = (eighths / 8.0).clamp(0.5, 12.0);

        return BorderSide(color: colour, width: width);
      }
      return null;
    }

    BorderSide? top, bottom, left, right;
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

    final decoration = ParagraphDecoration(
      fill: fill,
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      centered: centered,
    );

    // Centring alone is worth carrying; nothing at all is not.
    if (decoration.isEmpty && !centered) return null;
    return decoration;
  }

  /// Parses a Word `RRGGBB` hex value. Returns null for "auto" or malformed.
  Color? _hexColor(String? value) {
    if (value == null) return null;
    final v = value.trim().replaceAll('#', '');
    if (v.isEmpty || v.toLowerCase() == 'auto') return null;
    if (v.length != 6) return null;
    final parsed = int.tryParse(v, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }

  /// Converts one `<w:p>` into formatted spans.
  ///
  /// Walks each `<w:r>` run in document order and reads its own `<w:rPr>` for
  /// bold, italic, **colour and size**, then emits the run's children in order:
  /// `<w:t>` as text, `<w:br/>` as a newline, `<w:tab/>` as a tab, and
  /// `<w:drawing>` as an inline image.
  ///
  /// ⚠️ **Every property is read per run, never inherited from the previous
  /// one.** Bold and italic already worked this way; colour and size were not
  /// read at all before 2026-08-19. `style` is rebuilt from
  /// [kReaderParagraphStyle] on each iteration, so an uncoloured run falls back
  /// to the reader's default black rather than picking up the colour of the run
  /// before it — which is what would happen if the style were hoisted out of
  /// the loop.
  List<InlineSpan> _extractSpans(XmlElement paragraph) {
    final spans = <InlineSpan>[];

    for (final run in paragraph.findAllElements('r', namespace: '*')) {
      bool bold = false;
      bool italic = false;
      Color? colour;
      double? fontSize;

      // <w:rPr> is a direct child of the run it formats.
      for (final rPr in run.findElements('rPr', namespace: '*')) {
        bold = _isToggleOn(rPr, 'b');
        italic = _isToggleOn(rPr, 'i');

        for (final c in rPr.findElements('color', namespace: '*')) {
          colour = _hexColor(c.getAttribute('val', namespace: '*') ??
              c.getAttribute('w:val'));
          break;
        }

        for (final sz in rPr.findElements('sz', namespace: '*')) {
          final raw =
              sz.getAttribute('val', namespace: '*') ?? sz.getAttribute('w:sz');
          final halfPoints = int.tryParse(raw ?? '');
          if (halfPoints != null && halfPoints > 0) {
            // w:sz on a run is HALF-points: 28 -> 14pt. Clamped so a stray
            // value cannot blow the layout apart.
            fontSize = (halfPoints / 2.0).clamp(8.0, 40.0);
          }
          break;
        }
        break;
      }

      final style = kReaderParagraphStyle.copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
        // Null leaves kReaderParagraphStyle's own colour/size in place.
        color: colour,
        fontSize: fontSize,
      );

      for (final node in run.children.whereType<XmlElement>()) {
        switch (node.name.local) {
          case 't':
            // innerText keeps xml:space="preserve" spacing intact.
            if (node.innerText.isNotEmpty) {
              spans.add(TextSpan(text: node.innerText, style: style));
            }
            break;
          case 'br':
            spans.add(TextSpan(text: '\n', style: style));
            break;
          case 'tab':
            spans.add(TextSpan(text: '\t', style: style));
            break;
          // ⚠️ Three shapes, not one (fixed 2026-08-19). A direct-child match
          // on `drawing` alone silently dropped two of the three ways Word
          // actually embeds a picture — proven by probe, see the progress note:
          //
          //   <w:drawing>            modern DrawingML          -> <a:blip r:embed>
          //   <w:pict>               legacy VML, older/converted docs
          //                                                    -> <v:imagedata r:id>
          //   <mc:AlternateContent>  a wrapper Word emits when it supplies a
          //                          fallback; the drawing is a GRANDCHILD, so
          //                          the direct-child test never matched it
          //
          // `_imageSpanFrom` searches descendants and returns on the first hit,
          // so an AlternateContent carrying both a Choice and a Fallback for
          // the same picture still yields exactly one image.
          case 'drawing':
          case 'pict':
          case 'AlternateContent':
            final image = _imageSpanFrom(node);
            // Emitted at this exact point in the run sequence, so an image
            // between two words stays between them.
            if (image != null) spans.add(image);
            break;
        }
      }
    }

    return spans;
  }

  /// Builds an inline image span from a picture-bearing element, or null when
  /// nothing resolvable is found.
  ///
  /// Accepts `<w:drawing>`, legacy `<w:pict>`, or an `<mc:AlternateContent>`
  /// wrapper around either, and looks for whichever id form is present:
  ///   * `<a:blip r:embed="rIdN">`   — modern DrawingML
  ///   * `<v:imagedata r:id="rIdN">` — legacy VML
  ///
  /// Both are resolved through the relationship map from [_buildMediaMap].
  /// Returns on the first id that resolves, so a wrapper offering the same
  /// picture twice (a Choice plus a Fallback) still produces one image.
  InlineSpan? _imageSpanFrom(XmlElement source) {
    Uint8List? bytes;

    // Modern first — when a document offers both, DrawingML is the better one.
    for (final blip in source.findAllElements('blip', namespace: '*')) {
      final id = blip.getAttribute('embed', namespace: '*') ??
          blip.getAttribute('r:embed');
      if (id == null) continue;
      bytes = _media[id];
      if (bytes != null) break;
    }

    // Legacy VML fallback: <v:imagedata r:id="..."/>
    if (bytes == null) {
      for (final data in source.findAllElements('imagedata', namespace: '*')) {
        final id = data.getAttribute('id', namespace: '*') ??
            data.getAttribute('r:id');
        if (id == null) continue;
        bytes = _media[id];
        if (bytes != null) break;
      }
    }

    if (bytes == null) return null;

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConstrainedBox(
          // Bounded so a large picture cannot overflow the reader column.
          // Width is capped by the layout; height is capped outright.
          constraints: const BoxConstraints(maxHeight: 420),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            // ⚠️ Word also embeds legacy vector formats (EMF/WMF) that Flutter
            // cannot decode at all. Those reach this point with real bytes and
            // fail here, showing this line rather than nothing — so an unnamed
            // blank is a parsing miss, whereas this text is a format Flutter
            // will not render.
            errorBuilder: (context, error, stack) => Text(
              '[image could not be displayed]',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reads a WordprocessingML toggle such as `<w:b/>` or `<w:b w:val="0"/>`.
  /// A bare element means "on"; an explicit value decides otherwise.
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

  // ---------------------------------------------------------------------------
  // Bookmarks
  // ---------------------------------------------------------------------------

  /// Returns `{'chapter': i, 'paragraph': j}` for the stored bookmark, or null.
  Future<Map<String, int>?> _fetchBookmark() async {
    try {
      final snap =
          await _firestore.collection('bookmarks').doc(_bookmarkDocId).get();
      if (!snap.exists) return null;

      final chapter = snap.data()?['chapterIndex'];
      if (chapter is! num) return null;

      final paragraph = snap.data()?['paragraphIndex'];

      return {
        'chapter': chapter.toInt(),
        // Bookmarks written before paragraph support default to the top.
        'paragraph': paragraph is num ? paragraph.toInt() : 0,
      };
    } catch (_) {
      return null;
    }
  }

  void _rebuildParagraphKeys() {
    final count =
        _chapters.isEmpty ? 0 : _chapters[_currentChapter].paragraphs.length;
    _paragraphKeys = List.generate(count, (_) => GlobalKey());
  }

  void _scrollToBookmarkedParagraph() {
    final index = _bookmarkParagraph;
    if (index == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _paragraphKeys.length) return;

      final targetContext = _paragraphKeys[index].currentContext;
      if (targetContext == null) return;

      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    });
  }

  Future<void> _saveBookmarkAt(int paragraphIndex) async {
    final paragraphs = _chapters[_currentChapter].paragraphs;
    final text = paragraphIndex < paragraphs.length
        ? spansToPlainText(paragraphs[paragraphIndex])
        : '';

    try {
      await _firestore.collection('bookmarks').doc(_bookmarkDocId).set({
        'uid': widget.uid,
        'bookKey': widget.bookKey,
        'level': widget.level,
        'bookTitle': widget.bookTitle,
        'chapterIndex': _currentChapter,
        'paragraphIndex': paragraphIndex,
        'paragraphText': text.length > 100 ? text.substring(0, 100) : text,
        'savedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _bookmarkChapter = _currentChapter;
        _bookmarkParagraph = paragraphIndex;
        _selectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bookmark saved"),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectionMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save bookmark")),
      );
    }
  }

  Future<void> _removeBookmark() async {
    try {
      await _firestore.collection('bookmarks').doc(_bookmarkDocId).delete();

      if (!mounted) return;
      setState(() {
        _bookmarkChapter = null;
        _bookmarkParagraph = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bookmark removed"),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not remove bookmark")),
      );
    }
  }

  /// AppBar bookmark button: cancel selection, offer removal, or start picking.
  Future<void> _onBookmarkPressed() async {
    if (_selectionMode) {
      setState(() => _selectionMode = false);
      return;
    }

    if (!_hasBookmark) {
      setState(() => _selectionMode = true);
      return;
    }

    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Remove bookmark?"),
        content: Text(
          "Saved at chapter ${_bookmarkChapter! + 1}, paragraph ${_bookmarkParagraph! + 1}.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Remove", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (remove == true) await _removeBookmark();
  }

  // ---------------------------------------------------------------------------
  // Reading preferences (font size + theme)
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> _fetchReadingPrefs() async {
    try {
      final snap = await _firestore.collection('users').doc(widget.uid).get();
      final prefs = snap.data()?['readingPrefs'];
      if (prefs is! Map) return const {};
      final theme = prefs['theme'];
      final fontScale = prefs['fontScale'];
      return {
        'theme': theme is String && kReaderPalettes.containsKey(theme)
            ? theme
            : null,
        'fontScale': fontScale is num ? fontScale.toDouble() : null,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Merges into the existing map rather than overwriting it, so changing the
  /// theme here never clobbers a `language` choice made from the book list
  /// (Part 4) or vice versa — Firestore's `merge: true` deep-merges nested
  /// maps, so only the keys given here are touched.
  Future<void> _saveReadingPrefs() async {
    try {
      await _firestore.collection('users').doc(widget.uid).set({
        'readingPrefs': {'theme': _theme, 'fontScale': _fontScale},
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal: the choice still applies for the rest of this session,
      // only the cross-device/cross-session persistence is lost.
    }
  }

  Future<bool> _fetchFinishedState() async {
    try {
      final snap = await _firestore
          .collection(widget.isRdua ? 'rduaProgress' : 'booksRead')
          .doc(_progressDocId)
          .get();
      if (widget.isRdua) return snap.data()?['isRead'] == true;
      final endDate = snap.data()?['endDate'];
      return endDate != null && endDate.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Rewrites only the spans that fell back to the reader's own default
  /// colour (`kReaderParagraphStyle.color`, baked in by `_extractSpans` when
  /// the DOCX run carried no explicit `<w:color>`) to the current theme's
  /// text colour. A run whose colour WAS authored in the document keeps it
  /// exactly as parsed — theming must never repaint over deliberate document
  /// formatting, only over the reader's own unstyled default.
  ///
  /// Applied at build time, not at parse time: `_chapters` is parsed once and
  /// cached, so recolouring here (rather than reparsing the DOCX) is what
  /// lets a theme change apply immediately without reopening the book.
  List<InlineSpan> _recolor(List<InlineSpan> spans) {
    if (_theme == 'light') return spans; // parsed colour already matches
    return spans.map((s) {
      if (s is TextSpan && s.style?.color == kReaderParagraphStyle.color) {
        return TextSpan(
          text: s.text,
          children: s.children,
          style: s.style!.copyWith(color: _palette.text),
        );
      }
      return s;
    }).toList();
  }

  void _setTheme(String theme) {
    if (theme == _theme) return;
    setState(() => _theme = theme);
    _saveReadingPrefs();
  }

  void _setFontScale(double scale) {
    if (scale == _fontScale) return;
    setState(() => _fontScale = scale);
    _saveReadingPrefs();
  }

  Future<void> _openReaderSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _palette.chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget themeSwatch(String key, String label) {
              final palette = kReaderPalettes[key]!;
              final selected = _theme == key;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    // Outer state must update BEFORE the sheet redraws, or
                    // the swatch highlight would read the pre-tap value.
                    _setTheme(key);
                    setSheetState(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? Colors.deepPurple : Colors.grey.shade400,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text('Aa', style: TextStyle(color: palette.text, fontSize: 18)),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: _palette.onChrome,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final stepIndex = kReaderFontScaleSteps.indexWhere(
              (s) => (s - _fontScale).abs() < 0.001,
            );
            final safeIndex = stepIndex < 0 ? 1 : stepIndex;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reading settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _palette.onChrome,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Font size', style: TextStyle(fontSize: 12, color: _palette.secondaryText)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.text_decrease, color: _palette.onChrome),
                        onPressed: safeIndex <= 0
                            ? null
                            : () {
                                _setFontScale(kReaderFontScaleSteps[safeIndex - 1]);
                                setSheetState(() {});
                              },
                      ),
                      Expanded(
                        child: Text(
                          '${(kReaderFontScaleSteps[safeIndex] * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _palette.onChrome, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.text_increase, color: _palette.onChrome),
                        onPressed: safeIndex >= kReaderFontScaleSteps.length - 1
                            ? null
                            : () {
                                _setFontScale(kReaderFontScaleSteps[safeIndex + 1]);
                                setSheetState(() {});
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Background', style: TextStyle(fontSize: 12, color: _palette.secondaryText)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      themeSwatch('light', 'Light'),
                      themeSwatch('dark', 'Dark'),
                      themeSwatch('sepia', 'Sepia'),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Completion (Part 5.3 — Finish Book)
  // ---------------------------------------------------------------------------

  /// Book path: sets `endDate` + `finishedViaButton: true`, distinct from a
  /// student who read physically and filled `endDate` in manually from the
  /// book list's Update sheet — that path leaves `finishedViaButton` unset.
  /// Also clears `isCurrentBook`, matching how every already-finished book
  /// in real data is shaped (`endDate` set implies `isCurrentBook: false` —
  /// verified in Part 1/Part 7).
  ///
  /// Revert task (2026-08-30) — no longer advances to any other book.
  /// Finishing a book used to auto-select the next one in sequence (and,
  /// at a level's end, the next level's first book); the product owner saw
  /// that system and decided against it. A student now finishes exactly
  /// the one book they were reading, and picks whatever they want to read
  /// next themselves — there is no "next" for this write to compute at all.
  ///
  /// RDUA path ([BookReaderPage.isRdua]): an entirely separate, simpler
  /// schema (`rduaProgress`'s `isRead`/`readAt`, per that feature's own Part
  /// 2) — never touches `booksRead`, `endDate`, `finishedViaButton` or
  /// `isCurrentBook`, so a chapter read/unread state can never be confused
  /// with a book's.
  Future<void> _finishBook() async {
    if (_finishing || _finished) return;
    setState(() => _finishing = true);

    try {
      if (widget.isRdua) {
        await _firestore.collection('rduaProgress').doc(_progressDocId).set({
          'uid': widget.uid,
          'topicId': widget.level,
          'chapterNum': widget.bookKey,
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final today = DateTime.now().toIso8601String().split('T')[0];

        await _firestore.collection('booksRead').doc(_progressDocId).set(
          {
            'uid': widget.uid,
            'level': widget.level,
            'bookKey': widget.bookKey,
            'bookTitle': widget.bookTitle,
            'endDate': today,
            'finishedViaButton': true,
            // Contradictory-state task, Part 4 — forced false unconditionally
            // whenever `endDate` is present, never derived from any toggle.
            'isCurrentBook': false,
          },
          SetOptions(merge: true),
        );
      }

      if (!mounted) return;
      setState(() {
        _finished = true;
        _finishing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isRdua
              ? "Could not mark this chapter as read"
              : "Could not mark this book as finished"),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Exit handling
  // ---------------------------------------------------------------------------

  int get _elapsedSeconds => _readingStartedAt == null
      ? 0
      : DateTime.now().difference(_readingStartedAt!).inSeconds;

  Future<void> _handleExit() async {
    // A bookmark already exists — leave without asking.
    if (_hasBookmark || _loading || _error != null) {
      if (mounted) Navigator.pop(context, _elapsedSeconds);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Add a bookmark before leaving?"),
        content: Text(
          "You are on chapter ${_currentChapter + 1} of ${_chapters.length}.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'leave'),
            child: const Text("Leave"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () => Navigator.pop(dialogContext, 'bookmark'),
            child: const Text(
              "Add Bookmark",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (choice == null) return; // dismissed — stay on the page

    // "Add Bookmark" keeps the reader open so a paragraph can be picked.
    if (choice == 'bookmark') {
      if (mounted) setState(() => _selectionMode = true);
      return;
    }

    if (mounted) Navigator.pop(context, _elapsedSeconds);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  void _goToChapter(int index) {
    setState(() {
      _currentChapter = index;
      _rebuildParagraphKeys();
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// Books: unchanged, always "Next Chapter →" — zero behaviour change,
  /// gated entirely behind [BookReaderPage.isRdua].
  ///
  /// RDUA: shows the REAL upcoming chapter's own title (already parsed by
  /// `_parseDocx` from that section's actual Heading 1 text — e.g.
  /// "Reflection Questions"), not a hardcoded label list. Confirmed via
  /// real-file investigation (16 files sampled across 8 topics) that every
  /// RDUA document produces the same 3-heading sequence in the same order,
  /// but reading the title straight from `_chapters` is correct regardless
  /// of whether that holds for every one of the 50 topics — it can never
  /// mislabel a chapter, because it never guesses what the heading says.
  String _nextButtonLabel() {
    if (!widget.isRdua) return "Next Chapter  →";
    final nextIndex = _currentChapter + 1;
    if (nextIndex >= _chapters.length) return "Next Chapter  →";
    final nextTitle = _chapters[nextIndex].title.trim();
    return nextTitle.isEmpty ? "Next Chapter  →" : "$nextTitle  →";
  }

  /// One paragraph. Carries a [GlobalKey] so it can be scrolled to, highlights
  /// itself when bookmarked, and becomes tappable during selection mode.
  /// The chapter heading, with Word's banner styling when the document
  /// authored any.
  ///
  /// ⚠️ **Purely a visual wrapper.** Chapter splitting, the page-break boundary
  /// and the "Next Chapter" button are all driven by the `_chapters` list built
  /// in `_parseDocx`, and none of that is touched here — this only decides how
  /// the heading of the already-selected chapter is painted.
  ///
  /// Falls back to the original plain bold `Text` whenever the heading has no
  /// runs of its own (a synthetic first chapter) or no decoration, so an
  /// undecorated book looks exactly as it did before.
  Widget _chapterHeading(BookChapter chapter) {
    const base = TextStyle(
      // Device serif face — see the note in _paragraphTile.
      fontFamily: 'serif',
      fontSize: 24,
      fontWeight: FontWeight.bold,
      height: 1.3,
    );

    final decoration = chapter.titleDecoration;

    // A decorated heading (banner fill/border) renders against its OWN
    // authored background, not the reader's page background, so its text
    // must keep exactly the colour Word gave it — recolouring only applies
    // to an undecorated heading, which sits directly on the page.
    final headingSpans =
        decoration == null ? _recolor(chapter.titleSpans) : chapter.titleSpans;

    // With no authored runs there is nothing to colour, so the plain title
    // stands. This is the path a document without Heading 1 styles takes.
    final Widget content = chapter.titleSpans.isEmpty
        ? Text(chapter.title, style: base.copyWith(
            color: decoration == null ? _palette.text : null))
        : RichText(
            textAlign:
                decoration?.centered == true ? TextAlign.center : TextAlign.start,
            // Same reason as _paragraphTile: RichText ignores the ambient
            // MediaQuery, so most real headings (this branch is what an
            // authored Heading 1 actually takes) would otherwise never scale
            // even though the body now does.
            textScaler: TextScaler.linear(_fontScale),
            text: TextSpan(
              // The heading's own run colours and sizes win; this only supplies
              // the family and weight when a run does not specify them.
              style: base,
              children: headingSpans,
            ),
          );

    if (decoration == null || decoration.isEmpty) {
      // Centring with no fill or border still deserves honouring.
      if (decoration?.centered == true) {
        return SizedBox(width: double.infinity, child: content);
      }
      return content;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: decoration.fill,
        border: decoration.border,
      ),
      child: content,
    );
  }

  Widget _paragraphTile(List<InlineSpan> spans, int index) {
    final isBookmarked =
        _bookmarkChapter == _currentChapter && _bookmarkParagraph == index;

    // RichText so bold/italic runs and <w:br/> newlines render as authored.
    //
    // ⚠️ RichText does NOT read the ambient MediaQuery on its own (unlike
    // Text, which does) — the outer `MediaQuery(textScaler: ...)` wrap in
    // build() has no effect here unless textScaler is passed explicitly.
    // Passed straight from `_fontScale` rather than looked up via
    // MediaQuery.textScalerOf(context): this method runs on the State's own
    // `context`, which sits ABOVE that MediaQuery override in the tree, so a
    // lookup here would silently resolve to the app-wide default instead.
    final body = RichText(
      textScaler: TextScaler.linear(_fontScale),
      text: TextSpan(
        style: kReaderParagraphStyle,
        children: _recolor(spans),
      ),
    );

    return Container(
      key: index < _paragraphKeys.length ? _paragraphKeys[index] : null,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: isBookmarked
          ? BoxDecoration(
              color: Colors.deepPurple.withOpacity(.07),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: _selectionMode
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _saveBookmarkAt(index),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: body,
                ),
              ),
            )
          : Padding(
              padding: EdgeInsets.all(isBookmarked ? 8 : 0),
              child: body,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleExit();
      },
      child: Scaffold(
        backgroundColor: _palette.background,
        appBar: AppBar(
          backgroundColor: _palette.chrome,
          foregroundColor: _palette.onChrome,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleExit,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (_selectionMode)
                const Text(
                  "Tap a paragraph to bookmark",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.deepPurple,
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: "Reading settings",
              icon: const Icon(Icons.text_fields),
              onPressed:
                  (_loading || _error != null) ? null : _openReaderSettings,
            ),
            IconButton(
              tooltip: _selectionMode
                  ? "Cancel"
                  : (_hasBookmark ? "Remove bookmark" : "Add a bookmark"),
              icon: Icon(
                _selectionMode
                    ? Icons.close
                    : (_hasBookmark ? Icons.bookmark : Icons.bookmark_border),
                color: (_selectionMode || _hasBookmark)
                    ? Colors.deepPurple
                    : _palette.onChrome.withOpacity(.7),
              ),
              onPressed:
                  (_loading || _error != null) ? null : _onBookmarkPressed,
            ),
          ],
        ),
        body: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(_fontScale)),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              "The file may not be a .docx, or the link may not allow direct download.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final chapter = _chapters[_currentChapter];
    final isLast = _currentChapter >= _chapters.length - 1;

    return Column(
      children: [
        /// Chapter progress
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: _theme == 'light'
              ? Colors.deepPurple.withOpacity(.06)
              : _palette.chrome,
          child: Row(
            children: [
              Text(
                "Chapter ${_currentChapter + 1} of ${_chapters.length}",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple,
                ),
              ),
              const Spacer(),
              if (_hasBookmark)
                Row(
                  children: [
                    const Icon(Icons.bookmark,
                        size: 13, color: Colors.deepPurple),
                    const SizedBox(width: 4),
                    Text(
                      "Saved at ch ${_bookmarkChapter! + 1} · para ${_bookmarkParagraph! + 1}",
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chapterHeading(chapter),
                const SizedBox(height: 18),
                if (chapter.paragraphs.isEmpty)
                  Text(
                    "This chapter has no readable text.",
                    style: TextStyle(fontSize: 15, color: _palette.secondaryText),
                  )
                else
                  ...List.generate(
                    chapter.paragraphs.length,
                    (i) => _paragraphTile(chapter.paragraphs[i], i),
                  ),
              ],
            ),
          ),
        ),

        /// Chapter navigation
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: isLast
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Unchanged: purely a "you reached the last page of
                      // content" marker, independent of whether the Firestore
                      // completion state below has been set.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          "Finished",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // The actual completion write (Part 5.3) — additive to
                      // the "Finished" banner above, not a replacement for it.
                      if (_finished)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle,
                                size: 18, color: Colors.green),
                            const SizedBox(width: 6),
                            Text(
                              widget.isRdua
                                  ? "Marked as read"
                                  : "Marked as finished",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _palette.secondaryText,
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _finishing ? null : _finishBook,
                            icon: _finishing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    widget.isRdua
                                        ? Icons.check_circle_outline
                                        : Icons.flag_circle,
                                    size: 20),
                            label: Text(
                                widget.isRdua ? "Mark as Read" : "Finish Book"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _goToChapter(_currentChapter + 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _nextButtonLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
