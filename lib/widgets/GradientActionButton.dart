import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

/// A themed action button for dialogs: a theme gradient (violet, green ...) with the app's ink text, a soft elevation
/// tinted by the gradient, and the app's press feedback. Looks the same in light, dark and sepia (a gradient is the same
/// in every mode). At least [minHeight] tall; the label wraps (never cut) and the button grows when the text is large.
class GradientActionButton extends StatelessWidget {
  const GradientActionButton({
    super.key,
    required this.label,
    required this.gradient,
    required this.onPressed,
    this.minHeight = 52,
    this.verticalPadding = 10,
  });

  final String label;
  final LinearGradient gradient;
  final VoidCallback? onPressed;
  final double minHeight;

  /// The space above and below the label inside the button.
  final double verticalPadding;

  /// The horizontal padding inside the button (the label has the rest of the width).
  static const double horizontalPadding = 12;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final radius = BorderRadius.circular(FolkShape.buttonRadius);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // a soft elevation in the gradient's own tone (never a hard black shadow)
            boxShadow: [BoxShadow(color: gradient.colors.last.withValues(alpha: .38), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(gradient: gradient, borderRadius: radius),
              child: InkWell(
                borderRadius: radius,
                onTap: onPressed,
                child: Container(
                  constraints: BoxConstraints(minHeight: minHeight),
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: text.button.copyWith(color: FolkColors.onGradient),
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
