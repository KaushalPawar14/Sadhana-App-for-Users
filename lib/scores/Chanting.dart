import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:folk_app/utils/SameGender.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

class Chanting extends StatelessWidget {
  Chanting({super.key, this.scorecardReader});

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
        'totalChantRounds': entry.value['totalChantRounds'] ?? 0,
      });
    }

    leaderboard
        .sort((a, b) => b['totalChantRounds'].compareTo(a['totalChantRounds']));
    return leaderboard;
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: 'Chanting Leaderboard',
      onBack: () {
        Navigator.pop(context);
      },
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchLeaderboard(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LeaderboardGhost();
          }

          if (snapshot.hasError) {
            return Center(
                child: Text('Error: ${snapshot.error}', style: text.body));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text('No leaderboard data available.', style: text.body),
            );
          }

          List<Map<String, dynamic>> leaderboard = snapshot.data!;
          final rest = leaderboard.length > 3 ? leaderboard.length - 3 : 0;

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                FolkSpace.pagePadding, 0, FolkSpace.pagePadding, 28),
            itemCount: 1 + rest,
            itemBuilder: (context, index) {
              // 🎖️ Top 3 podium
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (leaderboard.length > 1)
                        Flexible(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: LeaderboardPodiumPlace(
                              gradient: FolkMedal.silver,
                              name: leaderboard[1]['userName'],
                              valueLabel:
                                  '${leaderboard[1]['totalChantRounds']} rounds',
                              medal: "🥈",
                              size: 65,
                            ),
                          ),
                        ),
                      Flexible(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: LeaderboardPodiumPlace(
                            gradient: FolkMedal.gold,
                            name: leaderboard[0]['userName'],
                            valueLabel:
                                '${leaderboard[0]['totalChantRounds']} rounds',
                            medal: "🥇",
                            size: 85,
                          ),
                        ),
                      ),
                      if (leaderboard.length > 2)
                        Flexible(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: LeaderboardPodiumPlace(
                              gradient: FolkMedal.bronze,
                              name: leaderboard[2]['userName'],
                              valueLabel:
                                  '${leaderboard[2]['totalChantRounds']} rounds',
                              medal: "🥉",
                              size: 55,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }

              // 🔽 Rest of leaderboard
              var user = leaderboard[index - 1 + 3];
              return EntryAnimation(
                index: index - 1,
                child: LeaderboardRankRow(
                  rank: index + 3,
                  name: user['userName'],
                  valueLabel: '${user['totalChantRounds']} rounds',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
