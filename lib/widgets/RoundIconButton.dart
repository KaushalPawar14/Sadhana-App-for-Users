import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

enum RoundIconButtonVariant { elevated, quiet }

// A 44 dp circular icon button inside a 48 dp touch target. [elevated] is a
// surface with a soft shadow; [quiet] is the flat secondary-surface look used
// inside cards (calendar month arrows).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.variant = RoundIconButtonVariant.elevated,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final RoundIconButtonVariant variant;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final elevated = variant == RoundIconButtonVariant.elevated;

    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onPressed != null,
      excludeSemantics: true,
      onTap: onPressed,
      child: PressScale(
        enabled: onPressed != null,
        child: SizedBox(
          width: FolkShape.touchTarget,
          height: FolkShape.touchTarget,
          child: Center(
            child: Container(
              width: FolkShape.iconButtonSize,
              height: FolkShape.iconButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: elevated ? colors.surface : colors.surfaceSecondary,
                boxShadow: elevated ? colors.iconShadows : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkResponse(
                  onTap: onPressed,
                  radius: FolkShape.touchTarget / 2,
                  child: Center(
                    child: Icon(icon, size: iconSize, color: colors.text),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
