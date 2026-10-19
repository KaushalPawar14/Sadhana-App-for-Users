import 'package:flutter/material.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FolkErrorRetry.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/FolkSegmented.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

/// The four category leaderboards (Chanting, Book Reading, SB class, Daily services), on the new point
/// system: each student is ranked by that ITEM's points summed over the period (this week / this month),
/// with NO multipliers - the multipliers belong to the overall Weekly / Monthly Performance total only.
///
/// The points are worked out by the server from the reports (functions/scoring.js) and stored on the
/// student's `competition` document as `weekly.pts_<item>` / `monthly.pts_<item>`:
///  * chanting: 50 x rounds / chanting commitment, no cap;
///  * reading: 50 x minutes / reading commitment, no cap (commitment 0: a flat 50 a day with any reading);
///  * class and services: Fully 50, Partially 25, Not 0.
/// Same category and gender separation as before (a student reads only their own).
enum BoardItem { chanting, reading, sbClass, service }

extension BoardItemX on BoardItem {
  /// The field name after `weekly.pts_` / `monthly.pts_`.
  String get key => switch (this) {
        BoardItem.chanting => 'chanting',
        BoardItem.reading => 'reading',
        BoardItem.sbClass => 'class',
        BoardItem.service => 'service',
      };
}

/// "62.5 pts" / "50 pts".
String pointsText(num p) => '${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(1)} pts';

/// The ranking of [docs] (competition documents by student name) for [item] over [period]
/// ('weekly' or 'monthly'): best first, a student with no points yet scores 0.
List<Map<String, dynamic>> rankByItem(
  Map<String, Map<String, dynamic>> docs,
  BoardItem item,
  String period, {
  bool Function(String name)? include,
}) {
  final rows = <Map<String, dynamic>>[];
  for (final e in docs.entries) {
    if (e.key == 'flag') continue;
    if (include != null && !include(e.key)) continue;
    final v = e.value['$period.pts_${item.key}'];
    rows.add({'userName': e.key, 'points': v is num ? v.toDouble() : 0.0});
  }
  rows.sort((a, b) => (b['points'] as double).compareTo(a['points'] as double));
  return rows;
}

class CategoryBoardPage extends StatefulWidget {
  const CategoryBoardPage({
    super.key,
    required this.title,
    required this.item,
    this.podium = true,
    this.reader,
  });

  final String title;
  final BoardItem item;

  /// The first three on a podium (Chanting, Book Reading, SB class), the rest in rows; Daily services is rows only.
  final bool podium;

  /// Tests hand in their own documents; the app reads the live `competition` collection.
  final ScorecardReader? reader;

  @override
  State<CategoryBoardPage> createState() => _CategoryBoardPageState();
}

class _CategoryBoardPageState extends State<CategoryBoardPage> {
  String _period = 'weekly';
  late Future<_Loaded> _future = _load();

  Future<_Loaded> _load() async {
    final docs = await (widget.reader ?? readCompetitionDocs)();
    final directory = await GenderDirectory.forCurrentUser();
    return _Loaded(docs, directory);
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: widget.title,
      onBack: () => Navigator.pop(context),
      body: FutureBuilder<_Loaded>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LeaderboardGhost();
          }
          if (snapshot.hasError) {
            return FolkErrorRetry(
              message: "Couldn't load the leaderboard just now.",
              onRetry: () => setState(() {
                _future = _load();
              }),
            );
          }
          final loaded = snapshot.data!;
          final board = rankByItem(loaded.docs, widget.item, _period, include: loaded.directory.sameByName);
          final rest = widget.podium && board.length > 3 ? board.length - 3 : 0;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.sm, FolkSpace.pagePadding, FolkSpace.sm),
                child: FolkSegmented<String>(
                  segments: const [
                    FolkSegment(value: 'weekly', label: 'This week'),
                    FolkSegment(value: 'monthly', label: 'This month'),
                  ],
                  value: _period,
                  onChanged: (v) => setState(() => _period = v),
                ),
              ),
              Expanded(
                child: board.isEmpty
                    ? Center(child: Text('No leaderboard data available.', style: text.body))
                    : ListView.builder(
                        key: PageStorageKey<String>('board-${widget.item.key}-$_period'),
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, 0, FolkSpace.pagePadding, 28),
                        itemCount: widget.podium ? 1 + rest : board.length,
                        itemBuilder: (context, index) {
                          if (!widget.podium) {
                            final user = board[index];
                            return EntryAnimation(
                              index: index,
                              child: LeaderboardRankRow(
                                rank: index + 1,
                                name: user['userName'],
                                valueLabel: pointsText(user['points'] as double),
                              ),
                            );
                          }
                          if (index == 0) return _podium(board);
                          final user = board[index - 1 + 3];
                          return EntryAnimation(
                            index: index - 1,
                            child: LeaderboardRankRow(
                              rank: index + 3,
                              name: user['userName'],
                              valueLabel: pointsText(user['points'] as double),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _podium(List<Map<String, dynamic>> board) {
    Widget place(int i, dynamic gradient, String medal, double size, double bottom, int flex) => Flexible(
          flex: flex,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: LeaderboardPodiumPlace(
              gradient: gradient,
              name: board[i]['userName'],
              valueLabel: pointsText(board[i]['points'] as double),
              medal: medal,
              size: size,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (board.length > 1) place(1, FolkMedal.silver, '🥈', 65, 20, 2),
          place(0, FolkMedal.gold, '🥇', 85, 40, 3),
          if (board.length > 2) place(2, FolkMedal.bronze, '🥉', 55, 10, 2),
        ],
      ),
    );
  }
}

class _Loaded {
  _Loaded(this.docs, this.directory);
  final Map<String, Map<String, dynamic>> docs;
  final GenderDirectory directory;
}
