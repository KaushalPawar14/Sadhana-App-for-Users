import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:folk_app/utils/SameGender.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

class SBclasses extends StatelessWidget {
  SBclasses({super.key, this.scorecardReader});

  // Tests hand in their own scorecard; the app never sets it.
  @visibleForTesting
  final ScorecardReader? scorecardReader;

  // Fetch leaderboard data
  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    final docs = await (scorecardReader ?? readScorecardDocs)();
    final directory = await GenderDirectory.forCurrentUser();

    List<Map<String, dynamic>> leaderboard = [];

    for (final entry in docs.entries) {
      // 🔥 VERY IMPORTANT: skip flag document
      if (entry.key == 'flag') continue;
      // A student sees only students of their own gender.
      if (!directory.sameByName(entry.key)) continue;
      leaderboard.add({
        'userName': entry.key,
        'totalSBClass': entry.value['totalSBClass'] ?? 0,
      });
    }

    leaderboard
        .sort((a, b) => b['totalSBClass'].compareTo(a['totalSBClass']));
    return leaderboard;
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: 'SB Watch Leaderboard',
      onBack: () => Navigator.pop(context),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchLeaderboard(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LeaderboardGhost();
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}', style: text.body),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text('No leaderboard data available.', style: text.body),
            );
          }

          List<Map<String, dynamic>> leaderboard = snapshot.data!;

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding,
                FolkSpace.lg, FolkSpace.pagePadding, 28),
            itemCount: leaderboard.length,
            itemBuilder: (context, index) {
              var user = leaderboard[index];

              return EntryAnimation(
                index: index,
                child: LeaderboardRankRow(
                  rank: index + 1,
                  name: user['userName'],
                  valueLabel: "${user['totalSBClass']} pts",
                ),
              );
            },
          );
        },
      ),
    );
  }
}
