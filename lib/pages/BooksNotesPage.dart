import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookHighlights.dart';
import '../utils/BookNotes.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/NoteJump.dart';

// Books -> Notes. Three screens:
//   1. BooksNotesPage   GOOD (blue square, top left), EXCELLENT (green square, top right), RARE (purple wide
//                       rectangle, bottom), in the highlight colours.
//   2. NotesBooksPage   the NAMES of the books that have highlights in that category (nothing else).
//   3. NotesCardsPage   that book's highlights as swipeable cards, numbered in reading order, each with a "View notes"
//                       button (the note in a dialog), and "3 of 12 · 25%" for how far through them the student is.
//
// The data is the student's own highlights (`bookHighlights`, private), read once and handed down the screens.

/// The text on a highlight-coloured tile: the app's dark ink (the colours are mid-tone, so dark ink reads best).
const Color _ink = FolkColors.onGradient;

/// The Notes tiles wear the app's own theme gradients: Good = coral (pink), Excellent = green, Rare = violet.
LinearGradient categoryGradient(HighlightCategory c) => switch (c) {
      HighlightCategory.good => FolkGradients.coral,
      HighlightCategory.excellent => FolkGradients.green,
      HighlightCategory.rare => FolkGradients.violet,
    };

class BooksNotesPage extends StatefulWidget {
  const BooksNotesPage({super.key, required this.uid, this.firestore});

  final String uid;

  /// Test seam: the app never sets this.
  final FirebaseFirestore? firestore;

  @override
  State<BooksNotesPage> createState() => _BooksNotesPageState();
}

class _BooksNotesPageState extends State<BooksNotesPage> {
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

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
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
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
      MaterialPageRoute(builder: (_) => NotesBooksPage(category: c, books: booksIn(c, _entries))),
    );
  }

  Widget _tile(HighlightCategory c, {required double width, required double height, required Key key}) {
    final text = context.folkText;
    final color = Color(c.argb);
    final n = countIn(c, _entries);
    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: '${c.label}, ${n == 1 ? '1 highlight' : '$n highlights'}',
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              gradient: categoryGradient(c),
              borderRadius: BorderRadius.circular(FolkShape.cardRadius),
              boxShadow: c.glows ? [BoxShadow(color: color.withValues(alpha: c.glowAlpha * 1.3), blurRadius: 16)] : null,
            ),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(FolkShape.cardRadius),
              onTap: () => _open(c),
              child: Padding(
                padding: const EdgeInsets.all(FolkSpace.md),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.label.toUpperCase(), style: text.topBarTitle.copyWith(color: _ink, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(n == 1 ? '1 highlight' : '$n highlights', style: text.small.copyWith(color: _ink)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: 'Notes',
      onBack: () => Navigator.pop(context),
      body: _loading
          ? GhostScope(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(FolkSpace.pagePadding),
                children: const [
                  GhostPlaceholder(width: double.infinity, height: 160, showBars: false),
                  SizedBox(height: FolkSpace.cardGap),
                  GhostPlaceholder(width: double.infinity, height: 90, showBars: false),
                ],
              ),
            )
          : _failed
              ? FolkErrorRetry(message: "Couldn't load your notes just now.", onRetry: _load)
              : LayoutBuilder(
                  builder: (context, box) {
                    final gap = FolkSpace.cardGap;
                    final inner = box.maxWidth - FolkSpace.pagePadding * 2;
                    final side = (inner - gap) / 2;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(FolkSpace.pagePadding),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _tile(HighlightCategory.good, width: side, height: side, key: const ValueKey('notes-good')),
                              SizedBox(width: gap),
                              _tile(HighlightCategory.excellent, width: side, height: side, key: const ValueKey('notes-excellent')),
                            ],
                          ),
                          SizedBox(height: gap),
                          _tile(HighlightCategory.rare, width: inner, height: side * .6, key: const ValueKey('notes-rare')),
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
  const NotesBooksPage({super.key, required this.category, required this.books});

  final HighlightCategory category;
  final List<NoteBook> books;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final colors = context.folk;
    return FolkScaffold(
      title: category.label,
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
                    Text('No ${category.label.toUpperCase()} highlights yet', key: const ValueKey('notes-empty-category'), style: text.topBarTitle, textAlign: TextAlign.center),
                    const SizedBox(height: FolkSpace.sm),
                    Text('Highlight a passage while you read and it will appear here.', style: text.small, textAlign: TextAlign.center),
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
                        MaterialPageRoute(builder: (_) => NotesCardsPage(category: category, book: b)),
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
  const NotesCardsPage({super.key, required this.category, required this.book});

  final HighlightCategory category;
  final NoteBook book;

  @override
  State<NotesCardsPage> createState() => _NotesCardsPageState();
}

class _NotesCardsPageState extends State<NotesCardsPage> {
  final PageController _pages = PageController();
  int _index = 0;

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

  Widget _card(int i, NoteEntry e) {
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
