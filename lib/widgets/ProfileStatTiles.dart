import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'CountUpText.dart';
import 'GhostPlaceholder.dart';
import 'GradientCard.dart';
import 'MinHeightBox.dart' show ghostHeight;

// The three tiles under the Profile name card: best daily chanting ever (green),
// best daily reading ever (coral) and best day points (violet), side by side.
//
// All three come from the user document (they are stored, kept by the server,
// because the reports they come from are deleted after a month). The best day
// points are the most the student ever earned in a single day, multipliers
// included (`users.bestDayPoints`, only ever raised by the scoring trigger).
class ProfileStatTiles extends StatelessWidget {
  const ProfileStatTiles({
    super.key,
    required this.bestChantRounds,
    required this.bestReadingMinutes,
    required this.bestDayPoints,
  });

  final int bestChantRounds;
  final int bestReadingMinutes;
  final int bestDayPoints;

  // The captions are held to this text size, so a word like "reading" always
  // fits the narrow tile whole.
  static const double captionMaxScale = 1.2;

  // The tiles are never shorter than this at the student's text size, so the
  // loading ghost and the real row are the same height: padding, the number, and
  // the caption's lines (two at the normal size; at a larger size "best reading
  // (min)" needs three).
  static double minHeightFor(BuildContext context) {
    final k = MediaQuery.textScalerOf(context).scale(12) / 12;
    final lines = k > 1.1 ? 3 : 2;
    final captionScale = k > captionMaxScale ? captionMaxScale : (k < 1 ? 1.0 : k);
    return 28 +
        ghostHeight(context, 28 * 1.1) +
        2 +
        lines * 12 * 1.43 * captionScale;
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(
              style: FolkGradientStyle.green,
              value: bestChantRounds,
              caption: 'best rounds',
              semanticLabel: 'Best day of chanting: $bestChantRounds rounds',
            ),
          ),
          const SizedBox(width: FolkSpace.cardGap),
          Expanded(
            child: _StatTile(
              style: FolkGradientStyle.coral,
              value: bestReadingMinutes,
              caption: 'best reading (min)',
              semanticLabel: 'Best day of reading: $bestReadingMinutes minutes',
            ),
          ),
          const SizedBox(width: FolkSpace.cardGap),
          Expanded(
            child: _StatTile(
              style: FolkGradientStyle.violet,
              value: bestDayPoints,
              caption: 'best day points',
              semanticLabel: 'Best day: $bestDayPoints points',
            ),
          ),
        ],
      ),
    );
  }
}

// The whole row as ghosts, while the profile loads.
class ProfileStatTilesGhost extends StatelessWidget {
  const ProfileStatTilesGhost({super.key});

  @override
  Widget build(BuildContext context) {
    final h = ProfileStatTiles.minHeightFor(context);
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: FolkSpace.cardGap),
          Expanded(
            child: GhostPlaceholder(
                width: double.infinity, height: h, radius: 24, showBars: false),
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.style,
    required this.value,
    required this.caption,
    required this.semanticLabel,
  });

  final FolkGradientStyle style;
  final int? value;
  final String caption;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return GradientCard(
      style: style,
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      semanticLabel: semanticLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            minHeight: ProfileStatTiles.minHeightFor(context) - 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shrinks, never wraps or clips, when the number is wider than the tile.
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: value == null
                    ? SizedBox(
                        width: 44,
                        height: 28 * 1.1,
                        child: const GhostPlaceholder(
                            radius: 8, showBars: false, onGradient: true),
                      )
                    : CountUpText(
                        value: value!, style: text.stat.copyWith(height: 1.1)),
              ),
            ),
            const SizedBox(height: 2),
            // Held to [captionMaxScale] so a word like "reading" always fits the
            // narrow tile whole (the tile itself grows with the text).
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: ProfileStatTiles.captionMaxScale,
              child: Text(caption, style: text.onGradientCaption),
            ),
          ],
        ),
      ),
    );
  }
}
