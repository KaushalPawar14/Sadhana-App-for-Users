import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';

// Page background with the full-width top fade (lavender in light, faint green
// in dark). Put it behind a screen's content.
class FolkPageBackground extends StatelessWidget {
  const FolkPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    return ColoredBox(
      color: colors.pageBackground,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: FolkColors.fadeHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: colors.topFade),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
