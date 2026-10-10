import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/FolkTheme.dart';

// Transparent status bar whose icons follow the Folk theme: dark icons on the
// light page, light icons on the dark page. Wrap a screen's Scaffold with it.
class FolkStatusBar extends StatelessWidget {
  const FolkStatusBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.folk.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: child,
    );
  }
}
