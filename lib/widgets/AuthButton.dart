import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// A full-width sign-in button: 56 dp tall at least, fully rounded, with an
// optional leading mark (the Google "G", a mail icon). [primary] is ink on
// cream (cream on ink in dark); otherwise it is a surface with a soft outline.
// While [loading] it shows a spinner and does nothing.
class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.loading = false,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final bool loading;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(FolkShape.buttonRadius);
    final background = primary ? colors.primaryBg : colors.surface;
    final foreground = primary ? colors.primaryFg : colors.text;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: Opacity(
          opacity: enabled || loading ? 1 : .45,
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: primary
                  ? BorderSide.none
                  : BorderSide(
                      color: colors.mutedText.withValues(alpha: .35), width: 1.5),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: enabled ? onPressed : null,
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: FolkShape.buttonHeight),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                alignment: Alignment.center,
                child: loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: foreground),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 12),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: text.button.copyWith(color: foreground),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
