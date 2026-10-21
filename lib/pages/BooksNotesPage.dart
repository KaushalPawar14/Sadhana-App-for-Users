import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookDoubts.dart';
import '../utils/BookHighlights.dart';
import '../utils/BookNotes.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/InsightTile.dart';
import '../widgets/NoteJump.dart';
import '../widgets/NotesHowItWorks.dart';
import '../widgets/RoundIconButton.dart';

// Books -> Notes. Three screens:
//   1. BooksNotesPage   GOOD (gold, dots) and EXCELLENT (green, leaves) squares on top, RARE (violet, sparkle) wide
//                       below: the app's own tile (InsightTile / GradientCard), like Journey and Insights.
//   2. NotesBooksPage   the NAMES of the books that have highlights in that category (nothing else).
//   3. NotesCardsPage   that book's highlights as swipeable cards, numbered in reading order, each with a "View notes"
//                       button (the note in a dialog), and "3 of 12 · 25%" for how far through them the student is.
//
// The data is the student's own highlights (`bookHighlights`, private), read once and handed down the screens.

/// The text on a highlight-coloured tile: the app's dark ink (the colours are mid-tone, so dark ink reads best).
const Color _ink = FolkColors.onGradient;

/// The Notes tiles wear the app's own theme gradients: Good = saffron (gold), Excellent = green, Rare = violet.
LinearGradient categoryGradient(HighlightCategory c) => switch (c) {
      HighlightCategory.good => FolkGradients.saffron,
      HighlightCategory.excellent => FolkGradients.green,
      HighlightCategory.rare => FolkGradients.violet,
      HighlightCategory.doubt => FolkGradients.pink,
    };

/// "12 highlights in 3 books" / "1 highlight in 1 book" / "No highlights yet".
String notesCountLine(int highlights, int books, {String noun = 'highlight'}) {
  if (highlights == 0) return 'No ${noun}s yet';
  return '${highlights == 1 ? '1 $noun' : '$highlights ${noun}s'} in ${books == 1 ? '1 book' : '$books books'}';
}

class BooksNotesPage extends StatefulWidget {
  const BooksNotesPage({super.key, required this.uid, this.firestore, this.doubtStore, this.openDoubtId});

  final String uid;

  /// Test seam: the app never sets this.
  final FirebaseFirestore? firestore;

  /// Test seam: where doubts are read (the app reads `bookDoubts`).
  final DoubtStore? doubtStore;

  /// Open this doubt's card straight away (the "your guide answered your doubt" notification).
  final String? openDoubtId;

  @override
  State<BooksNotesPage> createState() => _BooksNotesPageState();
}

class _BooksNotesPageState extends State<BooksNotesPage> {
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  DoubtStore get _doubtStore => widget.doubtStore ?? FirestoreDoubtStore(_db);

  /// The student's doubts (highlight id -> doubt). A failed read only leaves the Doubts without answers.
  Map<String, Doubt> _doubts = const {};

