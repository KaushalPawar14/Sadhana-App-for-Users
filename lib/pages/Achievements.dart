import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';
import '../utils/CompetitionRules.dart';
import '../utils/MalaLoading.dart';

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
  Widget compactBadgeCard(
      String badgeName, int count, Color textColor, int index) {
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
        child: Container(
          width: 170,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.25),
                Colors.white.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 1,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              /// Badge icon
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset("assets/images/$badgeName.png"),
                ),
              ),

              const SizedBox(height: 10),

              /// Badge name
              Text(
                badgeName.replaceAll("_", " ").toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 6),

              /// Count animation
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: count.toDouble()),
                duration: const Duration(milliseconds: 900),
                builder: (context, value, child) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: AppBar(
          title: Text(
            "Achievements",
            style: TextStyle(
              color: colorProvider.secondColor,
              fontWeight: FontWeight.bold,
              fontSize: 22.01,
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
            onPressed: () => Navigator.pop(context),
          ),
          backgroundColor: colorProvider.color,
          elevation: 0,
        ),
        body: FutureBuilder<Map<String, int>>(
          future: fetchBadges(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const CustomLoader();

            final badges = snapshot.data!;
            final textColor = colorProvider.secondColor;

            final badgeList = [
              {"name": "gold_badge", "count": badges["gold_badge"]!},
              {"name": "silver_badge", "count": badges["silver_badge"]!},
              {"name": "bronze_badge", "count": badges["bronze_badge"]!},
              {"name": "1st_badge", "count": badges["weekly_winner"]!},
            ];

            return Column(
              children: [

                /// 🔥 BADGES LIST (horizontal scroll)
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.32,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: badgeList.length,
                    itemBuilder: (context, index) {
                      return compactBadgeCard(
                        badgeList[index]["name"] as String,
                        badgeList[index]["count"] as int,
                        textColor,
                        index,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 50),

                /// 🔥 BUTTON (OUTSIDE SCROLL)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      backgroundColor: colorProvider.secondColor
                    ),
                    onPressed: () {
                      showSadhanaRulesDialog(context);
                    },
                    child: Text(
                      "View Sadhana Rules 📿",
                      style: TextStyle(fontSize: 16, color: colorProvider.color),
                    ),
                  ),
                ),

              ],
            );
          },
        ),
      );
    });
  }
}