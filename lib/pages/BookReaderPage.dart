import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../theme/FolkTypography.dart';
import '../utils/BookDocParser.dart';
import '../utils/BookHighlightStore.dart';
import '../utils/BookHighlights.dart';
import '../utils/BookLoader.dart';
import '../utils/ReaderContrast.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/ReaderChrome.dart';
import '../widgets/ReaderHighlights.dart';

/// Base style shared by every run of body text.
const TextStyle kReaderParagraphStyle = TextStyle(
  // Device serif face: full Unicode coverage for IAST diacritics.
  fontFamily: 'serif',
  fontSize: 16,
  height: 1.6,
  color: Colors.black87,
);

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

  // Tests hand in their own book source; the app never sets this.
  @visibleForTesting
  final Stream<BookLoadUpdate> Function(String url, String title)? loader;
  @visibleForTesting
  final Future<List<Object?>> Function()? extras;

  /// Where highlights are kept (tests hand in an in-memory one; the app uses Firestore).
  @visibleForTesting
  final HighlightStore? highlightStore;

  /// The clock the reading timer uses (tests move it; the app uses the real one).
  @visibleForTesting
  final DateTime Function()? clock;

  const BookReaderPage({
    super.key,
    required this.dropboxUrl,
    required this.bookTitle,
    required this.bookKey,
    required this.level,
    required this.uid,
    this.isRdua = false,
    this.loader,
    this.extras,
    this.highlightStore,
    this.clock,
  });

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  List<ParsedChapter> _chapters = [];
  int _currentChapter = 0;

  /// False while only the first chapter has been read (the rest is still being
  /// read in the background); the Next button waits for it.
  bool _complete = true;

  /// Relationship id -> image bytes for the open document; empty when the
  /// book has no images.
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

  /// How much of the chapter on screen has been read: the scroll position as
  /// 0.0 - 1.0 (a chapter too short to scroll counts as fully read). A notifier,
  /// so a scroll repaints only the bottom bar, never the page.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// Latched once the last chapter has been read to its end: the Finish Book /
  /// Mark as Read area stays up from then on (it would otherwise flicker, because
  /// showing it shortens the scroll view). Reset on every chapter change.
  bool _endReached = false;

  /// Height of that area once laid out, added to the page's bottom padding so it
  /// never covers the last lines.
  double _endAreaHeight = 0;
  final GlobalKey _endKey = GlobalKey();

  String get _bookmarkDocId => '${widget.uid}_${widget.bookKey}';

  // --- highlights & notes (books only; see BookHighlights.dart / BookHighlightStore.dart) -------------------

  /// RDUA modules reuse this reader but have no highlights.
  bool get _highlightsOn => !widget.isRdua;

  HighlightStore? _defaultStore;
  HighlightStore get _store => widget.highlightStore ?? (_defaultStore ??= FirestoreHighlightStore());

  /// Every highlight of this student in this book, and where each sits now (a highlight whose text cannot be found
  /// is kept in [_highlights] but is not in [_placed]).
  List<BookHighlight> _highlights = [];
  List<PlacedHighlight> _placed = [];

  /// The open selection (a new one, or the highlight being edited) in the chapter on screen. While it exists, or
  /// while the panel is open, the reader is in FOCUS MODE: the bars slide away.
  ReaderRange? _range;

  /// Set while an EXISTING highlight is being edited (long-press): its id, and its category (for the preview).
  String? _editingId;
  HighlightCategory? _editCategory;

  bool _panelOpen = false;
  bool get _focus => _range != null || _panelOpen;

  /// 0 = bars shown, 1 = bars gone.
  late final AnimationController _focusController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  late final Animation<double> _focusAnim = CurvedAnimation(parent: _focusController, curve: Curves.easeInOut);

  /// One key per paragraph's text (the highlight geometry comes from its render object).
  List<GlobalKey> _textKeys = [];
  final GlobalKey _contentKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();

  /// Where the two handles sit, in the scrolling content's own coordinates.
  Offset? _startHandle;
  Offset? _endHandle;
  bool _handleSyncQueued = false;

  /// The text of every paragraph of the book as the reader draws it, kept while the chapters list is the same.
  List<List<String>> _bookTexts = const [];
  List<ParsedChapter>? _bookTextsOf;

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
    _edgeScrollTimer?.cancel();
    _focusController.dispose();
    _progress.dispose();
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
    // The three Firestore reads start at once, alongside the download and the
    // parse, rather than after them.
    final Future<List<Object?>> extrasFuture = widget.extras?.call() ??
        Future.wait<Object?>([
          _fetchBookmark(),
          _fetchReadingPrefs(),
          _fetchFinishedState(),
        ]);

    try {
      final updates = (widget.loader ?? _defaultLoader)(
          _normalizeDropboxUrl(widget.dropboxUrl), widget.bookTitle);
      var shown = false;
      List<Object?>? extras;

      await for (final update in updates) {
        if (!mounted) return;
        extras ??= await extrasFuture;
        final chapters = update.book.chapters;

        if (shown) {
          // The rest of the book has been read: swap in the full list. The
          // chapter on screen is the same one, so nothing on it moves.
          setState(() {
            _chapters = chapters;
            _media = update.book.media;
            _complete = update.complete;
            _placeHighlights();
          });
          final pending = _pendingJump;
          if (pending != null) {
            if (pending <= chapters.length) {
              _pendingJump = null;
              _goToChapter(pending - 1);
            } else if (update.complete) {
              setState(() => _pendingJump = null);
              _tellChapterRange();
            }
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncProgress());
          continue;
        }

        final bookmark = extras[0] as Map<String, int>?;
        final bookmarkChapter = bookmark?['chapter'];
        // A bookmark further in than what has been read so far: wait for it.
        if (bookmarkChapter != null &&
            bookmarkChapter >= chapters.length &&
            !update.complete) {
          continue;
        }
        final prefs = extras[1] as Map<String, Object?>;
        final finished = extras[2] as bool;

        final startChapter =
            (bookmarkChapter != null && bookmarkChapter < chapters.length)
                ? bookmarkChapter
                : 0;

        shown = true;
        setState(() {
          _chapters = chapters;
          _media = update.book.media;
          _complete = update.complete;
          _bookmarkChapter = bookmarkChapter;
          _bookmarkParagraph = bookmark?['paragraph'];
          _currentChapter = startChapter;
          _rebuildParagraphKeys();
          _theme = (prefs['theme'] as String?) ?? 'light';
          _fontScale = (prefs['fontScale'] as double?) ?? 1.0;
          _finished = finished;
          _loading = false;
          // Timer starts only now that readable content is on screen.
          _readingStartedAt = _now();
        });
        if (_highlightsOn) _loadHighlights();

        // Once the chapter has laid out, bring the bookmarked paragraph on
        // screen.
        if (_bookmarkChapter == _currentChapter) {
          _scrollToBookmarkedParagraph();
        }
      }

      if (!shown && mounted) {
        setState(() {
          _loading = false;
          _error = "Could not open this book.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Could not open this book.";
      });
    }
  }

  Stream<BookLoadUpdate> _defaultLoader(String url, String title) =>
      loadBook(url: url, fallbackTitle: title);

  /// One run list as text spans, each run in a colour that can be read on the
  /// background it sits on in the current mode (see `ReaderContrast.dart`): a
  /// run's own colour is kept when it already reaches 4.5:1, and replaced by
  /// the mode's best text colour when it does not.
  List<InlineSpan> _spansFor(
    List<InlineItem> runs, {
    int? bannerFill,
    bool bookmarked = false,
    Set<HighlightCategory> onHighlights = const {},
  }) {
    final background =
        backgroundFor(_theme, bannerFill: bannerFill, bookmarked: bookmarked);
    final onBanner = bannerFill != null;
    return [
      for (final r in runs)
        if (r is TextRun)
          TextSpan(
            text: r.text,
            style: kReaderParagraphStyle.copyWith(
              fontWeight: r.bold ? FontWeight.bold : null,
              fontStyle: r.italic ? FontStyle.italic : null,
              // Text inside (or beside) a highlight keeps 4.5:1 on the page AND on each tint it may sit on.
              color: Color(onHighlights.isEmpty
                  ? _readable(r.color, background, onBanner)
                  : readableOnHighlights(r.color, _theme, onHighlights)),
              fontSize: r.size,
            ),
          )
        else if (r is ImageRun)
          _imageSpan(r.id),
    ];
  }

  // Memo for the colour rule: the same few colours repeat across a chapter.
  final Map<int, int> _readableMemo = {};
  String _memoTheme = '';

  int _readable(int? runColor, int background, bool onBanner) {
    if (_memoTheme != _theme) {
      _readableMemo.clear();
      _memoTheme = _theme;
    }
    final key = Object.hash(runColor, background, onBanner);
    return _readableMemo[key] ??= readableColor(runColor,
        mode: _theme, background: background, onBanner: onBanner);
  }

  InlineSpan _imageSpan(String id) {
    final bytes = _media[id];
    if (bytes == null) return const TextSpan(text: '');
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConstrainedBox(
          // Bounded so a large picture cannot overflow the reader column.
          constraints: const BoxConstraints(maxHeight: 420),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            // Legacy vector formats (EMF/WMF) cannot be decoded by Flutter.
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
    _textKeys = List.generate(count, (_) => GlobalKey());
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
        ? runsToPlainText(paragraphs[paragraphIndex])
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
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        return FolkDialog.alert(
          dialogContext,
          title: "Remove bookmark?",
          content: Text(
            "Saved at chapter ${_bookmarkChapter! + 1}, paragraph ${_bookmarkParagraph! + 1}.",
            style: text.small,
          ),
          actions: [
            TextButton(
              style: FolkDialog.quietButton(colors, text),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: FolkDialog.primaryButton(colors, text).copyWith(
                backgroundColor:
                    const WidgetStatePropertyAll(FolkCalendarTokens.legendMissed),
                foregroundColor:
                    const WidgetStatePropertyAll(FolkColors.onGradient),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Remove"),
            ),
          ],
        );
      },
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
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(FolkShape.cardRadius)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final text = context.folkText;
            Widget themeSwatch(String key, String label) {
              final palette = kReaderPalettes[key]!;
              final selected = _theme == key;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: '$label background',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                    onTap: () {
                      // Outer state must update BEFORE the sheet redraws, or
                      // the swatch highlight would read the pre-tap value.
                      _setTheme(key);
                      setSheetState(() {});
                    },
                    child: Container(
                      constraints: const BoxConstraints(
                          minHeight: FolkShape.touchTarget),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius:
                            BorderRadius.circular(FolkShape.tileRadius),
                        border: Border.all(
                          color: selected
                              ? FolkCalendarTokens.selectedRing
                              : _palette.secondaryText.withValues(alpha: .35),
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text('Aa',
                              style: TextStyle(
                                  color: palette.text, fontSize: 18)),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: text.caption.copyWith(
                              color: _palette.onChrome,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            final stepIndex = kReaderFontScaleSteps.indexWhere(
              (s) => (s - _fontScale).abs() < 0.001,
            );
            final safeIndex = stepIndex < 0 ? 1 : stepIndex;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reading settings',
                    style: text.topBarTitle.copyWith(color: _palette.onChrome),
                  ),
                  const SizedBox(height: 18),
                  Text('Font size',
                      style: text.caption
                          .copyWith(color: _palette.secondaryText)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Smaller text',
                        icon: Icon(Icons.text_decrease,
                            color: _palette.onChrome),
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
                          style: text.bodyStrong
                              .copyWith(color: _palette.onChrome),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Larger text',
                        icon: Icon(Icons.text_increase,
                            color: _palette.onChrome),
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
                  Text('Background',
                      style: text.caption
                          .copyWith(color: _palette.secondaryText)),
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
  // Highlights & notes
  // ---------------------------------------------------------------------------

  DateTime _now() => (widget.clock ?? DateTime.now)();

  List<List<String>> _texts() {
    if (!identical(_bookTextsOf, _chapters)) {
      _bookTexts = [
        for (final c in _chapters) [for (final p in c.paragraphs) renderedParagraphText(p)],
      ];
      _bookTextsOf = _chapters;
    }
    return _bookTexts;
  }

  List<String> get _chapterTexts => _currentChapter < _chapters.length ? _texts()[_currentChapter] : const [];

  Future<void> _loadHighlights() async {
    try {
      final loaded = await _store.load(uid: widget.uid, bookKey: widget.bookKey, level: widget.level);
      if (!mounted) return;
      setState(() {
        _highlights = loaded;
        _placeHighlights();
      });
    } catch (_) {
      // Highlights are an extra: a failed read just means none are drawn this time.
    }
  }

  /// Works out where every highlight sits now. While the rest of the book is still being read, only a highlight
  /// that is exactly where it was stored is drawn (the others wait for the whole book, so a short phrase is not
  /// matched to the wrong chapter).
  void _placeHighlights() {
    if (_highlights.isEmpty || _chapters.isEmpty) {
      _placed = [];
      return;
    }
    final book = _texts();
    _placed = _complete
        ? placeHighlights(_highlights, book)
        : [
            for (final h in _highlights)
              if (anchorHolds(h, book)) PlacedHighlight(h, h.anchor),
          ];
  }

  void _setFocusAnimation() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _focusController.value = _focus ? 1 : 0;
    } else if (_focus) {
      _focusController.forward();
    } else {
      _focusController.reverse();
    }
  }

  RenderParagraph? _paragraphAt(int index) {
    if (index < 0 || index >= _textKeys.length) return null;
    final object = _textKeys[index].currentContext?.findRenderObject();
    return object is RenderParagraph && object.hasSize ? object : null;
  }

  /// A long-press on text that is not highlighted: selects the word under the finger and opens the handles.
  void _beginSelection(int paragraph, Offset local) {
    if (!_highlightsOn || _selectionMode || _focus) return;
    final rp = _paragraphAt(paragraph);
    final text = _chapterTexts;
    if (rp == null || paragraph >= text.length || text[paragraph].isEmpty) return;
    final len = text[paragraph].length;
    final at = rp.getPositionForOffset(local).offset.clamp(0, len);
    var word = rp.getWordBoundary(TextPosition(offset: math.min(at, len - 1)));
    var start = word.start.clamp(0, len);
    var end = word.end.clamp(0, len);
    if (end <= start) {
      start = math.min(at, len - 1);
      end = start + 1;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _range = ReaderRange(paragraph, start, paragraph, end);
      _editingId = null;
      _editCategory = null;
    });
    _setFocusAnimation();
  }

  /// Closes the selection or the edit (nothing is saved) and brings the bars back.
  void _closeRange() {
    _edgeScrollTimer?.cancel();
    setState(() {
      _range = null;
      _editingId = null;
      _editCategory = null;
      _startHandle = null;
      _endHandle = null;
    });
    _setFocusAnimation();
  }

  /// Sentence / paragraph shortcuts under the handles.
  void _expandSelection({required bool sentence}) {
    final r = _range;
    final text = _chapterTexts;
    if (r == null || r.startPara >= text.length) return;
    setState(() {
      if (sentence) {
        final s = sentenceAround(text[r.startPara], r.startOffset);
        _range = s.end > s.start ? ReaderRange(r.startPara, s.start, r.startPara, s.end) : r;
      } else {
        _range = wholeParagraphs(r, text);
      }
    });
  }

  // --- the handles ----------------------------------------------------------------------------------------

  /// Where the character at [offset] of paragraph [index] is, in the scrolling content's coordinates: the left edge of the
  /// caret and the bottom of its line.
  Offset? _caretInContent(int index, int offset) {
    final rp = _paragraphAt(index);
    final content = _contentKey.currentContext?.findRenderObject();
    if (rp == null || content is! RenderBox || !content.hasSize) return null;
    final position = TextPosition(offset: offset);
    final caret = rp.getOffsetForCaret(position, Rect.zero);
    final lineHeight = rp.getFullHeightForCaret(position);
    return content.globalToLocal(rp.localToGlobal(caret.translate(0, lineHeight)));
  }

  void _queueHandleSync() {
    if (_handleSyncQueued) return;
    _handleSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleSyncQueued = false;
      if (!mounted) return;
      final r = _range;
      final start = r == null ? null : _caretInContent(r.startPara, r.startOffset);
      final end = r == null ? null : _caretInContent(r.endPara, r.endOffset);
      if (start != _startHandle || end != _endHandle) {
        setState(() {
          _startHandle = start;
          _endHandle = end;
        });
      }
    });
  }

  /// The paragraph and character under a screen point (the nearest paragraph when the point is between two).
  ({int paragraph, int offset})? _textPositionAt(Offset global) {
    int? best;
    var bestDistance = double.infinity;
    Offset? bestLocal;
    for (var i = 0; i < _textKeys.length; i++) {
      final rp = _paragraphAt(i);
      if (rp == null) continue;
      final local = rp.globalToLocal(global);
      final dy = local.dy < 0 ? -local.dy : (local.dy > rp.size.height ? local.dy - rp.size.height : 0.0);
      if (dy < bestDistance) {
        bestDistance = dy;
        best = i;
        bestLocal = local;
      }
    }
    if (best == null || bestLocal == null) return null;
    final rp = _paragraphAt(best)!;
    final clamped = Offset(bestLocal.dx.clamp(0.0, rp.size.width), bestLocal.dy.clamp(0.0, rp.size.height));
    final len = _chapterTexts[best].length;
    return (paragraph: best, offset: rp.getPositionForOffset(clamped).offset.clamp(0, len));
  }

  Offset _lastDrag = Offset.zero;
  Timer? _edgeScrollTimer;

  /// A handle was dragged to [global]: its end of the range follows the finger (the knob hangs under the line,
  /// so the point read is a little above it). The other end never moves, and the range never becomes empty.
  void _dragHandle(bool isStart, Offset global) {
    _lastDrag = global;
    final r = _range;
    if (r == null) return;
    final hit = _textPositionAt(global.translate(0, -30));
    if (hit != null) {
      final ReaderRange next = isStart
          ? ReaderRange(hit.paragraph, hit.offset, r.endPara, r.endOffset)
          : ReaderRange(r.startPara, r.startOffset, hit.paragraph, hit.offset);
      final before = next.startPara < next.endPara || (next.startPara == next.endPara && next.startOffset < next.endOffset);
      if (before && next != r) setState(() => _range = next);
    }
    _edgeScroll(isStart);
  }

  /// Dragging a handle near the top or bottom edge of the page scrolls it.
  void _edgeScroll(bool isStart) {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !_scrollController.hasClients) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final y = _lastDrag.dy;
    final delta = y < top + 70 ? -14.0 : (y > bottom - 90 ? 14.0 : 0.0);
    _edgeScrollTimer?.cancel();
    if (delta == 0) return;
    _edgeScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
      if (target == position.pixels) return;
      _scrollController.jumpTo(target);
      _dragHandle(isStart, _lastDrag);
    });
  }

  void _endDrag() => _edgeScrollTimer?.cancel();

  // --- a new highlight: the panel --------------------------------------------------------------------------

  Future<void> _submitSelection() async {
    final r = _range;
    if (r == null || _panelOpen) return;
    setState(() => _panelOpen = true);
    _setFocusAnimation();
    final choice = await showHighlightSheet(
      context,
      chrome: _palette.chrome,
      onChrome: _palette.onChrome,
      secondary: _palette.secondaryText,
    );
    if (!mounted) return;
    setState(() => _panelOpen = false);
    if (choice == null) {
      // Cancel (or tapped outside): nothing saved, the bars come back.
      _closeRange();
      return;
    }
    final draft = BookHighlight.create(
      id: '',
      chapter: _currentChapter,
      range: r,
      paragraphs: _chapterTexts,
      category: choice.category,
      note: choice.note,
    );
    try {
      final saved = await _store.add(
        uid: widget.uid,
        bookKey: widget.bookKey,
        level: widget.level,
        bookTitle: widget.bookTitle,
        highlight: draft,
      );
      if (!mounted) return;
      setState(() {
        _highlights = [..._highlights, saved];
        _placeHighlights();
      });
      _closeRange();
    } catch (_) {
      if (!mounted) return;
      // Keep the selection so Highlight can simply be tried again.
      _setFocusAnimation();
      // Floats above the action bar (a snackbar at the bottom edge would sit on top of its buttons).
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Could not save the highlight. Try again."),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 84),
      ));
    }
  }

  // --- an existing highlight --------------------------------------------------------------------------------

  PlacedHighlight? _placedAt(int paragraph, Offset local) {
    final rp = _paragraphAt(paragraph);
    if (rp == null) return null;
    final offset = rp.getPositionForOffset(local).offset;
    final inChapter = [for (final p in _placed) if (p.anchor.chapter == _currentChapter) p];
    return highlightAt(inChapter, _chapterTexts, paragraph, offset);
  }

  /// Single tap on a highlight: its category and note, with Edit note and Change category.
  Future<void> _onHighlightTap(int paragraph, Offset local) async {
    if (!_highlightsOn || _selectionMode || _focus) return;
    final hit = _placedAt(paragraph, local);
    if (hit == null) return;
    final action = await showHighlightInfo(
      context,
      highlight: hit.highlight,
      chrome: _palette.chrome,
      onChrome: _palette.onChrome,
      secondary: _palette.secondaryText,
    );
    if (!mounted || action == null) return;
    final h = hit.highlight;
    final editNote = action == HighlightAction.editNote;
    final choice = await showHighlightSheet(
      context,
      chrome: _palette.chrome,
      onChrome: _palette.onChrome,
      secondary: _palette.secondaryText,
      initialCategory: h.category,
      initialNote: h.note,
      title: editNote ? 'Edit note' : 'Change category',
      submitLabel: 'Save',
      showCategory: !editNote,
      showNote: editNote,
    );
    if (!mounted || choice == null) return;
    await _updateHighlight(h, {'category': choice.category.key, 'note': choice.note}, h.copyWith(category: choice.category, note: choice.note));
  }

  Future<void> _updateHighlight(BookHighlight old, Map<String, Object?> fields, BookHighlight updated) async {
    try {
      await _store.update(old.id, fields);
      if (!mounted) return;
      setState(() {
        _highlights = [for (final h in _highlights) h.id == old.id ? updated : h];
        _placeHighlights();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not save the change. Nothing was changed.")));
    }
  }

  /// Long-press on a highlight: edit mode (focus mode on) with a handle at each end.
  void _beginEdit(int paragraph, Offset local) {
    if (!_highlightsOn || _selectionMode || _focus) return;
    final hit = _placedAt(paragraph, local);
    if (hit == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _range = hit.anchor.range;
      _editingId = hit.highlight.id;
      _editCategory = hit.highlight.category;
    });
    _setFocusAnimation();
  }

  /// Save in edit mode: the new extent (the category and the note stay as they are).
  Future<void> _saveEdit() async {
    final r = _range;
    final id = _editingId;
    if (r == null || id == null) return;
    final h = _highlights.firstWhere((x) => x.id == id, orElse: () => _highlights.first);
    final fresh = BookHighlight.create(
      id: id,
      chapter: _currentChapter,
      range: r,
      paragraphs: _chapterTexts,
      category: h.category,
      note: h.note,
      createdMillis: h.createdMillis,
    );
    _closeRange();
    await _updateHighlight(h, {for (final e in fresh.toFields().entries) if (e.key != 'category' && e.key != 'note') e.key: e.value}, fresh);
  }

  Future<void> _deleteEdited() async {
    final id = _editingId;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        return FolkDialog.alert(
          dialogContext,
          title: "Delete this highlight?",
          content: Text("The highlight and its note will be removed. The book is not changed.", style: text.small),
          actions: [
            TextButton(
              key: const ValueKey('delete-cancel'),
              style: FolkDialog.quietButton(colors, text),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              key: const ValueKey('delete-confirm'),
              style: FolkDialog.primaryButton(colors, text).copyWith(
                backgroundColor: const WidgetStatePropertyAll(FolkCalendarTokens.legendMissed),
                foregroundColor: const WidgetStatePropertyAll(FolkColors.onGradient),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;
    try {
      await _store.delete(id);
      if (!mounted) return;
      setState(() {
        _highlights = [for (final h in _highlights) if (h.id != id) h];
        _placeHighlights();
      });
      _closeRange();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not delete the highlight.")));
    }
  }

  /// What is drawn in paragraph [index]: every placed highlight of the chapter (except the one being edited, which
  /// is drawn as the live selection), and the open selection.
  List<PaintedRange> _paintedFor(int index) {
    final texts = _chapterTexts;
    final out = <PaintedRange>[];
    for (final p in _placed) {
      if (p.anchor.chapter != _currentChapter || p.highlight.id == _editingId) continue;
      for (final s in segmentsOf(p.anchor.range, texts)) {
        if (s.paragraph == index) out.add(PaintedRange(s.start, s.end, p.highlight.category));
      }
    }
    final r = _range;
    if (r != null) {
      for (final s in segmentsOf(r, texts)) {
        if (s.paragraph == index) out.add(PaintedRange(s.start, s.end, _editCategory));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Exit handling
  // ---------------------------------------------------------------------------

  /// The reading time never pauses: selecting, the panel, edit mode and dialogs are all part of reading.
  int get _elapsedSeconds => _readingStartedAt == null
      ? 0
      : _now().difference(_readingStartedAt!).inSeconds;

  Future<void> _handleExit() async {
    // Back while selecting or editing a highlight closes that first; it never leaves the book.
    if (_range != null && !_panelOpen) {
      _closeRange();
      return;
    }
    // A bookmark already exists — leave without asking.
    if (_hasBookmark || _loading || _error != null) {
      if (mounted) Navigator.pop(context, _elapsedSeconds);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        return FolkDialog.alert(
          dialogContext,
          title: "Add a bookmark before leaving?",
          content: Text(
            "You are on chapter ${_currentChapter + 1} of ${_chapters.length}.",
            style: text.small,
          ),
          actions: [
            TextButton(
              style: FolkDialog.quietButton(colors, text),
              onPressed: () => Navigator.pop(dialogContext, 'leave'),
              child: const Text("Leave"),
            ),
            ElevatedButton(
              style: FolkDialog.primaryButton(colors, text),
              onPressed: () => Navigator.pop(dialogContext, 'bookmark'),
              child: const Text("Add Bookmark"),
            ),
          ],
        );
      },
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
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _range = null;
      _editingId = null;
      _editCategory = null;
      _startHandle = null;
      _endHandle = null;
      _currentChapter = index;
      _rebuildParagraphKeys();
      _endReached = false;
      _endAreaHeight = 0;
    });
    _progress.value = 0;
    // A selection (and with it focus mode) does not survive a change of chapter: the bars come back.
    _edgeScrollTimer?.cancel();
    _setFocusAnimation();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncProgress());
  }

  /// A chapter the reader typed that is not read yet (the book is still being read in the
  /// background): the strip shows its loading spinner, then the page jumps.
  int? _pendingJump;

  /// "Chapter [n]": Done / Enter in the chapter box. 1..total only; otherwise a short
  /// message and the reader stays where they are. While the rest of the book is still
  /// being read, a number beyond what is ready waits (the loading state), then jumps.
  void _jumpToTypedChapter(String raw) {
    final n = int.tryParse(raw.trim());
    final ready = _chapters.length;
    if (n != null && n >= 1 && n <= ready) {
      _pendingJump = null;
      if (n - 1 != _currentChapter) _goToChapter(n - 1);
      return;
    }
    if (n != null && n > ready && !_complete) {
      setState(() => _pendingJump = n);
      return;
    }
    _tellChapterRange();
  }

  void _tellChapterRange() {
    final total = _chapters.length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text("Enter a chapter between 1 and $total")));
  }

  bool get _onLastChapter =>
      _chapters.isNotEmpty && _currentChapter >= _chapters.length - 1 && _complete;

  /// Progress from the scroll metrics: position / extent, clamped (bounce
  /// overscroll never shows below 0 or above 100); nothing to scroll = 100 %.
  void _updateProgress(ScrollMetrics m) {
    final extent = m.maxScrollExtent;
    final value = extent <= 1 ? 1.0 : (m.pixels / extent).clamp(0.0, 1.0);
    if ((value - _progress.value).abs() > .0005) _progress.value = value;

    if (value >= .995 && _onLastChapter && !_endReached) {
      // May arrive mid-layout: rebuild after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_endReached && _onLastChapter) {
          setState(() => _endReached = true);
        }
      });
    }
  }

  void _syncProgress() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    _updateProgress(position);
  }

  bool _onScroll(Notification n) {
    if (n is ScrollNotification && n.depth == 0) {
      _updateProgress(n.metrics);
    } else if (n is ScrollMetricsNotification && n.depth == 0) {
      _updateProgress(n.metrics);
    }
    return false;
  }

  /// Measures the finish area after it is laid out and makes room for it, then
  /// keeps the end of the chapter in view.
  void _measureEndArea() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _endKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      if ((box.size.height - _endAreaHeight).abs() < .5) return;
      setState(() => _endAreaHeight = box.size.height);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        if (position.hasContentDimensions) {
          _scrollController.jumpTo(position.maxScrollExtent);
        }
      });
    });
  }

  /// The right arrow's tooltip. Books: "Next chapter". RDUA: the REAL upcoming
  /// chapter's own title (already parsed by `parseDocx` from that section's actual
  /// Heading 1 text, e.g. "Reflection Questions"), never a hardcoded label list.
  String _nextTooltip() {
    if (!widget.isRdua) return "Next chapter";
    final nextIndex = _currentChapter + 1;
    if (nextIndex >= _chapters.length) return "Next chapter";
    final nextTitle = _chapters[nextIndex].title.trim();
    return nextTitle.isEmpty ? "Next chapter" : nextTitle;
  }

  /// One paragraph. Carries a [GlobalKey] so it can be scrolled to, highlights
  /// itself when bookmarked, and becomes tappable during selection mode.
  /// The chapter heading, with Word's banner styling when the document
  /// authored any.
  ///
  /// ⚠️ **Purely a visual wrapper.** Chapter splitting, the page-break boundary
  /// and the "Next Chapter" button are all driven by the `_chapters` list built
  /// in `parseDocx`, and none of that is touched here — this only decides how
  /// the heading of the already-selected chapter is painted.
  ///
  /// Falls back to the original plain bold `Text` whenever the heading has no
  /// runs of its own (a synthetic first chapter) or no decoration, so an
  /// undecorated book looks exactly as it did before.
  Widget _chapterHeading(ParsedChapter chapter) {
    const base = TextStyle(
      // Device serif face — see the note in _paragraphTile.
      fontFamily: 'serif',
      fontSize: 24,
      fontWeight: FontWeight.bold,
      height: 1.3,
    );

    final decoration = chapter.titleDecoration;
    final fill = decoration?.fill;

    // Each run is drawn in a colour that reads on what is behind it: the page
    // colour for a plain heading, the banner's own fill for a shaded one.
    final headingSpans = _spansFor(chapter.titleRuns, bannerFill: fill);

    // With no authored runs there is nothing to colour, so the plain title
    // stands. This is the path a document without Heading 1 styles takes.
    final Widget content = chapter.titleRuns.isEmpty
        ? Text(chapter.title,
            style: base.copyWith(
                color: decoration == null
                    ? _palette.text
                    : Color(_readable(
                        null,
                        backgroundFor(_theme, bannerFill: fill),
                        fill != null))))
        : RichText(
            textAlign:
                decoration?.centered == true ? TextAlign.center : TextAlign.start,
            // RichText ignores the ambient MediaQuery, so the heading would
            // never scale with the reader's font size without this.
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

    BorderSide? side(ParsedBorder? b) =>
        b == null ? null : BorderSide(color: Color(b.color), width: b.width);
    final top = side(decoration.top);
    final bottom = side(decoration.bottom);
    final left = side(decoration.left);
    final right = side(decoration.right);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill == null ? null : Color(fill),
        border: (top == null && bottom == null && left == null && right == null)
            ? null
            : Border(
                top: top ?? BorderSide.none,
                bottom: bottom ?? BorderSide.none,
                left: left ?? BorderSide.none,
                right: right ?? BorderSide.none,
              ),
      ),
      child: content,
    );
  }

  /// Is this point of paragraph [index] on a highlighted character (where the glyphs are, not the blank next to them)?
  bool _onHighlightedText(int index, Offset local) {
    final rp = _paragraphAt(index);
    if (rp == null) return false;
    final texts = _chapterTexts;
    final offset = rp.getPositionForOffset(local).offset;
    for (final p in _placed) {
      if (p.anchor.chapter != _currentChapter) continue;
      for (final s in segmentsOf(p.anchor.range, texts)) {
        if (s.paragraph != index || offset < s.start || offset >= s.end) continue;
        final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: s.start, extentOffset: s.end));
        if (boxes.any((b) => b.toRect().inflate(3).contains(local))) return true;
      }
    }
    return false;
  }

  Widget _paragraphTile(List<InlineItem> runs, int index) {
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
    final painted = _highlightsOn ? _paintedFor(index) : const <PaintedRange>[];
    final categories = {for (final r in painted) if (r.category != null) r.category!};
    final textKey = index < _textKeys.length ? _textKeys[index] : null;
    final richText = RichText(
      key: textKey,
      textScaler: TextScaler.linear(_fontScale),
      text: TextSpan(
        style: kReaderParagraphStyle,
        children: _spansFor(runs, bookmarked: isBookmarked, onHighlights: categories),
      ),
    );
    final canInteract = _highlightsOn && !_selectionMode && !_panelOpen;
    // The coloured portions are painted BEHIND the text; a long-press on text that is not highlighted starts a
    // selection, and (while a plain selection is open) a tap on the page closes it.
    final body = textKey == null
        ? richText
        : GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onLongPressStart: canInteract && _range == null ? (d) => _beginSelection(index, d.localPosition) : null,
            onTap: _range != null && _editingId == null && !_panelOpen ? _closeRange : null,
            child: CustomPaint(
              painter: ParagraphHighlightPainter(
                textKey: textKey,
                ranges: painted,
                neutral: _palette.text.withValues(alpha: .20),
              ),
              child: richText,
            ),
          );

    // ⚠️ A paragraph's size and position NEVER depend on bookmark state. The
    // bookmark tint and the tap area are drawn around the text (outside the
    // paragraph's own box), not by padding it: padding every paragraph while
    // bookmark mode was on (or the bookmarked one while it was set) changed the
    // text width and every height above the reader's position, so the page jumped
    // to another paragraph when the bookmark icon was tapped.
    const around = -8.0;
    return Container(
      key: index < _paragraphKeys.length ? _paragraphKeys[index] : null,
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isBookmarked)
            Positioned(
              left: around,
              top: around,
              right: around,
              bottom: around,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          body,
          // Over a highlighted portion only: tap shows its note, long-press edits its extent.
          if (_highlightsOn && textKey != null && _placed.isNotEmpty && !_selectionMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTapUp: canInteract && _range == null ? (d) => _onHighlightTap(index, d.localPosition) : null,
                onLongPressStart: canInteract && _range == null ? (d) => _beginEdit(index, d.localPosition) : null,
                child: HighlightHitGate(accepts: (local) => _onHighlightedText(index, local)),
              ),
            ),
          if (_selectionMode)
            Positioned(
              left: around,
              top: around,
              right: around,
              bottom: around,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _saveBookmarkAt(index),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    // The title bar grows with the text size so the book name never clips. Its
    // height does NOT depend on bookmark mode (the hint is drawn over the page's
    // bottom edge instead): a bar that changes height moves the whole page.
    final scaler = MediaQuery.textScalerOf(context);
    final toolbarHeight = math.max(
      kToolbarHeight,
      scaler.scale(16) * 1.5 + 16,
    );
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleExit();
      },
      child: AnimatedBuilder(
        animation: _focusAnim,
        // The page is built once per state change, not once per animation frame.
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_fontScale)),
          child: _buildBody(),
        ),
        builder: (context, page) {
          final shown = 1 - _focusAnim.value;
          final topInset = MediaQuery.paddingOf(context).top;
          return Scaffold(
        backgroundColor: _palette.background,
        // Focus mode: the title bar slides up and away (the page does not move under it).
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(toolbarHeight * shown),
          child: ClipRect(
            key: const ValueKey('bar-appbar'),
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: toolbarHeight + topInset,
              maxHeight: toolbarHeight + topInset,
              child: AppBar(
          backgroundColor: _palette.chrome,
          foregroundColor: _palette.onChrome,
          surfaceTintColor: Colors.transparent,
          elevation: 1,
          toolbarHeight: toolbarHeight,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.chevron_left_rounded, size: 30),
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
                style: text.bodyStrong.copyWith(color: _palette.onChrome),
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
              icon: (_selectionMode || _hasBookmark)
                  ? Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: FolkGradients.violet,
                      ),
                      child: Icon(
                        _selectionMode ? Icons.close : Icons.bookmark,
                        size: 20,
                        color: FolkColors.onGradient,
                      ),
                    )
                  : Icon(
                      Icons.bookmark_border,
                      color: _palette.onChrome.withValues(alpha: .7),
                    ),
              onPressed:
                  (_loading || _error != null) ? null : _onBookmarkPressed,
            ),
          ],
        ),
            ),
          ),
        ),
        body: page,
      );
        },
      ),
    );
  }

  /// A bar that slides out of the way in focus mode: [alignment] is the edge it leaves through's opposite side
  /// (a top bar keeps its bottom edge visible longest).
  Widget _slideAway({required Key key, required Widget child, required Alignment alignment}) {
    return AnimatedBuilder(
      animation: _focusAnim,
      child: child,
      builder: (context, c) {
        final shown = 1 - _focusAnim.value;
        return ClipRect(key: key, child: Align(alignment: alignment, heightFactor: shown, child: c));
      },
    );
  }

  Widget _buildBody() {
    final text = context.folkText;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: FolkCalendarTokens.legendMissed),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: text.body.copyWith(
                  fontSize: 16, color: _palette.onChrome),
            ),
            const SizedBox(height: 8),
            Text(
              "The file may not be a .docx, or the link may not allow direct download.",
              textAlign: TextAlign.center,
              style: text.small.copyWith(color: _palette.secondaryText),
            ),
          ],
        ),
      );
    }

    final chapter = _chapters[_currentChapter];
    final atEnd = _currentChapter >= _chapters.length - 1;
    // While the rest of the book is still being read, the last chapter READ so
    // far is not the last chapter: the right arrow waits for the next one.
    final isLast = atEnd && _complete;
    final waitingForNext = atEnd && !_complete;

    final showEnd = isLast && _endReached;
    if (showEnd) _measureEndArea();
    final barContent = ReaderProgressBar.contentHeightFor(_fontScale);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Room under the last line for the fixed bar (and the finish area above it).
    final bottomPadding = barContent + bottomInset + (showEnd ? _endAreaHeight : 0);

    return Stack(
      children: [
        Column(
          children: [
            /// Chapter header: "Chapter 7 of 30" between the two arrows
            _slideAway(
              key: const ValueKey('bar-strip'),
              alignment: Alignment.bottomCenter,
              child: ReaderChapterStrip(
              background: Color.alphaBlend(
                  _palette.onChrome.withValues(alpha: .05), _palette.chrome),
              textColor: _palette.onChrome,
              chapterLabel: _complete
                  ? "Chapter ${_currentChapter + 1} of ${_chapters.length}"
                  : "Chapter ${_currentChapter + 1}",
              bookmarkLabel: _hasBookmark
                  ? "Saved at ch ${_bookmarkChapter! + 1} · para ${_bookmarkParagraph! + 1}"
                  : null,
              onPrevious: _currentChapter > 0
                  ? () => _goToChapter(_currentChapter - 1)
                  : null,
              onNext: atEnd ? null : () => _goToChapter(_currentChapter + 1),
              nextLoading: waitingForNext || _pendingJump != null,
              nextTooltip: _nextTooltip(),
              chapterNumber: _currentChapter + 1,
              chapterTotal: _complete ? _chapters.length : null,
              onChapterSubmitted: _jumpToTypedChapter,
              ),
            ),

            Expanded(
              child: NotificationListener<Notification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  key: _viewportKey,
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPadding),
                  child: Stack(
                    key: _contentKey,
                    fit: StackFit.passthrough,
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _chapterHeading(chapter),
                          const SizedBox(height: 18),
                          if (chapter.paragraphs.isEmpty)
                            Text(
                              "This chapter has no readable text.",
                              style: TextStyle(
                                  fontSize: 15, color: _palette.secondaryText),
                            )
                          else
                            ...List.generate(
                              chapter.paragraphs.length,
                              (i) => _paragraphTile(chapter.paragraphs[i], i),
                            ),
                        ],
                      ),
                      ..._handles(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        /// Fixed to the bottom: the finish area (last chapter, once read to the
        /// end) above the slim progress bar.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectionMode)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: IgnorePointer(
                    child: ReaderPill(label: "Tap a paragraph to bookmark"),
                  ),
                ),
              // Focus mode: what can be done with the open selection, floating where the bars were.
              if (_range != null && !_panelOpen) _focusBar(),
              _slideAway(
                key: const ValueKey('bar-bottom'),
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showEnd) _finishArea(text),
                    ValueListenableBuilder<double>(
                      valueListenable: _progress,
                      builder: (context, value, _) => ReaderProgressBar(
                        progress: value,
                        background: _palette.chrome,
                        textColor: _palette.secondaryText,
                        trackColor: _palette.onChrome.withValues(alpha: .12),
                        fontScale: _fontScale,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The two drag handles of the open selection, inside the scrolling content so they move with the text.
  List<Widget> _handles() {
    if (_range == null) return const [];
    _queueHandleSync();
    final color = handleColor(_editCategory);
    Widget at(Offset? o, bool isStart) => o == null
        ? const SizedBox.shrink()
        : Positioned(
            left: o.dx - ReaderHandle.size / 2,
            top: o.dy - 8,
            child: ReaderHandle(
              key: ValueKey(isStart ? 'handle-start' : 'handle-end'),
              color: color,
              isStart: isStart,
              onDragStart: () {},
              onDragUpdate: (g) => _dragHandle(isStart, g),
              onDragEnd: _endDrag,
            ),
          );
    return [at(_startHandle, true), at(_endHandle, false)];
  }

  Widget _focusBar() {
    final editing = _editingId != null;
    final onChrome = _palette.onChrome;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
      child: ReaderActionBar(
        background: _palette.chrome,
        foreground: onChrome,
        children: editing
            ? [
                ReaderActionButton(key: const ValueKey('edit-delete'), label: 'Delete', color: FolkCalendarTokens.legendMissed, onPressed: _deleteEdited),
                ReaderActionButton(key: const ValueKey('edit-cancel'), label: 'Cancel', color: onChrome, onPressed: _closeRange),
                ReaderActionButton(key: const ValueKey('edit-save'), label: 'Save', color: onChrome, strong: true, onPressed: _saveEdit),
              ]
            : [
                ReaderActionButton(key: const ValueKey('sel-sentence'), label: 'Sentence', color: onChrome, onPressed: () => _expandSelection(sentence: true)),
                ReaderActionButton(key: const ValueKey('sel-paragraph'), label: 'Paragraph', color: onChrome, onPressed: () => _expandSelection(sentence: false)),
                ReaderActionButton(key: const ValueKey('sel-cancel'), label: 'Cancel', color: onChrome, onPressed: _closeRange),
                ReaderActionButton(key: const ValueKey('sel-highlight'), label: 'Highlight', color: onChrome, strong: true, onPressed: _submitSelection),
              ],
      ),
    );
  }

  /// Last chapter, read to its end. Unfinished: the Finish Book / Mark as Read
  /// button (the completion write is `_finishBook`, unchanged). Already finished:
  /// the "Finished" banner and "Marked as finished" line, as before.
  Widget _finishArea(FolkTypography text) {
    return Container(
      key: _endKey,
      width: double.infinity,
      color: _palette.chrome,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: _finished
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  constraints:
                      const BoxConstraints(minHeight: FolkShape.buttonHeight),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: FolkGradients.green,
                    borderRadius: BorderRadius.circular(FolkShape.buttonRadius),
                  ),
                  child: Text(
                    "Finished",
                    style: text.button.copyWith(color: FolkColors.onGradient),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 18, color: FolkCalendarTokens.legendSubmitted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.isRdua ? "Marked as read" : "Marked as finished",
                        style: text.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _palette.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : ReaderGradientButton(
              onPressed: _finishing ? null : _finishBook,
              loading: _finishing,
              gradient: FolkGradients.green,
              icon: widget.isRdua
                  ? Icons.check_circle_outline
                  : Icons.flag_circle,
              label: widget.isRdua ? "Mark as Read" : "Finish Book",
            ),
    );
  }
}
