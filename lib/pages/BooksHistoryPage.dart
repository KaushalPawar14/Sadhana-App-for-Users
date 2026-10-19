import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookReadingLog.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';

/// Books -> History: one row per day the student read (the date and the minutes read that day, newest first). Tap a day
/// and it opens smoothly to list each book read that day with its minutes; tap it again and it closes.
///
/// The data is the student's own reading log (`readingDays`, see `BookReadingLog.dart`); the server keeps the newest 30
/// days. A day with no reading has no row.
class BooksHistoryPage extends StatefulWidget {
  const BooksHistoryPage({super.key, required this.uid, this.firestore});

  final String uid;

  /// Test seam: the app never sets this.
  final FirebaseFirestore? firestore;

  @override
  State<BooksHistoryPage> createState() => _BooksHistoryPageState();
}

class _BooksHistoryPageState extends State<BooksHistoryPage> {
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  bool _loading = true;
  bool _failed = false;
  List<ReadingDay> _days = const [];

  /// The days that are open (by stamp). Several can be open at once.
  final Set<int> _open = {};

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
      final snap = await _db.collection('readingDays').where('uid', isEqualTo: widget.uid).get();
      final days = parseReadingDays(snap.docs.map((d) => d.data()));
      if (!mounted) return;
      setState(() {
        _days = days;
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

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: 'History',
      onBack: () => Navigator.pop(context),
      body: _loading
          ? GhostScope(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(FolkSpace.pagePadding),
                children: [
                  for (var i = 0; i < 5; i++)
                    const Padding(
                      padding: EdgeInsets.only(bottom: FolkSpace.cardGap),
                      child: GhostPlaceholder(width: double.infinity, height: 64, showBars: false),
                    ),
                ],
              ),
            )
          : _failed
              ? FolkErrorRetry(message: "Couldn't load your reading history just now.", onRetry: _load)
              : _days.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding, FolkSpace.xxl),
                      itemCount: _days.length,
                      itemBuilder: (context, i) => _DayTile(
                        key: ValueKey('day-${_days[i].stamp}'),
                        day: _days[i],
                        open: _open.contains(_days[i].stamp),
                        onTap: () => setState(() {
                          if (!_open.remove(_days[i].stamp)) _open.add(_days[i].stamp);
                        }),
                      ),
                    ),
    );
  }

  Widget _empty() {
    final colors = context.folk;
    final text = context.folkText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FolkSpace.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 52, color: colors.disabledText),
            const SizedBox(height: FolkSpace.lg),
            Text('No reading yet', key: const ValueKey('history-empty'), style: text.topBarTitle, textAlign: TextAlign.center),
            const SizedBox(height: FolkSpace.sm),
            Text('Open a book and the days you read will appear here.', style: text.small, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({super.key, required this.day, required this.open, required this.onTap});

  final ReadingDay day;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkCard(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      padding: EdgeInsets.zero,
      radius: FolkShape.tileRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              key: ValueKey('day-header-${day.stamp}'),
              borderRadius: BorderRadius.circular(FolkShape.tileRadius),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FolkSpace.lg, vertical: FolkSpace.md),
                  child: Row(
                    children: [
                      Expanded(child: Text(DateFormat('EEE, dd MMM yyyy').format(day.date), style: text.bodyStrong)),
                      const SizedBox(width: FolkSpace.sm),
                      Text(minutesText(day.totalSeconds), key: ValueKey('day-total-${day.stamp}'), style: text.bodyStrong),
                      AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(Icons.expand_more, color: colors.mutedText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    key: ValueKey('day-books-${day.stamp}'),
                    padding: const EdgeInsets.fromLTRB(FolkSpace.lg, 0, FolkSpace.lg, FolkSpace.md),
                    child: Column(
                      children: [
                        Divider(height: 1, color: colors.surfaceSecondary),
                        for (final b in day.books)
                          Padding(
                            padding: const EdgeInsets.only(top: FolkSpace.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(b.title, style: text.body)),
                                const SizedBox(width: FolkSpace.sm),
                                Text(minutesText(b.seconds), style: text.small),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
