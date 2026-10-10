import 'package:flutter/material.dart';

import 'GhostPlaceholder.dart';
import 'MinHeightBox.dart';

// One line of text (a progress line on a gradient card) that shows a ghost bar
// until its data arrives, then cross-fades into the text. The line is at least
// [lineHeight] tall and grows with large text; the ghost grows the same way.
class GhostedTextLine extends StatelessWidget {
  const GhostedTextLine({
    super.key,
    required this.loading,
    required this.child,
    this.lineHeight = 17.2,
    this.ghostWidth = 150,
  });

  final bool loading;
  final Widget child;
  final double lineHeight;
  final double ghostWidth;

  @override
  Widget build(BuildContext context) {
    final height = ghostHeight(context, lineHeight);
    return GhostCrossFade(
      loading: loading,
      alignment: Alignment.centerLeft,
      ghost: SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: GhostPlaceholder(
            width: ghostWidth,
            height: height * .75,
            radius: 6,
            showBars: false,
            onGradient: true,
          ),
        ),
      ),
      child: MinHeightBox(minHeight: lineHeight, child: child),
    );
  }
}
