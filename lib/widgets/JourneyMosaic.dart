import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'GhostPlaceholder.dart';
import 'GradientCard.dart';

// The Journey screen's mosaic: gradient tiles of mixed sizes in two columns.
// Heights are minimums (a short tile is at least 112 dp, a tall one at least
// 236 dp: two short tiles and the gap between them); every tile grows with its
// content and with the student's text size, and a tall tile always stretches
// to match the two short tiles beside it.

const double kJourneyShortMin = 112;
const double kJourneyTallMin = kJourneyShortMin * 2 + FolkSpace.cardGap;

// "Hare Krishna," (small, muted) and the student's first name (large). While
// the name is loading its line is a ghost of the same height, so nothing moves
// when it arrives.
class JourneyGreeting extends StatelessWidget {
  const JourneyGreeting({
    super.key,
    required this.firstName,
    required this.loading,
  });

  // Null or empty once loaded: only "Hare Krishna," is shown.
  final String? firstName;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final nameStyle = text.screenTitle;
    return Padding(
      padding: const EdgeInsets.only(top: FolkSpace.sm, bottom: FolkSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hare Krishna,', style: text.body.copyWith(color: context.folk.mutedText)),
          if (loading)
            // A name's worth of height (an invisible name sizes it) with a
            // ghost bar on top, so the real name moves nothing.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Stack(
                children: [
                  Opacity(
                    opacity: 0,
                    child: Text('Hare', maxLines: 1, style: nameStyle),
                  ),
                  const Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GhostPlaceholder(
                        width: 150,
                        height: 30,
                        radius: 10,
                        showBars: false,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (firstName != null && firstName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(firstName!, maxLines: 1, style: nameStyle),
              ),
            ),
        ],
      ),
    );
  }
}

// Two tiles side by side, half width each, 12 dp apart, the same height.
class JourneyPair extends StatelessWidget {
  const JourneyPair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: FolkSpace.cardGap),
          Expanded(child: right),
        ],
      ),
    );
  }
}

// Two short tiles one above the other, 12 dp apart. The lower one takes any
// height the neighbouring tall tile needs beyond the two, so the column is
// always exactly as tall as the tall tile and nothing overflows.
class JourneyStack extends StatelessWidget {
  const JourneyStack({super.key, required this.top, required this.bottom});

  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // IntrinsicHeight: the upper tile is as tall as its content needs (a
        // tile spreads its content over the height it is given).
        IntrinsicHeight(child: top),
        const SizedBox(height: FolkSpace.cardGap),
        Expanded(child: bottom),
      ],
    );
  }
}

// One mosaic tile. [leading] is the 44 dp avatar (the A-E letter, or an icon)
// and may carry its unseen dot. [line] is the progress line or description;
// [stat] is a big number (the tall Chanting tile) with [statCaption] under it.
class JourneyTile extends StatelessWidget {
  const JourneyTile({
    super.key,
    required this.style,
    required this.title,
    required this.leading,
    required this.onTap,
    this.subtitle,
    this.line,
    this.stat,
    this.statCaption,
    this.watermark,
    this.tall = false,
    this.square = false,
  });

  final FolkGradientStyle style;
  final String title;
  final Widget leading;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? line;
  final Widget? stat;
  final String? statCaption;
  final IconData? watermark;
  final bool tall;

  // A square tile: at least as tall as it is wide, with its title on one line
  // (it grows taller, never clips, when the text size needs more room).
  final bool square;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final card = GradientCard(
      style: style,
      radius: FolkShape.cardRadius,
      padding: EdgeInsets.all(square ? 16 : 18),
      semanticLabel: title,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (watermark != null)
            Positioned(
              right: -2,
              bottom: 4,
              child: Icon(
                watermark,
                size: tall ? 96 : 64,
                color: FolkColors.onGradient.withValues(alpha: .08),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
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
              const SizedBox(height: 12),
              const Spacer(),
              _FitTitle(title: title, style: text.cardTitle, oneLine: square),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: text.onGradientSmall),
              ],
              if (stat != null) ...[
                const SizedBox(height: 10),
                stat!,
                if (statCaption != null)
                  Text(statCaption!, style: text.onGradientCaption),
              ],
              if (line != null) ...[
                SizedBox(height: stat == null ? 4 : 2),
                line!,
              ],
            ],
          ),
        ],
      ),
    );

    // A square tile is as tall as the tile column is wide (two columns, the
    // page padding and the gap, read from the screen width).
    final columnWidth = (MediaQuery.of(context).size.width -
            2 * FolkSpace.pagePadding -
            FolkSpace.cardGap) /
        2;
    final tileMinHeight =
        square ? columnWidth : (tall ? kJourneyTallMin : kJourneyShortMin);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: tileMinHeight),
      child: card,
    );
  }
}

// A tile title: one line per word, each line shrunk (never clipped, never
// wrapped mid-word) to fit the tile's width at any text size.
class _FitTitle extends StatelessWidget {
  const _FitTitle({
    required this.title,
    required this.style,
    this.oneLine = false,
  });

  final String title;
  final TextStyle style;
  final bool oneLine;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final word in oneLine ? [title] : title.split(' '))
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(word, maxLines: 1, softWrap: false, style: style),
            ),
        ],
      ),
    );
  }
}
