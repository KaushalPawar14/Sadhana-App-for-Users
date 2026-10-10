import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../utils/BottomNavBar.dart' show hostHeader, hostNavItems;
import 'FloatingPillNavBar.dart';
import 'FolkPageBackground.dart';
import 'FolkStatusBar.dart';
import 'NavHostGhost.dart';

// What is drawn from the moment the app starts until it knows where to go (the
// wait for the student's profile). No spinner anywhere:
//
//  - signed in: the tab host's own loading frame, so the ghost that follows inside
//    the tab host is the same picture and nothing visibly switches: the page
//    background, room for the title bar (not drawn: the host's title fades in by
//    itself there), `NavHostGhost` (the Sadhana tab's ghost), and the pill
//    navigation, which cannot be tapped yet;
//  - signed out: just the themed page background, until the welcome page appears.
class StartupWaiting extends StatelessWidget {
  const StartupWaiting({super.key, required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    if (!signedIn) {
      return Scaffold(backgroundColor: colors.pageBackground);
    }
    return FolkStatusBar(
      child: Scaffold(
        extendBody: true,
        backgroundColor: colors.pageBackground,
        body: FolkPageBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // The title bar's room, kept but not drawn (the Sadhana tab is
                // the one the host opens on).
                ExcludeSemantics(
                  child: Visibility(
                    visible: false,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: hostHeader(context, 2),
                  ),
                ),
                Expanded(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.paddingOf(context).copyWith(bottom: 0),
                    ),
                    child: const NavHostGhost(),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: IgnorePointer(
          child: FloatingPillNavBar(
            currentIndex: 2,
            items: hostNavItems(context),
            onTap: (_) {},
          ),
        ),
      ),
    );
  }
}
