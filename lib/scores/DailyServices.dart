import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'CategoryBoard.dart';

// Service Leaderboard: ranked by this item's points over the week / month (no multipliers) - see CategoryBoard.dart.
class DailyServices extends StatelessWidget {
  const DailyServices({super.key, this.reader});

  // Tests hand in their own competition documents; the app never sets it.
  @visibleForTesting
  final ScorecardReader? reader;

  @override
  Widget build(BuildContext context) => CategoryBoardPage(
        title: 'Service Leaderboard',
        item: BoardItem.service,
        podium: false,
        reader: reader,
      );
}
