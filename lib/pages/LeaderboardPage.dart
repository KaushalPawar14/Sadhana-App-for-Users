import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../scores/TopMonthResults.dart';
import '../scores/TopWeekResults.dart';
import '../services/PercentageServices.dart';
import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/LeaderboardData.dart';
import '../utils/SameGender.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/FolkSegmented.dart';
import '../widgets/LeaderboardPodium.dart';
import '../widgets/OwnScoreCard.dart';
import '../widgets/PressScale.dart';
import '../widgets/ScoreWidgets.dart';

/// The Leaderboard: the total-points ranking and the scores of the student's own group (own category AND own
/// gender), for a Weekly or a Monthly period.
///
///  * App bar: "Leaderboard" and a "Results" button that opens the finished results (three podium cards with
///    confetti) of the period that is selected.
///  * Just under it, attached: row 1 the period switch (Weekly | Monthly), row 2 the tabs (Leaderboard | Scores).
///    The two always apply together (Monthly + Scores = the month's scores).
///  * Leaderboard tab: the total points (multipliers applied) with an Olympic podium for 1st-3rd, then the rest
///    as a list; the student's own row is highlighted.
///  * Scores tab: the student's own points and their change against the previous period, then the best five of
///    each field (Chanting, Reading, Hearing and - FOLK only - Service) by that field's own points, no multipliers.
///
/// Everything comes from the `competition` documents, which the server keeps up to date from the reports. One live
/// read feeds both tabs and both periods, so switching never reloads.
enum LeaderboardTab { leaderboard, scores }

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({
    super.key,
    required this.username,
    this.docsStream,
    this.changesLoader,
    this.firestore,
    this.initialPeriod = BoardPeriod.weekly,
    this.initialTab = LeaderboardTab.leaderboard,
  });

  /// The student's own name (their `competition` document).
  final String username;

  /// Tests hand in their own documents; the app reads the live `competition` collection.
  @visibleForTesting
  final Stream<Map<String, Map<String, dynamic>>>? docsStream;

  /// Tests hand in the percentage changes; the app asks [PercentageService].
  @visibleForTesting
  final Future<Map<String, double>> Function(BoardPeriod period)? changesLoader;

  /// Tests hand in an in-memory database; the app reads the live one.
  @visibleForTesting
  final FirebaseFirestore? firestore;

  final BoardPeriod initialPeriod;
  final LeaderboardTab initialTab;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  late BoardPeriod _period = widget.initialPeriod;
  late LeaderboardTab _tab = widget.initialTab;

  late Future<GenderDirectory> _directory = GenderDirectory.forCurrentUser();
  late Stream<Map<String, Map<String, dynamic>>> _docs = _openDocs();

  /// Percentage changes per period, asked once each and kept (so switching back and forth never asks again).
  final Map<BoardPeriod, Future<Map<String, double>>> _changes = {};

  Stream<Map<String, Map<String, dynamic>>> _openDocs() {
    final given = widget.docsStream;
    if (given != null) return given;
    return Stream.fromFuture(GenderDirectory.forCurrentUser()).asyncExpand((directory) => (widget.firestore ?? FirebaseFirestore.instance)
        .collection('competition')
        .where('gender', isEqualTo: directory.mine)
        .where('category', isEqualTo: directory.category)
        .snapshots()
        .map((snap) => {for (final d in snap.docs) d.id: d.data()}));
  }

  Future<Map<String, double>> _changesFor(BoardPeriod p) => _changes.putIfAbsent(p, () async {
        try {
          final loader = widget.changesLoader;
          if (loader != null) return await loader(p);
          final service = PercentageService();
          return p == BoardPeriod.weekly
              ? await service.getWeeklyPercentageChange(username: widget.username)
              : await service.getMonthlyPercentageChange(username: widget.username);
        } catch (_) {
          return <String, double>{};
        }
      });

  void _retry() => setState(() {
        GenderDirectory.reset();
        _directory = GenderDirectory.forCurrentUser();
        _docs = _openDocs();
      });

  void _openResults() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _period == BoardPeriod.weekly
            ? WeeklyLeaderboardPage(username: widget.username)
            : MonthlyLeaderboardPage(username: widget.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: 'Leaderboard',
      actions: [_ResultsButton(onPressed: _openResults)],
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.md, FolkSpace.pagePadding, FolkSpace.sm),
        child: Column(
          children: [
            FolkSegmented<BoardPeriod>(
              segments: [for (final p in BoardPeriod.values) FolkSegment(value: p, label: p.label)],
              value: _period,
              onChanged: (v) => setState(() => _period = v),
            ),
            const SizedBox(height: 8),
            FolkSegmented<LeaderboardTab>(
              segments: const [
                FolkSegment(value: LeaderboardTab.leaderboard, label: 'Leaderboard'),
                FolkSegment(value: LeaderboardTab.scores, label: 'Scores'),
              ],
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ],
        ),
      ),
      body: FutureBuilder<GenderDirectory>(
        future: _directory,
        builder: (context, dirSnap) {
          if (dirSnap.hasError) return _failure();
          if (!dirSnap.hasData) return const LeaderboardGhost(rows: 4);
          final directory = dirSnap.data!;
          return StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: _docs,
            builder: (context, snap) {
              if (snap.hasError) return _failure();
              if (!snap.hasData) return const LeaderboardGhost(rows: 4);
              final docs = snap.data!;
              return AnimatedSwitcher(
                duration: FolkMotion.of(context, const Duration(milliseconds: 200)),
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: _tab == LeaderboardTab.leaderboard
                      ? _LeaderboardTab(docs: docs, directory: directory, period: _period, myName: widget.username)
                      : _ScoresTab(
                          docs: docs,
                          directory: directory,
                          period: _period,
                          myName: widget.username,
                          changes: _changesFor(_period),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _failure() => FolkErrorRetry(message: "Couldn't load the leaderboard just now.", onRetry: _retry);
}

/// The "Results" button of the app bar: a pill, at least 48 dp tall.
class _ResultsButton extends StatelessWidget {
  const _ResultsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Semantics(
      button: true,
      label: 'Results',
      excludeSemantics: true,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
          key: const ValueKey('results-button'),
          constraints: const BoxConstraints(minHeight: FolkShape.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: colors.surfaceSecondary, borderRadius: BorderRadius.circular(FolkShape.touchTarget / 2)),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_outlined, size: 18, color: colors.text),
              const SizedBox(width: 6),
              Text('Results', style: text.chip),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------------------- the Leaderboard tab
class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab({required this.docs, required this.directory, required this.period, required this.myName});

  final Map<String, Map<String, dynamic>> docs;
  final GenderDirectory directory;
  final BoardPeriod period;
  final String myName;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final board = totalRanking(docs, period, include: directory.sameByName);
    final scored = board.where((r) => r.points > 0).toList();
    if (scored.isEmpty) {
      return _Empty(
        key: const ValueKey('leaderboard-empty'),
        title: 'No points ${period.thisPeriod} yet',
        message: 'Submit your sadhana and your group\'s ranking will appear here.',
      );
    }
    final top = scored.take(3).toList();
    final rest = board.skip(top.length).toList();
    final myIndex = board.indexWhere((r) => isMe(r.name, myName));
    return ListView(
      key: PageStorageKey<String>('leaderboard-${period.key}'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.md, FolkSpace.pagePadding, 28),
      children: [
        if (myIndex >= 0)
          Padding(
            padding: const EdgeInsets.only(bottom: FolkSpace.md),
            child: Text(
              'Your place: #${myIndex + 1} of ${board.length}',
              key: const ValueKey('my-place'),
              textAlign: TextAlign.center,
              style: text.bodyStrong,
            ),
          ),
        LeaderboardPodium(top: top, myName: myName),
        const SizedBox(height: FolkSpace.lg),
        for (var i = 0; i < rest.length; i++)
          EntryAnimation(
            index: i,
            child: LeaderboardRankRow(
              rank: top.length + i + 1,
              name: rest[i].name,
              valueLabel: pointsText(rest[i].points),
              highlight: isMe(rest[i].name, myName),
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------------------- the Scores tab
class _ScoresTab extends StatelessWidget {
  const _ScoresTab({
    required this.docs,
    required this.directory,
    required this.period,
    required this.myName,
    required this.changes,
  });

  final Map<String, Map<String, dynamic>> docs;
  final GenderDirectory directory;
  final BoardPeriod period;
  final String myName;
  final Future<Map<String, double>> changes;

  Map<String, dynamic>? _mine() {
    for (final e in docs.entries) {
      if (isMe(nameOf(e.key, e.value), myName) || isMe(e.key, myName)) return e.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final hostel = directory.isHostelLocalite;
    final fields = [for (final f in BestField.values) if (!(f.folkOnly && hostel)) f];
    return ListView(
      key: PageStorageKey<String>('scores-${period.key}'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.md, FolkSpace.pagePadding, 28),
      children: [
        FutureBuilder<Map<String, double>>(
          future: changes,
          builder: (context, snap) => OwnScoreCard(
            period: period,
            data: _mine(),
            changes: snap.data,
            hostelLocalite: hostel,
          ),
        ),
        const SizedBox(height: FolkSpace.xl),
        Text('Best performers ${period.thisPeriod}', style: text.topBarTitle),
        const SizedBox(height: 4),
        Text('Points of each field alone, without multipliers.', style: text.caption),
        const SizedBox(height: FolkSpace.md),
        for (final f in fields) ...[
          _BestCard(
            field: f,
            best: bestOf(docs, period, f, include: directory.sameByName),
            myName: myName,
            period: period,
          ),
          const SizedBox(height: FolkSpace.cardGap),
        ],
      ],
    );
  }
}

class _BestCard extends StatelessWidget {
  const _BestCard({required this.field, required this.best, required this.myName, required this.period});

  final BestField field;
  final List<RankedStudent> best;
  final String myName;
  final BoardPeriod period;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkCard(
      key: ValueKey('best-${field.key}'),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.title, style: text.bodyStrong.copyWith(fontSize: 17)),
          Text(field.hint, style: text.caption),
          const SizedBox(height: 10),
          if (best.isEmpty)
            Text('No points here ${period.thisPeriod} yet.', key: ValueKey('best-${field.key}-empty'), style: text.small)
          else
            for (var i = 0; i < best.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: FolkMedal.forRank(i),
                        color: FolkMedal.forRank(i) == null ? colors.surfaceSecondary : null,
                      ),
                      child: Text('${i + 1}', style: text.chip.copyWith(color: FolkMedal.forRank(i) == null ? colors.text : FolkColors.onGradient)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        best[i].name,
                        style: text.body.copyWith(fontWeight: isMe(best[i].name, myName) ? FontWeight.w800 : null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(pointsText(best[i].points), style: text.chip),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🏆', style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: text.topBarTitle),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: text.small),
          ],
        ),
      ),
    );
  }
}
