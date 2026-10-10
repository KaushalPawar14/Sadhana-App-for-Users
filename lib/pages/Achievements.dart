import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import '../theme/FolkTokens.dart';
import '../utils/CompetitionRules.dart';
import '../widgets/Group2Widgets.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';

// The badges and the Sadhana rules button: the second part of "My Competitions".
// The same badge cards in the same horizontal scroll, the same one read of the
// student's own counts, the same ghost while it loads and the same rules dialog.
class AchievementsSection extends StatefulWidget {
  // The student's name (their `users` document is found by it). Empty: the
  // student's own document, by uid.
  final String username;

  // Tests hand in their own counts; the app never sets it.
  @visibleForTesting
  final Future<Map<String, int>> Function()? badgesLoader;

  const AchievementsSection(
      {super.key, required this.username, this.badgesLoader});

  @override
  State<AchievementsSection> createState() => _AchievementsSectionState();
}

class _AchievementsSectionState extends State<AchievementsSection>
    with SingleTickerProviderStateMixin {
  // Looked up only when the counts are read, so a test's own counts never need Firebase.
  FirebaseFirestore get firestore => FirebaseFirestore.instance;
  late AnimationController _controller;
  late final Future<Map<String, int>> _badges =
      (widget.badgesLoader ?? fetchBadges)();

  /// 🔥 FETCH BADGES FROM USERS COLLECTION USING 'name' FIELD
  Future<Map<String, int>> fetchBadges() async {
    Map<String, dynamic>? data;
    if (widget.username.isNotEmpty) {
      final query = await firestore
          .collection("users")
          .where("name", isEqualTo: widget.username)
          .limit(1)
          .get();
      data = query.docs.isEmpty ? null : query.docs.first.data();
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        data = (await firestore.collection("users").doc(uid).get()).data();
      }
    }

    // If no user found, zeros
    if (data == null) {
      return {
        "gold_badge": 0,
        "silver_badge": 0,
        "bronze_badge": 0,
        "weekly_winner": 0,
      };
    }

    return {
      "gold_badge": data["monthly-gold"] ?? 0,
      "silver_badge": data["monthly-silver"] ?? 0,
      "bronze_badge": data["monthly-bronze"] ?? 0,
      "weekly_winner": data["weekly-winner"] ?? 0,
    };
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 🔥 COMPACT BADGE CARD (TOP SECTION)
  Widget compactBadgeCard(String badgeName, int count, int index) {
    // The entrance is skipped under "reduce animations" (the count-up inside
    // the card honours it too).
    final reduced = FolkMotion.reduced(context);
    final card = AchievementBadgeCard(badgeName: badgeName, count: count);

    if (reduced) return card;
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Interval(0.1 * index, 1.0)),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(
              parent: _controller,
              curve: Interval(0.1 * index, 1.0, curve: Curves.easeOut)),
        ),
        child: card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _badges,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Ghost badge cards while the counts load.
          return const GhostScope(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: FolkSpace.pagePadding),
              child: Row(
                children: [
                  Expanded(
                      child: GhostPlaceholder(height: 220, showBars: false)),
                  SizedBox(width: FolkSpace.cardGap),
                  Expanded(
                      child: GhostPlaceholder(height: 220, showBars: false)),
                ],
              ),
            ),
          );
        }

        final badges = snapshot.data!;

        final badgeList = [
          {"name": "gold_badge", "count": badges["gold_badge"]!},
          {"name": "silver_badge", "count": badges["silver_badge"]!},
          {"name": "bronze_badge", "count": badges["bronze_badge"]!},
          {"name": "1st_badge", "count": badges["weekly_winner"]!},
        ];

        return Column(
          children: [
            /// 🔥 BADGES LIST (horizontal scroll)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < badgeList.length; index++)
                    compactBadgeCard(
                      badgeList[index]["name"] as String,
                      badgeList[index]["count"] as int,
                      index,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            /// 🔥 BUTTON
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: FolkSpace.pagePadding),
              child: PrimaryButton(
                label: "View Sadhana Rules 📿",
                onPressed: () {
                  showSadhanaRulesDialog(context);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
