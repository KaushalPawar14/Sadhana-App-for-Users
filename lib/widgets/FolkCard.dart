import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// A surface card: white (light) / dark surface (dark), radius 28 (or [radius]),
// a soft shadow. With [onTap] it ripples and scales to 0.97 on press.
class FolkCard extends StatelessWidget {
  const FolkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FolkSpace.lg),
    this.radius = FolkShape.cardRadius,
    this.onTap,
    this.margin,
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  // Overrides the surface colour (a selected or highlighted card).
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final borderRadius = BorderRadius.circular(radius);

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: borderRadius,
        boxShadow: colors.cardShadows,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );

    if (onTap != null) card = PressScale(child: card);
    if (semanticLabel != null) {
      card = Semantics(
        button: onTap != null,
        label: semanticLabel,
        container: true,
        child: card,
      );
    }
    return card;
  }
}
