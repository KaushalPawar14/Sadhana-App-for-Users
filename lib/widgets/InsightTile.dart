import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'GradientCard.dart';

// A tile on the Insights page. Every one is laid out the same way, so the five
// read as a set:
//
//   icon circle (top left)                       arrow circle (top right)
//   title    — ONE style (`FolkTypography.tileTitle`), never scaled to fit,
//              at most 2 lines, in an area that always holds 2 lines
//   subtitle — one style, directly under the title area
//
// The title area is always two lines tall, so every title starts at exactly the
// same distance from the top of its tile, whatever the other tiles say. The
// tile is at least [minHeight] tall (a square, or as tall as one for the wide
// Leaderboard) and grows when the text size needs more room.
class InsightTile extends StatelessWidget {
  const InsightTile({
    super.key,
    required this.style,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.minHeight,
    this.titleLines = 2,
    this.semanticLabel,
  });

  final FolkGradientStyle style;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final double minHeight;

  /// How many lines of room the title area keeps (2 on Insights; a tile whose title is always one short word,
  /// like the Notes categories, keeps 1).
  final int titleLines;

  /// What a screen reader says; the title when null.
  final String? semanticLabel;

  // Titles grow with the student's text size only up to this, so the longest word
  // ("Performance") always fits a tile on one line.
  static const double maxTitleScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final titleStyle = text.tileTitle;

    // The Stack is as wide as the tile allows (`double.infinity`): with only the
    // invisible placeholder as its sized child it was exactly as wide as the
    // letter "A" in it, and the title (laid out across the Stack's width) was one
    // letter wide.
    final titleArea = MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTitleScale,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
            // Two lines of the same style, invisible: they size the area, so a
            // one-line title and a two-line title take the same room.
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text(List.filled(titleLines, 'A').join('\n'), maxLines: titleLines, style: titleStyle),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Text(
                title,
                key: const ValueKey('insight-tile-title'),
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
          ],
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: GradientCard(
        style: style,
        radius: FolkShape.cardRadius,
        padding: const EdgeInsets.all(16),
        semanticLabel: semanticLabel ?? title,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -2,
              bottom: 4,
              child: Icon(
                icon,
                size: 64,
                color: FolkColors.onGradient.withValues(alpha: .08),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: FolkColors.onGradientIconTile,
                      ),
                      child: Icon(icon, size: 22),
                    ),
                    const Spacer(),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: FolkColors.onGradientIconTile,
                      ),
                      child: const Icon(Icons.north_east, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                titleArea,
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  key: const ValueKey('insight-tile-subtitle'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.onGradientSmall.copyWith(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
