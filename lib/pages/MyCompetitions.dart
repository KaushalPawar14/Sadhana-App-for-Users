import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/SectionDivider.dart';
import 'Achievements.dart';
import 'ChantingCompetition.dart';

// "My Competitions": one continuous scroll. The chanting competition first (idle,
// active with progress and contributors, or its result: exactly what the
// Chanting Competition page showed), then an ACHIEVEMENTS divider, the badges, and
// the "View Sadhana Rules" button.
class MyCompetitionsPage extends StatelessWidget {
  // The student's name, for the badge counts. Empty: found by their own uid.
  final String username;

  // Tests stand in for the two sections (which read Firestore); the app never
  // sets these.
  @visibleForTesting
  final Widget? chantingSection;
  @visibleForTesting
  final Future<Map<String, int>> Function()? badgesLoader;

  const MyCompetitionsPage(
      {super.key, this.username = '', this.chantingSection, this.badgesLoader});

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: "My Competitions",
      onBack: () => Navigator.pop(context),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          children: [
            chantingSection ?? const ChantingCompetitionSection(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: FolkSpace.pagePadding),
              child: SectionDivider(label: 'ACHIEVEMENTS'),
            ),
            AchievementsSection(username: username, badgesLoader: badgesLoader),
          ],
        ),
      ),
    );
  }
}