  bool _loading = true;
  bool _failed = false;
  List<NoteEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final snap = await _db.collection('bookHighlights').where('uid', isEqualTo: widget.uid).get();
      final entries = parseNotes(snap.docs.map((d) => (id: d.id, data: d.data())));
      Map<String, Doubt> doubts = const {};
      try {
        doubts = await _doubtStore.loadMine(widget.uid);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _doubts = doubts;
        _loading = false;
      });
      final open = widget.openDoubtId;
      if (open != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openDoubt(open));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _open(HighlightCategory c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotesBooksPage(category: c, books: booksIn(c, _entries), doubts: _doubts, doubtStore: _doubtStore)),
    );
  }

  /// A notification about one doubt: its book's cards, on that doubt.
  void _openDoubt(String id) {
    if (!mounted) return;
    final books = booksIn(HighlightCategory.doubt, _entries);
    for (final b in books) {
      final i = b.entries.indexWhere((e) => e.id == id);
      if (i >= 0) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => NotesBooksPage(category: HighlightCategory.doubt, books: books, doubts: _doubts, doubtStore: _doubtStore)));
        Navigator.push(context, MaterialPageRoute(builder: (_) => NotesCardsPage(category: HighlightCategory.doubt, book: b, doubts: _doubts, doubtStore: _doubtStore, initialIndex: i)));
        return;
      }
    }
    _open(HighlightCategory.doubt);
  }

  static IconData _icon(HighlightCategory c) => switch (c) {
        HighlightCategory.good => Icons.star_outline_rounded,
        HighlightCategory.excellent => Icons.workspace_premium_outlined,
        HighlightCategory.rare => Icons.auto_awesome_outlined,
        HighlightCategory.doubt => Icons.help_outline_rounded,
      };

  static FolkGradientStyle _style(HighlightCategory c) => switch (c) {
        HighlightCategory.good => FolkGradientStyle.saffron,
        HighlightCategory.excellent => FolkGradientStyle.green,
        HighlightCategory.rare => FolkGradientStyle.violet,
        HighlightCategory.doubt => FolkGradientStyle.pink,
      };

  Widget _tile(HighlightCategory c, {required double minHeight, required Key key, required int index}) {
    final n = countIn(c, _entries);
    final isDoubt = c == HighlightCategory.doubt;
    final line = notesCountLine(n, booksIn(c, _entries).length, noun: isDoubt ? 'doubt' : 'highlight');
    return EntryAnimation(
      index: index,
      child: InsightTile(
        key: key,
        style: _style(c),
        title: c.tileTitle,
        subtitle: line,
        icon: _icon(c),
        minHeight: minHeight,
        titleLines: 1,
        semanticLabel: '${c.label}, $line',
        onTap: () => _open(c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: 'Notes',
      onBack: () => Navigator.pop(context),
      actions: [
        RoundIconButton(
          key: const ValueKey('notes-how-button'),
          icon: Icons.info_outline_rounded,
          iconSize: 22,
          semanticLabel: 'How notes work',
          onPressed: () => showNotesHowItWorks(context),
        ),
      ],
      body: _failed
          ? FolkErrorRetry(message: "Couldn't load your notes just now.", onRetry: _load)
          : Builder(
              builder: (context) {
                // The page is full width: the width comes from the screen (no LayoutBuilder in this app).
                final gap = FolkSpace.cardGap;
                final inner = MediaQuery.sizeOf(context).width - FolkSpace.pagePadding * 2;
                final side = (inner - gap) / 2;
                if (_loading) {
                  // The ghost has the tiles' own shape, so nothing moves when the real ones arrive.
                  return GhostScope(
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(FolkSpace.pagePadding),
                      children: [
                        Row(children: [
                          GhostPlaceholder(width: side, height: side, showBars: false),
                          SizedBox(width: gap),
                          GhostPlaceholder(width: side, height: side, showBars: false),
                        ]),
                        SizedBox(height: gap),
                        Row(children: [
                          GhostPlaceholder(width: side, height: side, showBars: false),
                          SizedBox(width: gap),
                          GhostPlaceholder(width: side, height: side, showBars: false),
                        ]),
                      ],
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(FolkSpace.pagePadding),
                  child: Column(
                    children: [
                      // Both squares are as tall as the taller of the two (a big text size grows them together).
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _tile(HighlightCategory.good, minHeight: side, key: const ValueKey('notes-good'), index: 0)),
                            SizedBox(width: gap),
                            Expanded(child: _tile(HighlightCategory.excellent, minHeight: side, key: const ValueKey('notes-excellent'), index: 1)),
                          ],
                        ),
                      ),
                      SizedBox(height: gap),
                      // Rare and Doubts: the second row of the 2 x 2.
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _tile(HighlightCategory.rare, minHeight: side, key: const ValueKey('notes-rare'), index: 2)),
                            SizedBox(width: gap),
                            Expanded(child: _tile(HighlightCategory.doubt, minHeight: side, key: const ValueKey('notes-doubt'), index: 3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// The books that have highlights in one category: their NAMES, and nothing else.
class NotesBooksPage extends StatelessWidget {
  const NotesBooksPage({super.key, required this.category, required this.books, this.doubts = const {}, this.doubtStore});

  final HighlightCategory category;
  final List<NoteBook> books;
  final Map<String, Doubt> doubts;
  final DoubtStore? doubtStore;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final colors = context.folk;
    return FolkScaffold(
      title: category.tileTitle,
      onBack: () => Navigator.pop(context),
      body: books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(FolkSpace.pagePadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sticky_note_2_outlined, size: 52, color: colors.disabledText),
                    const SizedBox(height: FolkSpace.lg),
                    Text(category == HighlightCategory.doubt ? 'No doubts yet' : 'No ${category.label.toUpperCase()} highlights yet',
                        key: const ValueKey('notes-empty-category'), style: text.topBarTitle, textAlign: TextAlign.center),
                    const SizedBox(height: FolkSpace.sm),
                    Text(
                        category == HighlightCategory.doubt
                            ? 'Select a passage while you read, choose Doubt, and ask the AI or your guide.'
                            : 'Highlight a passage while you read and it will appear here.',
                        style: text.small,
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding, FolkSpace.xxl),
              children: [
                for (final b in books)
                  FolkCard(
                    margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
                    padding: EdgeInsets.zero,
                    radius: FolkShape.tileRadius,
                    child: InkWell(
                      key: ValueKey('notes-book-${b.bookId}'),
                      borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => NotesCardsPage(category: category, book: b, doubts: doubts, doubtStore: doubtStore)),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: FolkSpace.lg, vertical: FolkSpace.md),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 28,
                                decoration: BoxDecoration(color: Color(category.argb), borderRadius: BorderRadius.circular(3)),
                              ),
                              const SizedBox(width: FolkSpace.md),
                              Expanded(child: Text(b.title, style: text.bodyStrong)),
                              Icon(Icons.chevron_right, color: colors.mutedText),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One book's highlights in one category, as horizontally swipeable cards numbered in reading order.
class NotesCardsPage extends StatefulWidget {
  const NotesCardsPage({super.key, required this.category, required this.book, this.doubts = const {}, this.doubtStore, this.initialIndex = 0});

  final HighlightCategory category;
  final NoteBook book;

  /// The student's doubts (for the Doubts category: each card shows its question and "View answer").
  final Map<String, Doubt> doubts;
  final DoubtStore? doubtStore;
  final int initialIndex;

  @override
  State<NotesCardsPage> createState() => _NotesCardsPageState();
}

class _NotesCardsPageState extends State<NotesCardsPage> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _showNote(NoteEntry e) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        final maxNote = MediaQuery.of(dialogContext).size.height * .5;
        return Dialog(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your note', style: text.topBarTitle),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxNote),
                  child: SingleChildScrollView(
                    child: Text(e.note, key: const ValueKey('note-dialog-text'), style: text.body.copyWith(height: 1.45)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A doubt's answer, live: "Not answered yet" until it comes, then the answer and who gave it.
  Future<void> _showAnswer(NoteEntry e) {
    final known = widget.doubts[e.id];
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        final maxH = MediaQuery.of(dialogContext).size.height * .5;
        Widget body(Doubt? d) {
          if (d == null || !d.answered) {
            final who = d == null ? '' : (d.toGuide ? 'Your guide has your doubt.' : 'The AI has your doubt.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not answered yet', key: const ValueKey('answer-pending'), style: text.bodyStrong),
                if (who.isNotEmpty) ...[const SizedBox(height: 6), Text(who, style: text.small)],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Answered by ${d.answeredByLabel}', key: const ValueKey('answer-by'), style: text.caption.copyWith(color: colors.mutedText)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: SingleChildScrollView(child: Text(d.answer!, key: const ValueKey('answer-text'), style: text.body.copyWith(height: 1.45))),
              ),
            ],
          );
        }

        final store = widget.doubtStore;
        return Dialog(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Answer', style: text.topBarTitle),
                const SizedBox(height: 12),
                if (store == null)
                  body(known)
                else
                  StreamBuilder<Doubt?>(stream: store.watch(e.id), initialData: known, builder: (context, snap) => body(snap.data ?? known)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _doubtCard(int i, NoteEntry e) {
    final colors = context.folk;
    final text = context.folkText;
    final color = Color(widget.category.argb);
    final doubt = widget.doubts[e.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.sm, FolkSpace.pagePadding, FolkSpace.lg),
      child: Container(
        key: ValueKey('note-card-${i + 1}'),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FolkShape.cardRadius),
          border: Border.all(color: color, width: 1.6),
          boxShadow: colors.cardShadows,
        ),
        padding: const EdgeInsets.all(FolkSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  child: Text('${i + 1}', key: ValueKey('note-number-${i + 1}'), style: text.bodyStrong.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: FolkSpace.md),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.truncated ? '${e.text}…' : e.text, key: ValueKey('note-text-${i + 1}'), style: text.body.copyWith(height: 1.5)),
                    const SizedBox(height: FolkSpace.lg),
                    Text('Your doubt', style: text.caption.copyWith(color: colors.mutedText)),
                    const SizedBox(height: 4),
                    Text(doubt?.question ?? 'Your question could not be loaded.', key: ValueKey('doubt-question-${i + 1}'), style: text.bodyStrong.copyWith(height: 1.4)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: FolkSpace.md),
            OutlinedButton(
              key: ValueKey('view-answer-${i + 1}'),
              onPressed: () => _showAnswer(e),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(FolkShape.buttonHeight),
                foregroundColor: colors.text,
                side: BorderSide(color: color, width: 1.6),
              ),
              child: const Text('View answer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(int i, NoteEntry e) {
    if (widget.category == HighlightCategory.doubt) return _doubtCard(i, e);
    final colors = context.folk;
    final text = context.folkText;
    final color = Color(widget.category.argb);
    return Padding(
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.sm, FolkSpace.pagePadding, FolkSpace.lg),
      child: Container(
        key: ValueKey('note-card-${i + 1}'),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FolkShape.cardRadius),
          border: Border.all(color: color, width: 1.6),
          boxShadow: widget.category.glows ? [BoxShadow(color: color.withValues(alpha: widget.category.glowAlpha * 1.3), blurRadius: 14)] : colors.cardShadows,
        ),
        padding: const EdgeInsets.all(FolkSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  child: Text('${i + 1}', key: ValueKey('note-number-${i + 1}'), style: text.bodyStrong.copyWith(color: _ink, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: FolkSpace.md),
            Expanded(
              child: SingleChildScrollView(
                child: Text(e.truncated ? '${e.text}…' : e.text, key: ValueKey('note-text-${i + 1}'), style: text.body.copyWith(height: 1.5)),
              ),
            ),
            const SizedBox(height: FolkSpace.md),
            if (e.note.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: FolkSpace.md),
                  child: Text('No note added', key: ValueKey('note-none-${i + 1}'), style: text.small.copyWith(color: colors.mutedText)),
                ),
              )
            else
              OutlinedButton(
                key: ValueKey('view-note-${i + 1}'),
                onPressed: () => _showNote(e),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(FolkShape.buttonHeight),
                  foregroundColor: colors.text,
                  side: BorderSide(color: color, width: 1.6),
                ),
                child: const Text('View notes'),
              ),
          ],
        ),
      ),
    );
  }

  /// "Note [n] of total": Done / Enter in the box. 1..total only; otherwise a short message and the cards stay.
  void _jumpTo(String raw, int total) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < 1 || n > total) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Enter a note between 1 and $total')));
      return;
    }
    if (n - 1 == _index) return;
    if (FolkMotion.reduced(context)) {
      _pages.jumpToPage(n - 1);
    } else {
      _pages.animateToPage(n - 1, duration: FolkMotion.of(context, const Duration(milliseconds: 260)), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final colors = context.folk;
    final entries = widget.book.entries;
    final total = entries.length;
    return FolkScaffold(
      title: widget.book.title,
      onBack: () => Navigator.pop(context),
      body: total == 0
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(FolkSpace.pagePadding),
                child: Text('No notes in this book yet', key: const ValueKey('notes-empty-book'), style: text.topBarTitle, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding, FolkSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NoteJump(
                        key: const ValueKey('notes-progress'),
                        number: (_index + 1).clamp(1, total),
                        total: total,
                        textColor: colors.text,
                        suffix: ' · ${(progressFraction(_index, total) * 100).round()}%',
                        onSubmitted: (raw) => _jumpTo(raw, total),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          key: const ValueKey('notes-progress-bar'),
                          value: progressFraction(_index, total),
                          minHeight: 8,
                          backgroundColor: colors.surfaceSecondary,
                          color: Color(widget.category.argb),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: total,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _card(i, entries[i]),
                  ),
                ),
              ],
            ),
    );
  }
}
