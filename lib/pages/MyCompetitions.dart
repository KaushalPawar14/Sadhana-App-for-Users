import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/SectionDivider.dart';
import '../utils/CompetitionDots.dart';
import 'Achievements.dart';
import 'ChantingCompetition.dart';

// "My Competitions": one continuous scroll. The chanting competition first (idle,
// active with progress and contributors, or its result: exactly what the
// Chanting Competition page showed), then an ACHIEVEMENTS divider, the badges, and
// the "View Sadhana Rules" button.
class MyCompetitionsPage extends StatefulWidget {
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
  State<MyCompetitionsPage> createState() => _MyCompetitionsPageState();
}

class _MyCompetitionsPageState extends State<MyCompetitionsPage> {
  StreamSubscription<Set<String>>? _sub;

  /// What was new when he opened this page (and what arrives while he is on it): the competition's card keeps its dot while he is here, so he sees which one is new;
  /// when he leaves, all of it is seen.
  final Set<String> _shown = {};
  late final CompetitionDots? _dots = CompetitionDots.forCurrentUser();

  @override
  void initState() {
    super.initState();
    _sub = _dots?.unseenKeysStream().listen((keys) => _shown.addAll(keys), onError: (Object _) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dots?.markSeen(_shown);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.username;
    final chantingSection = widget.chantingSection;
    final badgesLoader = widget.badgesLoader;
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
