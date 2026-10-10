import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// Controls around the book reader's page. The reading surface itself (page
// colours, text, paragraphs) is NOT here — only the chrome. Every colour that
// has to sit on the reader's own palette (light / dark / sepia) is passed in;
// the rest are gradients with ink text, which read on all three.

// A small gradient pill (a status or hint).
class ReaderPill extends StatelessWidget {
  const ReaderPill({
    super.key,
    required this.label,
    this.gradient = FolkGradients.violet,
    this.icon,
    this.fontSize = 11,
  });

  final String label;
  final LinearGradient gradient;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: FolkColors.onGradient),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: text.caption.copyWith(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: FolkColors.onGradient,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The strip under the title bar: "Chapter 2 of 9" and, when a bookmark exists,
// where it is. It wraps onto a second line at large text sizes.
class ReaderChapterStrip extends StatelessWidget {
  const ReaderChapterStrip({
    super.key,
    required this.background,
    required this.textColor,
    required this.chapterLabel,
    this.bookmarkLabel,
  });

  final Color background;
  final Color textColor;
  final String chapterLabel;
  final String? bookmarkLabel;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: background,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            chapterLabel,
            style: text.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          if (bookmarkLabel != null)
            ReaderPill(label: bookmarkLabel!, icon: Icons.bookmark),
        ],
      ),
    );
  }
}

// A full-width gradient button (Next Chapter / Finish Book / Mark as Read).
// At least 56 dp tall; grows with the label at large text sizes.
class ReaderGradientButton extends StatelessWidget {
  const ReaderGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.gradient,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final LinearGradient gradient;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(FolkShape.buttonRadius);
    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        enabled: enabled,
        child: Opacity(
          opacity: enabled || loading ? 1 : .45,
          child: Container(
            decoration: BoxDecoration(gradient: gradient, borderRadius: radius),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: radius,
              child: InkWell(
                borderRadius: radius,
                onTap: onPressed,
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: FolkShape.buttonHeight),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (loading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: FolkColors.onGradient,
                          ),
                        )
                      else if (icon != null) ...[
                        Icon(icon, size: 20, color: FolkColors.onGradient),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: text.button
                              .copyWith(color: FolkColors.onGradient),
                        ),
                      ),
                    ],
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
