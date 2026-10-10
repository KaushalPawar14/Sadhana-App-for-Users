import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/FolkTokens.dart';
import '../utils/CompetitionRules.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/Group2Widgets.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';

class AchievementsPage extends StatefulWidget {
  final String username;
  const AchievementsPage({super.key, required this.username});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage>
    with SingleTickerProviderStateMixin {
  final firestore = FirebaseFirestore.instance;
  late AnimationController _controller;

  /// 🔥 FETCH BADGES FROM USERS COLLECTION USING 'name' FIELD
  Future<Map<String, int>> fetchBadges() async {
    final query = await firestore
        .collection("users")
        .where("name", isEqualTo: widget.username)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      // If no user found, return zeros
      return {
        "gold_badge": 0,
        "silver_badge": 0,
        "bronze_badge": 0,
        "weekly_winner": 0,
      };
    }

    final data = query.docs.first.data();

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
    return FolkScaffold(
      title: "Achievements",
      onBack: () => Navigator.pop(context),
      body: FutureBuilder<Map<String, int>>(
        future: fetchBadges(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            // Ghost badge cards while the counts load.
            return const GhostScope(
              child: Padding(
                padding: EdgeInsets.all(FolkSpace.pagePadding),
                child: Row(
                  children: [
                    Expanded(
                        child: GhostPlaceholder(
                            height: 220, showBars: false)),
                    SizedBox(width: FolkSpace.cardGap),
                    Expanded(
                        child: GhostPlaceholder(
                            height: 220, showBars: false)),
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

          return SingleChildScrollView(
            padding: const EdgeInsets.only(top: FolkSpace.lg, bottom: 32),
            child: Column(
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: FolkSpace.pagePadding),
                  child: PrimaryButton(
                    label: "View Sadhana Rules 📿",
                    onPressed: () {
                      showSadhanaRulesDialog(context);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
