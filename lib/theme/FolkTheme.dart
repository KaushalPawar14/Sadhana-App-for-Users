import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'FolkColors.dart';
import 'FolkTypography.dart';

// The Material base stays as it is today (light, Satoshi) until each screen is
// restyled: unmocked screens still draw from ColorProvider and hard-coded
// colours, so flipping Material's own brightness now would change them. The new
// look comes from the FolkColors extension, which differs between the two.
abstract final class FolkTheme {
  // The colour a page transition paints behind the pages while one opens or closes.
  //
  // ⚠️ Root cause of the white flash when a screen is opened in dark mode (the AI History page, and every
  // other pushed screen): Flutter's page transitions (Android: PredictiveBack -> FadeForwards, ~0.8 s; the
  // other platforms' too) paint a scrim of `ColorScheme.surface` under the pages
  // (flutter/lib/src/material/page_transitions_theme.dart: `backgroundColor ?? ColorScheme.of(context).surface`).
  // This app keeps Material's own brightness LIGHT in both themes (see above), so that surface is white even
  // in dark mode. Every route therefore starts with a white frame behind its fade. The scrim is now the
  // app's own page background in each theme, so the very first frame is already the right colour.
  static PageTransitionsTheme _transitions(Color scrim) => PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(fallbackColor: scrim),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(backgroundColor: scrim),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(backgroundColor: scrim),
        },
      );

  static final ThemeData light = ThemeData(
    fontFamily: 'Satoshi',
    extensions: const <ThemeExtension<dynamic>>[FolkColors.light],
    pageTransitionsTheme: _transitions(FolkColors.light.pageBackground),
  );

  static final ThemeData dark = ThemeData(
    fontFamily: 'Satoshi',
    extensions: const <ThemeExtension<dynamic>>[FolkColors.dark],
    pageTransitionsTheme: _transitions(FolkColors.dark.pageBackground),
  );
}

extension FolkThemeContext on BuildContext {
  FolkColors get folk =>
      Theme.of(this).extension<FolkColors>() ?? FolkColors.light;

  FolkTypography get folkText => FolkTypography(folk);
}
