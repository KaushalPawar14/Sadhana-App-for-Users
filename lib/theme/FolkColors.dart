import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// Light and dark palettes as a ThemeExtension, so switching theme cross-fades
// every token-driven colour. Values from design/extracted/*_Light|_Dark.html.
@immutable
class FolkColors extends ThemeExtension<FolkColors> {
  const FolkColors({
    required this.isDark,
    required this.pageBackground,
    required this.fadeBase,
    required this.fadeStrongAlpha,
    required this.fadeMidAlpha,
    required this.surface,
    required this.surfaceSecondary,
    required this.text,
    required this.mutedText,
    required this.primaryBg,
    required this.primaryFg,
    required this.switchOff,
    required this.disabledText,
    required this.cardShadow,
    required this.iconShadow,
    required this.navShadow,
    required this.ghostBase,
    required this.chartBarInactive,
    required this.calendarMissedBg,
    required this.calendarMissedText,
    required this.japaRingTrack,
  });

  final bool isDark;
  final Color pageBackground;
  final Color fadeBase;
  final double fadeStrongAlpha;
  final double fadeMidAlpha;
  final Color surface;
  final Color surfaceSecondary;
  final Color text;
  final Color mutedText;
  final Color primaryBg;
  final Color primaryFg;
  final Color switchOff;
  final Color disabledText;
  final Color cardShadow;
  final Color iconShadow;
  final Color navShadow;
  final Color ghostBase;
  final Color chartBarInactive;
  final Color calendarMissedBg;
  final Color calendarMissedText;
  final Color japaRingTrack;

  // Gradient widgets look the same in both themes and always use this text.
  static const Color onGradient = Color(0xFF1E1B2E);
  static const Color onGradientSecondary = Color.fromRGBO(30, 27, 46, .78);
  static const Color onGradientIconTile = Color.fromRGBO(255, 255, 255, .6);

  // Podcast: the round play button on the highlighted (saffron) episode, and
  // the unfilled part of the mini-player's progress bar. Same in both themes.
  // The Log Out button: a filled red, the same in light and dark, with white text and
  // icon. #C62828 against white is 5.62:1 (WCAG AA needs 4.5:1 for text).
  static const Color logoutRed = Color(0xFFC62828);
  static const Color onLogoutRed = Color(0xFFFFFFFF);

  static const Color gradientPlayButton = Color(0xFFFFFFFE);

  // Profile menu: the icon tile behind each row's icon. The dark theme's
  // secondary surface, used in BOTH themes so the golden icon (`FolkGradients
  // .profileMenuIcon`) is always on the same dark tile.
  static const Color profileIconTile = Color(0xFF2E2E32);
  static const Color miniPlayerTrack = Color.fromRGBO(128, 128, 128, .35);

