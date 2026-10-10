import 'package:flutter/material.dart';

// A box that is AT LEAST [minHeight] tall and grows with its content, so text
// inside it is never clipped when the student's text size is large. Use this
// (never a fixed height) wherever text sits inside a pinned-looking row.
class MinHeightBox extends StatelessWidget {
  const MinHeightBox({
    super.key,
    required this.minHeight,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final double minHeight;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Align(alignment: alignment, child: child),
    );
  }
}

// The height a ghost should have to stand in for text that is [base] dp tall at
// the default text size: it grows with the student's text size, like the text.
double ghostHeight(BuildContext context, double base) {
  final scaled = MediaQuery.textScalerOf(context).scale(base);
  return scaled > base ? scaled : base;
}
