import 'dart:math' as math;

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

// The strip under the title bar: "Chapter 7 of 30" between a previous and a next
// chapter arrow and, when a bookmark exists, where it is. Each arrow is a 48 dp
// target, faded when there is nowhere to go (the first / last chapter); while the
// next chapter is still being read in the background the right arrow shows a small
// spinner. The label wraps onto a second line at large text sizes.
class ReaderChapterStrip extends StatelessWidget {
  const ReaderChapterStrip({
    super.key,
    required this.background,
    required this.textColor,
    required this.chapterLabel,
    this.bookmarkLabel,
    this.onPrevious,
    this.onNext,
    this.nextLoading = false,
    this.previousTooltip = 'Previous chapter',
    this.nextTooltip = 'Next chapter',
  });

  final Color background;
  final Color textColor;
  final String chapterLabel;
  final String? bookmarkLabel;

  /// Null = there is no previous / next chapter (the arrow is faded and inert).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// True while the next chapter is not read yet: a small spinner, not tappable.
  final bool nextLoading;
  final String previousTooltip;
  final String nextTooltip;

  static const double arrowSize = 48;

  Widget _arrow(IconData icon, String tooltip, VoidCallback? onTap,
      {bool loading = false}) {
    final enabled = onTap != null && !loading;
    return SizedBox(
      width: arrowSize,
      height: arrowSize,
      child: loading
          ? Semantics(
              label: 'Loading next chapter',
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: textColor),
                ),
              ),
            )
          : Opacity(
              opacity: enabled ? 1 : .3,
              child: IconButton(
                tooltip: tooltip,
                iconSize: 28,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                    width: arrowSize, height: arrowSize),
                icon: Icon(icon, color: textColor),
                onPressed: onTap,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: arrowSize),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      color: background,
      child: Row(
        children: [
          _arrow(Icons.chevron_left_rounded, previousTooltip, onPrevious),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    chapterLabel,
                    textAlign: TextAlign.center,
                    style: text.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  if (bookmarkLabel != null)
                    ReaderPill(label: bookmarkLabel!, icon: Icons.bookmark),
                ],
              ),
            ),
          ),
          _arrow(Icons.chevron_right_rounded, nextTooltip, onNext,
              loading: nextLoading),
        ],
      ),
    );
  }
}

// The slim bar fixed to the bottom of the reader: how much of the CURRENT chapter
// has been read (the scroll position, 0-100 %), with a small percentage label. The
// fill follows the scroll smoothly (no animation under "reduce motion").
class ReaderProgressBar extends StatelessWidget {
  const ReaderProgressBar({
    super.key,
    required this.progress,
    required this.background,
    required this.textColor,
    required this.trackColor,
    required this.fontScale,
  });

  /// 0.0 - 1.0.
  final double progress;
  final Color background;
  final Color textColor;
  final Color trackColor;
  final double fontScale;

  static const double _vertical = 8;

  /// The bar's content height for a reader text scale: tall enough for the label.
  /// The reader pads its page by this plus the system inset below the bar.
  static double contentHeightFor(double fontScale) =>
      math.max(32, 11 * fontScale * 1.4 + 2 * _vertical);

  static int percentOf(double progress) =>
      progress >= .995 ? 100 : (progress * 100).floor().clamp(0, 99);

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final p = progress.clamp(0.0, 1.0);
    final percent = percentOf(p);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final duration = FolkMotion.of(context, const Duration(milliseconds: 120));
    return Semantics(
      label: 'Chapter progress',
      value: '$percent percent',
      child: Container(
        height: contentHeightFor(fontScale) + bottomInset,
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset),
        decoration: BoxDecoration(
          color: background,
          border: Border(top: BorderSide(color: trackColor, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: trackColor),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: p),
                          duration: duration,
                          curve: Curves.easeOut,
                          builder: (context, value, _) => FractionallySizedBox(
                            widthFactor: value.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: const DecoratedBox(
                              decoration:
                                  BoxDecoration(gradient: FolkGradients.violet),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 11 * fontScale * 3.0,
              child: Text(
                '$percent%',
                textAlign: TextAlign.right,
                maxLines: 1,
                style: text.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
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
