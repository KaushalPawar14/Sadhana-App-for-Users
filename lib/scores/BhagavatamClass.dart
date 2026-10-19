import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'CategoryBoard.dart';

// SB Watch Leaderboard: ranked by this item's points over the week / month (no multipliers) - see CategoryBoard.dart.
class SBclasses extends StatelessWidget {
  const SBclasses({super.key, this.reader});

  // Tests hand in their own competition documents; the app never sets it.
  @visibleForTesting
  final ScorecardReader? reader;

  @override
  Widget build(BuildContext context) => CategoryBoardPage(
        title: 'SB Watch Leaderboard',
        item: BoardItem.sbClass,
        podium: false,
        reader: reader,
      );
}
