import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../utils/LeaderboardData.dart';
import 'ScoreWidgets.dart' show FolkMedal;

/// An Olympic-style podium for the first three places: 2nd on the left, 1st in the middle (the tallest block),
/// 3rd on the right. Each place has its medal, the name (wraps, never cut off), the points, and a block with the
/// place number in the medal's own gradient. The viewer's own place is outlined. With fewer than three students the
/// missing places are left out (a lone winner stands in the middle).
class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({super.key, required this.top, this.myName});

  /// The first (up to) three students, best first.
  final List<RankedStudent> top;
  final String? myName;

  static const double _firstBlock = 96;
  static const double _secondBlock = 72;
  static const double _thirdBlock = 52;

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) return const SizedBox.shrink();
    // left to right: 2nd, 1st, 3rd
    final order = <int>[if (top.length > 1) 1, 0, if (top.length > 2) 2];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _Place(place: i, student: top[i], me: isMe(top[i].name, myName)),
            ),
          ),
      ],
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.place, required this.student, required this.me});

  final int place; // 0-based
  final RankedStudent student;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final medal = FolkMedal.forRank(place)!;
    final block = [LeaderboardPodium._firstBlock, LeaderboardPodium._secondBlock, LeaderboardPodium._thirdBlock][place];
    final emoji = ['🥇', '🥈', '🥉'][place];
    return Semantics(
      label: '${place + 1}${['st', 'nd', 'rd'][place]} place, ${student.name}, ${pointsText(student.points)}${me ? ', you' : ''}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: medal),
            child: Text(emoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(height: 6),
          Text(
            student.name,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: text.bodyStrong.copyWith(fontWeight: me ? FontWeight.w800 : null),
          ),
          const SizedBox(height: 2),
          Text(pointsText(student.points), textAlign: TextAlign.center, style: text.chip),
          const SizedBox(height: 8),
          Container(
            key: ValueKey('podium-block-${place + 1}'),
            height: block,
            width: double.infinity,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              gradient: medal,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: me ? Border.all(color: colors.text, width: 2.5) : null,
            ),
            child: Text('${place + 1}', style: text.stat.copyWith(color: FolkColors.onGradient, fontSize: 26)),
          ),
        ],
      ),
    );
  }
}
