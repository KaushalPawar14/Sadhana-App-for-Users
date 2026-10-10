import 'package:flutter/material.dart';

import 'FolkColors.dart';
import 'FolkTypography.dart';

// The Material base stays as it is today (light, Satoshi) until each screen is
// restyled: unmocked screens still draw from ColorProvider and hard-coded
// colours, so flipping Material's own brightness now would change them. The new
// look comes from the FolkColors extension, which differs between the two.
abstract final class FolkTheme {
  static final ThemeData light = ThemeData(
    fontFamily: 'Satoshi',
    extensions: const <ThemeExtension<dynamic>>[FolkColors.light],
  );

  static final ThemeData dark = ThemeData(
    fontFamily: 'Satoshi',
    extensions: const <ThemeExtension<dynamic>>[FolkColors.dark],
  );
}

extension FolkThemeContext on BuildContext {
  FolkColors get folk =>
      Theme.of(this).extension<FolkColors>() ?? FolkColors.light;

  FolkTypography get folkText => FolkTypography(folk);
}
