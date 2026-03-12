import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:iconly/iconly.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

class Chanting extends StatelessWidget {
  // Fetch leaderboard data
  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    var userDocs =
    await FirebaseFirestore.instance.collection('scorecard').get();

    List<Map<String, dynamic>> leaderboard = [];

    for (var userDoc in userDocs.docs) {
      // 🔥 VERY IMPORTANT: skip flag document
      if (userDoc.id == 'flag') continue;
      leaderboard.add({
        'userName': userDoc.id,
        'totalChantRounds': userDoc['totalChantRounds'] ?? 0,
      });
    }

    leaderboard.sort(
            (a, b) => b['totalChantRounds'].compareTo(a['totalChantRounds']));
    return leaderboard;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(65),
          child: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                IconlyBroken.arrow_left,
                size: 4.5.h, // bigger back icon
                color: colorProvider.secondColor,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text(
              'Chanting Leaderboard',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17.sp,
                color: colorProvider.secondColor,
              ),
            ),
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: fetchLeaderboard(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CustomLoader();
            }

            if (snapshot.hasError) {
              return Center(
                  child: Text('Error: ${snapshot.error}',
                      style: TextStyle(color: colorProvider.secondColor)));
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Text(
                  'No leaderboard data available.',
                  style: TextStyle(color: colorProvider.secondColor),
                ),
              );
            }

            List<Map<String, dynamic>> leaderboard = snapshot.data!;

            return Column(
              children: [
                // 🎖️ Top 3 podium
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (leaderboard.length > 1)
                        Flexible(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: _AnimatedTopPlayerCard(
                              colorProvider: colorProvider,
                              user: leaderboard[1],
                              medal: "🥈",
                              size: 65,
                            ),
                          ),
                        ),
                      Flexible(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: _AnimatedTopPlayerCard(
                            colorProvider: colorProvider,
                            user: leaderboard[0],
                            medal: "🥇",
                            size: 85,
                          ),
                        ),
                      ),
                      if (leaderboard.length > 2)
                        Flexible(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AnimatedTopPlayerCard(
                              colorProvider: colorProvider,
                              user: leaderboard[2],
                              medal: "🥉",
                              size: 55,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 🔽 Rest of leaderboard (stylized cards)
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: leaderboard.length > 3 ? leaderboard.length - 3 : 0,
                    itemBuilder: (context, index) {
                      var user = leaderboard[index + 3];

                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 500 + (index * 120)),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, (1 - value) * 40), // slide from bottom
                            child: Opacity(
                              opacity: value.clamp(0.0, 1.0),
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  colorProvider.thirdColor.withOpacity(0.8),
                                  colorProvider.secondColor.withOpacity(0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorProvider.secondColor.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(2, 4),
                                ),
                              ],
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.black.withOpacity(0.2),
                                child: Text(
                                  (index + 4).toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              title: Text(
                                user['userName'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16.sp,
                                  color: Colors.white,
                                ),
                                softWrap: true,
                              ),
                              trailing: Text(
                                '${user['totalChantRounds']} rounds',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13.sp,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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

// 🔥 Animated Top Player Card
class _AnimatedTopPlayerCard extends StatefulWidget {
  final ColorProvider colorProvider;
  final Map<String, dynamic> user;
  final String medal;
  final double size;

  const _AnimatedTopPlayerCard({
    required this.colorProvider,
    required this.user,
    required this.medal,
    required this.size,
  });

  @override
  State<_AnimatedTopPlayerCard> createState() => _AnimatedTopPlayerCardState();
}

class _AnimatedTopPlayerCardState extends State<_AnimatedTopPlayerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller =
    AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🥇 Medal Circle
          CircleAvatar(
            radius: widget.size / 2,
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    widget.colorProvider.secondColor.withOpacity(0.4),
                    widget.colorProvider.secondColor.withOpacity(0.7),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.colorProvider.secondColor.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                widget.medal,
                style: TextStyle(fontSize: widget.size / 2),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ✅ User name (always wrapped, no ...)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.size * 2.5,
            ),
            child: Text(
              widget.user['userName'],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: widget.colorProvider.secondColor,
                fontSize: 17.sp,
              ),
              softWrap: true,
            ),
          ),

          const SizedBox(height: 4),

          // ✅ Total rounds
          Text(
            "${widget.user['totalChantRounds']} rounds",
            style: TextStyle(
              color: widget.colorProvider.secondColor.withOpacity(0.9),
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
