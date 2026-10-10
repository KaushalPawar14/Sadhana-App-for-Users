import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'CountUpText.dart';
import 'GradientCard.dart';

// One of the two tiles above the Sadhana calendar: a big number line ("4 of 10",
// "2 days") and a small caption under it, on a gradient. The number counts up
// once, the first time it is shown; if there is nothing to count yet, [friendly]
// takes its place in the same spot. As tall as its text needs at any size.
class SadhanaStatTile extends StatelessWidget {
  const SadhanaStatTile({
    super.key,
    required this.style,
    required this.value,
    required this.caption,
    this.suffix = '',
    this.friendly,
    this.semanticLabel,
  });

  final FolkGradientStyle style;

  // The number that counts up.
  final int value;

  // Text after the number ("of 10", "days").
  final String suffix;
  final String caption;

  // Shown instead of the number and suffix when there is nothing to count yet.
  final String? friendly;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return GradientCard(
      style: style,
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      semanticLabel: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shrinks (never wraps or clips) when the number and its words are
          // wider than the tile.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: friendly != null
                  ? Text(friendly!, style: text.stat.copyWith(height: 1.1), maxLines: 1)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        CountUpText(
                            value: value, style: text.stat.copyWith(height: 1.1)),
                        if (suffix.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(suffix,
                              style: text.stat.copyWith(height: 1.1),
                              maxLines: 1),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 2),
          Text(caption, style: text.onGradientCaption),
        ],
      ),
    );
  }
}
