import 'package:flutter/material.dart';

import 'FolkColors.dart';
import 'FolkTokens.dart';

// Type scale: Bricolage Grotesque for headings and numbers (700, -0.02em),
// DM Sans for everything else. Sizes from the README / design files.
@immutable
class FolkTypography {
  const FolkTypography(this.colors);

  final FolkColors colors;

  TextStyle _heading(double size, Color color,
      {FontWeight weight = FontWeight.w700, double tracking = -.02}) {
    return TextStyle(
      fontFamily: FolkFonts.heading,
      fontFamilyFallback: FolkFonts.fallback,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size * tracking,
      color: color,
    );
  }

  TextStyle _body(double size, Color color,
      {FontWeight weight = FontWeight.w400, double? height}) {
    return TextStyle(
      fontFamily: FolkFonts.body,
      fontFamilyFallback: FolkFonts.fallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
    );
  }

  TextStyle get screenTitle => _heading(34, colors.text);
  TextStyle get topBarTitle => _heading(20, colors.text);
  TextStyle get cardTitle => _heading(20, FolkColors.onGradient);
  // The title on every Insights tile: one size for all five, never scaled to fit.
  TextStyle get tileTitle => _heading(18, FolkColors.onGradient);
  TextStyle get bigStat => _heading(44, FolkColors.onGradient);
  TextStyle get stat => _heading(28, FolkColors.onGradient);
  TextStyle get statSmall => _heading(26, FolkColors.onGradient);
  // The label that breaks a section divider (ABCDE, MODULES): Bricolage,
  // upper-case at the call site, widely letter-spaced.
  TextStyle get sectionLabel =>
      _heading(13, colors.text, weight: FontWeight.w600, tracking: .18);
  TextStyle get japaCount => _heading(FolkJapaTokens.countSize, colors.text);
  TextStyle get messageText => _heading(19, FolkColors.onGradient,
      weight: FontWeight.w500, tracking: -.01);

  TextStyle get body => _body(15, colors.text);
  TextStyle get bodyStrong => _body(15, colors.text, weight: FontWeight.w700);
  TextStyle get small => _body(13, colors.mutedText);
  TextStyle get caption => _body(12, colors.mutedText);
  TextStyle get onGradientSmall =>
      _body(13, FolkColors.onGradientSecondary);
  TextStyle get onGradientCaption =>
      _body(12, FolkColors.onGradientSecondary);
  TextStyle get button =>
      _body(16, colors.primaryFg, weight: FontWeight.w700);
  TextStyle get chip => _body(14, colors.text, weight: FontWeight.w700);
  TextStyle get navLabel => _body(14, colors.primaryFg, weight: FontWeight.w700);

  // Callers render the text upper-case; this is the style only.
  TextStyle get label => TextStyle(
        fontFamily: FolkFonts.body,
        fontFamilyFallback: FolkFonts.fallback,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 11 * .12,
        color: colors.mutedText,
      );
}
