import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// The main action button: 56 dp tall, fully rounded, ink on cream (light) or
// cream on ink (dark). Disabled when [onPressed] is null or [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.gradient,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  // A gradient button: the gradient is the background and the text, icon and
  // spinner are ALWAYS the ink colour on it (`FolkColors.onGradient`), also
  // while loading or disabled. Size, radius and press feedback are the same.
  final LinearGradient? gradient;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(FolkShape.buttonRadius);
    final foreground =
        gradient != null ? FolkColors.onGradient : colors.primaryFg;

    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
            ),
          )
        else ...[
          if (icon != null) ...[
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              style: text.button.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    final inkWell = InkWell(
      borderRadius: radius,
      onTap: enabled ? onPressed : null,
      child: Container(
        height: FolkShape.buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        child: content,
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        enabled: enabled,
        child: Opacity(
          opacity: enabled || loading ? 1 : .45,
          child: Material(
            color: gradient == null ? colors.primaryBg : Colors.transparent,
            borderRadius: radius,
            child: gradient == null
                ? inkWell
                : Ink(
                    decoration:
                        BoxDecoration(gradient: gradient, borderRadius: radius),
                    child: inkWell,
                  ),
          ),
        ),
      ),
    );
  }
}
