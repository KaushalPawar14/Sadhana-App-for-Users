import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';
import '../theme/FolkTheme.dart';
import 'FloatingPillNavBar.dart';
import 'GhostPlaceholder.dart';
import 'PrimaryButton.dart';
import 'SadhanaDayCell.dart';

// What the tab host shows while it reads the student's name and role: the
// Sadhana tab's own ghost (the calendar card and the submit button), so the
// swap into that tab's loading state moves nothing. It shows no spinner.
class NavHostGhost extends StatelessWidget {
  const NavHostGhost({super.key});

  @override
  Widget build(BuildContext context) {
    final rowHeight = MediaQuery.of(context).size.width * 0.12;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          FolkSpace.pagePadding,
          FolkSpace.sm,
          FolkSpace.pagePadding,
          20 + FloatingPillNavBar.reservedHeight(context)),
      child: GhostScope(
        child: Column(
          children: [
            SadhanaCalendarGhost(month: DateTime.now(), rowHeight: rowHeight),
            const SizedBox(height: 20),
            const SizedBox(height: 0),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: GhostPlaceholder(
                width: double.infinity,
                height: FolkShape.buttonHeight,
                radius: FolkShape.buttonRadius,
                showBars: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// What the tab host shows when it could not read the student's profile: a short
// message and a Retry button, in place of the ghost that would otherwise stay
// on screen for good.
class NavHostError extends StatelessWidget {
  const NavHostError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            FolkSpace.pagePadding,
            FolkSpace.xxl,
            FolkSpace.pagePadding,
            FolkSpace.xxl + FloatingPillNavBar.reservedHeight(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: colors.mutedText),
            const SizedBox(height: FolkSpace.lg),
            Text(
              "Couldn't load your profile",
              textAlign: TextAlign.center,
              style: text.topBarTitle,
            ),
            const SizedBox(height: FolkSpace.sm),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: text.small,
            ),
            const SizedBox(height: FolkSpace.xl),
            PrimaryButton(label: 'Retry', onPressed: onRetry, expanded: false),
          ],
        ),
      ),
    );
  }
}
