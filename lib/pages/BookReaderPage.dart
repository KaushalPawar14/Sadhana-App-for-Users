import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../theme/FolkTypography.dart';
import '../utils/BookDocParser.dart';
import '../utils/BookLoader.dart';
import '../utils/ReaderContrast.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/ReaderChrome.dart';

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
  });

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
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
          });
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
          _readingStartedAt = DateTime.now();
        });

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
              color: Color(_readable(r.color, background, onBanner)),
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
      _currentChapter = index;
      _rebuildParagraphKeys();
      _endReached = false;
      _endAreaHeight = 0;
    });
    _progress.value = 0;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncProgress());
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
    final body = RichText(
      textScaler: TextScaler.linear(_fontScale),
      text: TextSpan(
        style: kReaderParagraphStyle,
        children: _spansFor(runs, bookmarked: isBookmarked),
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
    final text = context.folkText;
    // The title bar grows with the text size so the two-line title (book name
    // and the bookmark hint) never clips.
    final scaler = MediaQuery.textScalerOf(context);
    final toolbarHeight = math.max(
      kToolbarHeight,
      scaler.scale(16) * 1.5 +
          (_selectionMode ? scaler.scale(11) * 1.5 + 12 : 0) +
          16,
    );
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
              if (_selectionMode) ...[
                const SizedBox(height: 4),
                const ReaderPill(label: "Tap a paragraph to bookmark"),
              ],
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
        body: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(_fontScale)),
          child: _buildBody(),
        ),
      ),
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
            ReaderChapterStrip(
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
              nextLoading: waitingForNext,
              nextTooltip: _nextTooltip(),
            ),

            Expanded(
              child: NotificationListener<Notification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPadding),
                  child: Column(
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
