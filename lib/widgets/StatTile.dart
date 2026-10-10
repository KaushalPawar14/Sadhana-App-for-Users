import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'CountUpText.dart';
import 'GhostPlaceholder.dart';
import 'GradientCard.dart';

enum StatTileSize { big, medium, small }

// A displayed number with its label on a gradient tile. [value] is already
// formatted by the caller from real data.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.style,
    this.size = StatTileSize.medium,
    this.onTap,
    this.valueGhost = false,
    this.countUp,
  });

  final String value;
  final String label;
  final FolkGradientStyle style;
  final StatTileSize size;
  final VoidCallback? onTap;

  // True while the number is still loading: the number is a ghost bar (the
  // tile keeps its exact size) that cross-fades into the value.
  final bool valueGhost;

  // When set, [value] is shown as this whole number, counting up from 0 the
  // FIRST time it appears (not while [valueGhost]). Later changes show at once.
  final int? countUp;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final valueStyle = switch (size) {
      StatTileSize.big => text.bigStat,
      StatTileSize.medium => text.stat,
      StatTileSize.small => text.statSmall,
    };
    return GradientCard(
      style: style,
      radius: FolkShape.tileRadius,
      padding: EdgeInsets.symmetric(
        horizontal: size == StatTileSize.small ? 14 : 16,
        vertical: 14,
      ),
      onTap: onTap,
      semanticLabel: '$value $label',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GhostCrossFade(
            loading: valueGhost,
            alignment: Alignment.centerLeft,
            ghost: SizedBox(
              height: (valueStyle.fontSize ?? 28) * 1.1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: GhostPlaceholder(
                  width: 56,
                  height: (valueStyle.fontSize ?? 28) * .75,
                  radius: 8,
                  showBars: false,
                  onGradient: true,
                ),
              ),
            ),
            child: countUp == null
                ? Text(value, style: valueStyle.copyWith(height: 1.1))
                : CountUpText(
                    value: countUp!,
                    ready: !valueGhost,
                    style: valueStyle.copyWith(height: 1.1),
                  ),
          ),
          const SizedBox(height: 2),
          Text(label, style: text.onGradientCaption),
        ],
      ),
    );
  }
}
