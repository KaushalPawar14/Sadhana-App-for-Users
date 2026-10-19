import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'CategoryBoard.dart';

// Chanting Leaderboard: ranked by this item's points over the week / month (no multipliers) - see CategoryBoard.dart.
class Chanting extends StatelessWidget {
  const Chanting({super.key, this.reader});

  // Tests hand in their own competition documents; the app never sets it.
  @visibleForTesting
  final ScorecardReader? reader;

  @override
  Widget build(BuildContext context) => CategoryBoardPage(
        title: 'Chanting Leaderboard',
        item: BoardItem.chanting,
        podium: true,
        reader: reader,
      );
}
