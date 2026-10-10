import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkPageBackground.dart';
import 'FolkStatusBar.dart';
import 'RoundIconButton.dart';

// The page shell for a screen that is pushed on top of the tabs: the page
// background with its top fade, a round back button, a centred title and any
// action buttons on the right, then [body]. It replaces a Scaffold + AppBar;
// "back" is the same pop the AppBar's own back arrow did.
//
// [bottom] sits right under the title bar (for a tab bar or a search field).
class FolkScaffold extends StatelessWidget {
  const FolkScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.bottom,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
    this.onBack,
    this.showBack = true,
    this.backIcon = Icons.chevron_left_rounded,
    this.backLabel = 'Back',
  });

  final String title;
  final Widget body;

  // Round buttons (usually `RoundIconButton`s) shown at the right of the bar.
  final List<Widget> actions;
  final Widget? bottom;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;

  // What the back button does; defaults to popping this route.
  final VoidCallback? onBack;
  final bool showBack;

  // The leading button's glyph and spoken label (a voice room minimizes with a
  // down arrow, for example).
  final IconData backIcon;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    return FolkStatusBar(
      child: Scaffold(
        backgroundColor: colors.pageBackground,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: FolkPageBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding,
                      FolkSpace.xl, FolkSpace.pagePadding, 0),
                  child: Row(
                    children: [
                      if (showBack)
                        RoundIconButton(
                          icon: backIcon,
                          iconSize: 26,
                          semanticLabel: backLabel,
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
                        )
                      else
                        const SizedBox(width: FolkShape.touchTarget),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.folkText.topBarTitle,
                        ),
                      ),
                      if (actions.isEmpty)
                        const SizedBox(width: FolkShape.touchTarget)
                      else
                        Row(mainAxisSize: MainAxisSize.min, children: actions),
                    ],
                  ),
                ),
                if (bottom != null) bottom!,
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