  static const FolkColors light = FolkColors(
    isDark: false,
    pageBackground: Color(0xFFF8F7FC),
    fadeBase: Color(0xFFD4C6FF),
    fadeStrongAlpha: .75,
    fadeMidAlpha: .30,
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF3EDE4),
    text: Color(0xFF1E1B2E),
    mutedText: Color(0xFF6B6880),
    primaryBg: Color(0xFF1E1B2E),
    primaryFg: Color(0xFFFBF7F2),
    switchOff: Color(0xFFE5DED4),
    disabledText: Color(0xFFA9A5B8),
    cardShadow: Color.fromRGBO(80, 50, 20, .08),
    iconShadow: Color.fromRGBO(80, 50, 20, .10),
    navShadow: Color.fromRGBO(60, 40, 20, .16),
    ghostBase: Color(0xFF1E1B2E),
    chartBarInactive: Color(0xFFEEE8FA),
    calendarMissedBg: Color(0xFFFFDAD6),
    calendarMissedText: Color(0xFFA3271E),
    japaRingTrack: Color(0xFFEDE5DA),
  );

  static const FolkColors dark = FolkColors(
    isDark: true,
    pageBackground: Color(0xFF151517),
    fadeBase: Color(0xFF50C88C),
    fadeStrongAlpha: .20,
    fadeMidAlpha: .07,
    surface: Color(0xFF222225),
    surfaceSecondary: Color(0xFF2E2E32),
    text: Color(0xFFF4F1EC),
    mutedText: Color(0xFFA09DA5),
    primaryBg: Color(0xFFF4F1EC),
    primaryFg: Color(0xFF151517),
    switchOff: Color(0xFF3C3C41),
    disabledText: Color(0xFF66646C),
    cardShadow: Color.fromRGBO(0, 0, 0, .08),
    iconShadow: Color.fromRGBO(0, 0, 0, .10),
    navShadow: Color.fromRGBO(0, 0, 0, .16),
    ghostBase: Color(0xFFF4F1EC),
    chartBarInactive: Color(0xFF34343A),
    calendarMissedBg: Color(0xFF4A2428),
    calendarMissedText: Color(0xFFFF9B93),
    japaRingTrack: Color(0xFF2E2E32),
  );

  // The top fade is 340 dp tall: strong at 0, mid at 150 dp, clear at 340 dp.
  static const double fadeHeight = 340;
  static const double _fadeMidStop = 150 / 340;

  LinearGradient get topFade => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fadeBase.withValues(alpha: fadeStrongAlpha),
          fadeBase.withValues(alpha: fadeMidAlpha),
          fadeBase.withValues(alpha: 0),
        ],
        stops: const [0, _fadeMidStop, 1],
      );

  // Smoothness pass: the card and icon shadows sit under many items in
  // scrolling lists, and a blur is paid per item per frame, so they are
  // lighter than before (card 28 -> 16 dp blur, icon 18 -> 12 dp). The single
  // floating nav pill keeps its larger one.
  List<BoxShadow> get cardShadows => [
        BoxShadow(color: cardShadow, blurRadius: 16, offset: const Offset(0, 5)),
      ];

  List<BoxShadow> get iconShadows => [
        BoxShadow(color: iconShadow, blurRadius: 12, offset: const Offset(0, 4)),
      ];

  List<BoxShadow> get navShadows => [
        BoxShadow(color: navShadow, blurRadius: 32, offset: const Offset(0, 12)),
      ];

  @override
  FolkColors copyWith({
    bool? isDark,
    Color? pageBackground,
    Color? fadeBase,
    double? fadeStrongAlpha,
    double? fadeMidAlpha,
    Color? surface,
    Color? surfaceSecondary,
    Color? text,
    Color? mutedText,
    Color? primaryBg,
    Color? primaryFg,
    Color? switchOff,
    Color? disabledText,
    Color? cardShadow,
    Color? iconShadow,
    Color? navShadow,
    Color? ghostBase,
    Color? chartBarInactive,
    Color? calendarMissedBg,
    Color? calendarMissedText,
    Color? japaRingTrack,
  }) {
    return FolkColors(
      isDark: isDark ?? this.isDark,
      pageBackground: pageBackground ?? this.pageBackground,
      fadeBase: fadeBase ?? this.fadeBase,
      fadeStrongAlpha: fadeStrongAlpha ?? this.fadeStrongAlpha,
      fadeMidAlpha: fadeMidAlpha ?? this.fadeMidAlpha,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      primaryBg: primaryBg ?? this.primaryBg,
      primaryFg: primaryFg ?? this.primaryFg,
      switchOff: switchOff ?? this.switchOff,
      disabledText: disabledText ?? this.disabledText,
      cardShadow: cardShadow ?? this.cardShadow,
      iconShadow: iconShadow ?? this.iconShadow,
      navShadow: navShadow ?? this.navShadow,
      ghostBase: ghostBase ?? this.ghostBase,
      chartBarInactive: chartBarInactive ?? this.chartBarInactive,
      calendarMissedBg: calendarMissedBg ?? this.calendarMissedBg,
      calendarMissedText: calendarMissedText ?? this.calendarMissedText,
      japaRingTrack: japaRingTrack ?? this.japaRingTrack,
    );
  }

  @override
  FolkColors lerp(ThemeExtension<FolkColors>? other, double t) {
    if (other is! FolkColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return FolkColors(
      isDark: t < .5 ? isDark : other.isDark,
      pageBackground: c(pageBackground, other.pageBackground),
      fadeBase: c(fadeBase, other.fadeBase),
      fadeStrongAlpha: lerpDouble(fadeStrongAlpha, other.fadeStrongAlpha, t)!,
      fadeMidAlpha: lerpDouble(fadeMidAlpha, other.fadeMidAlpha, t)!,
      surface: c(surface, other.surface),
      surfaceSecondary: c(surfaceSecondary, other.surfaceSecondary),
      text: c(text, other.text),
      mutedText: c(mutedText, other.mutedText),
      primaryBg: c(primaryBg, other.primaryBg),
      primaryFg: c(primaryFg, other.primaryFg),
      switchOff: c(switchOff, other.switchOff),
      disabledText: c(disabledText, other.disabledText),
      cardShadow: c(cardShadow, other.cardShadow),
      iconShadow: c(iconShadow, other.iconShadow),
      navShadow: c(navShadow, other.navShadow),
      ghostBase: c(ghostBase, other.ghostBase),
      chartBarInactive: c(chartBarInactive, other.chartBarInactive),
      calendarMissedBg: c(calendarMissedBg, other.calendarMissedBg),
      calendarMissedText: c(calendarMissedText, other.calendarMissedText),
      japaRingTrack: c(japaRingTrack, other.japaRingTrack),
    );
  }
}
