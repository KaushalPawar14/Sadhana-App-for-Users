import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

// Design tokens. Values come from design/extracted/*.html (HTML wins over PNG).

abstract final class FolkFonts {
  static const String heading = 'Bricolage Grotesque';
  static const String body = 'DM Sans';
  // Used until the font files are bundled, so new components never fall back
  // to the platform default.
  static const List<String> fallback = ['Satoshi'];
}

abstract final class FolkShape {
  static const double cardRadius = 28;
  static const double tileRadius = 24;
  static const double chipHeight = 40;
  static const double chipHeightLarge = 44;
  static const double buttonHeight = 56;
  static const double buttonRadius = 28;
  static const double iconButtonSize = 44;
  static const double touchTarget = 48;
  static const double navHeight = 68;
  static const double navRadius = 34;
  static const double navInset = 20;
  static const double miniPlayerHeight = 64;
  static const double miniPlayerRadius = 32;
  static const double messageBubbleRadius = 22;
}

abstract final class FolkSpace {
  static const double pagePadding = 20;
  static const double cardGap = 12;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

abstract final class FolkMotion {
  static const Duration press = Duration(milliseconds: 130);
  static const double pressScale = 0.97;
  static const Duration entry = Duration(milliseconds: 300);
  static const Duration entryStagger = Duration(milliseconds: 50);
  static const double entryOffset = 14;
  static const Duration navMorph = Duration(milliseconds: 250);
  static const Duration theme = Duration(milliseconds: 300);
  static const Duration ghostPulse = Duration(milliseconds: 1800);
  static const Duration ghostCrossFade = Duration(milliseconds: 250);
  static const Duration countUp = Duration(milliseconds: 600);
  static const Duration ripple = Duration(milliseconds: 400);
  static const Duration japaIdle = Duration(milliseconds: 3000);
  static const Duration ringFill = Duration(milliseconds: 300);
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve out = Curves.easeOutCubic;

  // The one place the "reduce animations" setting is read. Above the app's
  // MaterialApp there is no MediaQuery yet, so it falls back to the platform.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ??
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  static Duration of(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}

enum FolkGradientStyle { green, violet, saffron, coral, warm, sky, slate }

// Which feature wears which gradient (the approved table, second review
// 2026-10-09):
//   saffron  Expeditions, RDUA Friends, ranking and recognition
//   green    Association, Devotional Service, Insights "Weekly Performance"
//   coral    Chanting, Podcast Modules, Insights "Monthly Performance"
//   violet   Books, RDUA Modules, Insights "Want to improve?", learning and insight
//   warm     the Service Bank's "nuance" notes (and the gold medal's tones)
//   sky      Today's message (Journey, Ask, History, the preparing banner) and the
//            Profile name card
// Screens read their gradient from here, never a style of their own.
abstract final class FolkFeatureGradients {
  static const FolkGradientStyle association = FolkGradientStyle.green;
  static const FolkGradientStyle books = FolkGradientStyle.violet;
  static const FolkGradientStyle chanting = FolkGradientStyle.coral;
  static const FolkGradientStyle devotionalService = FolkGradientStyle.green;
  static const FolkGradientStyle expeditions = FolkGradientStyle.saffron;
  static const FolkGradientStyle rduaModules = FolkGradientStyle.violet;
  static const FolkGradientStyle rduaFriends = FolkGradientStyle.saffron;
  static const FolkGradientStyle podcastModules = FolkGradientStyle.coral;
  static const FolkGradientStyle weeklyPerformance = FolkGradientStyle.green;
  static const FolkGradientStyle monthlyPerformance = FolkGradientStyle.coral;
  static const FolkGradientStyle bestPerformer = FolkGradientStyle.violet;
}

abstract final class FolkGradients {
  static const Alignment _from = Alignment.topLeft;
  static const Alignment _to = Alignment.bottomRight;

  static const LinearGradient green = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFFC4EED8), Color(0xFF82D3A8)]);
  static const LinearGradient violet = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFFDDD2FF), Color(0xFFAE95F7)]);
  static const LinearGradient saffron = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFFFFE48F), Color(0xFFFFB65A)]);
  static const LinearGradient coral = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFFFFCFC6), Color(0xFFFF9E98)]);
  static const LinearGradient warm = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFFFFE9B8), Color(0xFFFFC978)]);

  // The book reader's DOUBT category (Notes -> Doubts): a balanced cool gray, the same in light and dark. The text on it
  // is `FolkColors.onGradient`.
  static const LinearGradient slate = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFFE6E9EE), Color(0xFFB4BBC6)]);

  // Today's message and the Profile name card: sky blue, the same in light and
  // dark (#CDE8FF -> #8EC5F5, 135 degrees). The text on it is `FolkColors.onGradient`.
  static const LinearGradient sky = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFFCDE8FF), Color(0xFF8EC5F5)]);

  // Profile menu icons: the saffron gradient (#FFE48F -> #FFB65A) painted on
  // the icon itself, the same in both themes. See `FolkColors.profileIconTile`.
  static const LinearGradient profileMenuIcon = saffron;

  // The "Submit Sadhana" button: the violet gradient in BOTH modes. Its text and
  // icon are always `FolkColors.onGradient`.
  static const LinearGradient submitSadhana = violet;

  // Insights: today's bar (the others are `FolkColors.chartBarInactive`).
  static const LinearGradient insightToday = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFCB7A), Color(0xFFFFA94D)],
  );

  static LinearGradient of(FolkGradientStyle style) => switch (style) {
        FolkGradientStyle.green => green,
        FolkGradientStyle.violet => violet,
        FolkGradientStyle.saffron => saffron,
        FolkGradientStyle.coral => coral,
        FolkGradientStyle.warm => warm,
        FolkGradientStyle.sky => sky,
        FolkGradientStyle.slate => slate,
      };

  // Sadhana calendar: a submitted day.
  static const LinearGradient calendarSubmitted = LinearGradient(
    begin: _from, end: _to, colors: [Color(0xFF8FE0A8), Color(0xFF4FBF7F)]);

  // Insights: the highlighted bar.
  static const LinearGradient chartBarHighlight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFCB7A), Color(0xFFFFA94D)]);

  // Japa: the tap circle (SVG radialGradient cx 50% cy 38% r 70%).
  static const RadialGradient japaTap = RadialGradient(
    center: Alignment(0, -0.24),
    radius: 0.7,
    colors: [Color(0xFFFFF1C9), Color(0xFFFFC873)]);
}

abstract final class FolkCalendarTokens {
  static const Color legendSubmitted = Color(0xFF4FBF7F);
  static const Color legendMissed = Color(0xFFE5584B);

  // The ring around the day the student has tapped (the violet of the
  // gradient family, so it never reads as a status colour).
  static const Color selectedRing = Color(0xFFAE95F7);
  static const double dayCircle = 40;
}

abstract final class FolkJapaTokens {
  static const double tapBox = 272;
  static const double ringRadius = 128;
  static const double ringWidth = 8;
  static const double tapRadius = 110;
  static const Color ringProgress = Color(0xFFF59E0B);
  static const Color onTap = Color(0xFF1E1B2E);
  static const Color onTapSecondary = Color(0xFF4A4760);
  static const double countSize = 96;

  // The 30-day strip: darker green for more rounds that day.
  static const Color heat8 = Color(0xFF1B5E20);
  static const Color heat5 = Color(0xFF388E3C);
  static const Color heat3 = Color(0xFF66BB6A);
  static const Color heat1 = Color(0xFFA5D6A7);
}
