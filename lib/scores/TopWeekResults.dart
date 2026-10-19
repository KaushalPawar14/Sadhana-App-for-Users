import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import '../widgets/FolkErrorRetry.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:lottie/lottie.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/ScoreWidgets.dart';
import '../utils/BadgeDialog.dart';

class WeeklyLeaderboardPage extends StatefulWidget {

  final String username;   // ✅ store username

  const WeeklyLeaderboardPage({
    super.key,
    required this.username,
  });

  @override
  State<WeeklyLeaderboardPage> createState() => _WeeklyLeaderboardPageState();
}

class _WeeklyLeaderboardPageState extends State<WeeklyLeaderboardPage> with TickerProviderStateMixin {
  final firestore = FirebaseFirestore.instance;
  late ConfettiController _confettiController;
  bool _badgeShown = false;

  final PageController pageController =
      PageController(viewportFraction: 0.62, initialPage: 0);

  @override
  void initState() {
    super.initState();

    _confettiController = ConfettiController(duration: const Duration(seconds: 4));

  }

  bool _celebrated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_celebrated) return;
    _celebrated = true;
    // The confetti burst is skipped under "reduce animations".
    if (!FolkMotion.reduced(context)) _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    pageController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> fetchTop3() async {
    final metaSnap = await firestore
        .collection('competition-results')
        .doc('weekly_meta')
        .get();
    final weekId = metaSnap.data()?['last_week_finalized'];

    if (weekId == null) return [];

    // The winners of MY gender only: results are split into one document per
    // gender (`readMyGenderList`).
    return readMyGenderList(
      firestore
          .collection('competition-results')
          .doc('weekly')
          .collection('weeks')
          .doc(weekId),
      'topUsers',
    );
  }

  Widget buildAnimatedMedal(int rank) {

    if (rank == 0) {
      return Lottie.asset(
        "assets/emoji/1st_medal.json",
        width: 130,
        repeat: !FolkMotion.reduced(context),
      );
    }

    if (rank == 1) {
      return Lottie.asset(
        "assets/emoji/2nd_medal.json",
        width: 125,
        repeat: !FolkMotion.reduced(context),
      );
    }

    if (rank == 2) {
      return Lottie.asset(
        "assets/emoji/3rd_medal.json",
        width: 125,
        repeat: !FolkMotion.reduced(context),
      );
    }

    return const Icon(Icons.star, size: 100);
  }

// FRONT CARD WITH BIG MEDAL
  Widget podiumCard(Map<String, dynamic> user, int rank, double width) {
    return WinnerFrontCard(
      width: width,
      gradient: FolkMedal.forRank(rank) ?? FolkMedal.bronze,
      medal: buildAnimatedMedal(rank),
      name: user['name'] ?? '',
      scoreLabel:
          "${(user['total_score'] ?? 0).toDouble().toStringAsFixed(2)} pts",
    );
  }

// BACK SIDE: every score for this winner
  Widget buildBackSide(Map<String, dynamic> user, double width) {
    final fields = [
      "bhagavatam",
      "book_reading",
      "chanting_rounds",
      "daily_service",
      "extra_lecture",
      "japa_multiplier",
      "sleeping_multiplier",
      "temple_multiplier"
    ];

    /// helper to capitalize words
    String format(String text) {
      return text
          .replaceAll("_", " ")
          .split(" ")
          .map((w) =>
      w.isEmpty ? w : "${w[0].toUpperCase()}${w.substring(1)}")
          .join(" ");
    }

    final rows = <(String, String)>[
      for (final key in fields)
        if (user.containsKey(key))
          (format(key), "${(user[key] ?? 0).toDouble().toStringAsFixed(2)} pts"),
    ];

    return WinnerBackCard(
      width: width,
      name: user['name'] ?? '',
      rows: rows,
    );
  }

  // The winners: header, the swipeable podium cards, and the message for this
  // student.
  Widget _winnersBody(List<Map<String, dynamic>> users) {
    final text = context.folkText;
    final currentName = widget.username;

    // Find index of current user in top 3
                        int rankIndex = users.indexWhere((u) => u['name'] == currentName);

                        String message;
                        if (rankIndex == 0) {
                          message = "🏆 Congratulations! You are 1st this week!";
                        } else if (rankIndex == 1) {
                          message = "🥈 Great job! You are 2nd this week!";
                        } else if (rankIndex == 2) {
                          message = "🥉 Well done! You are 3rd this week!";
                        } else {
                          message = "Better luck next time! Keep participating ✨";
                        }

    return Stack(
      children: [
        Column(
          children: [
            IdleFloat(
              dy: 10,
              period: const Duration(milliseconds: 900),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    /// LEFT SIDE EMOJI
                    Lottie.asset(
                      "assets/emoji/party.json",
                      width: 55,
                      repeat: !FolkMotion.reduced(context),
                    ),

                    const SizedBox(width: 10),

                    /// TEXT
                    Flexible(
                      child: Text(
                        "Winners !!",
                        textAlign: TextAlign.center,
                        style: text.screenTitle,
                      ),
                    ),

                    const SizedBox(width: 10),

                    /// RIGHT SIDE EMOJI
                    Lottie.asset(
                      "assets/emoji/party.json",
                      width: 55,
                      repeat: !FolkMotion.reduced(context),
                    ),
                  ],
                ),
              ),
            ),

            /// LEADERBOARD
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: users.length,
                itemBuilder: (context, index) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: FolkMotion.of(
                        context, Duration(milliseconds: 600 + (index * 150))),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      // value goes from 0 → 1
                      // scale & vertical translation for pop-up effect
                      final double scale = 0.8 + 0.2 * value;
                      final double translateY = 50 * (1 - value);

                      return Transform.translate(
                        offset: Offset(0, translateY),
                        child: Transform.scale(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: AnimatedBuilder(
                      animation: pageController,
                      builder: (context, child) {
                        double page = pageController.hasClients
                            ? pageController.page ??
                                pageController.initialPage.toDouble()
                            : 0;

                        double distance = (index - page);
                        double scale = (1 - 0.2 * distance.abs()).clamp(
                            0.0, 1.0); // clamp to avoid negative
                        double angle = 0.3 * distance;

                        final matrix = Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle)
                          ..scale(scale);

                        return Center(
                          child: SizedBox(
                            width: 330, // must match your card width
                            height: 340, // must match your card height
                            child: Transform(
                              transform: matrix,
                              alignment: Alignment.center,
                              child: FlippingPodiumCard(
                                width: 330,
                                front: podiumCard(users[index], index, 330),
                                back: buildBackSide(users[index], 330),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            /// THE MESSAGE FOR THIS STUDENT
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.1, end: 1),
              duration: FolkMotion.of(context, const Duration(milliseconds: 800)),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        FolkSpace.pagePadding, 8, FolkSpace.pagePadding, 24),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: text.topBarTitle.copyWith(fontSize: 22),
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        /// TOP EXPLOSION 💥
        Positioned.fill(
          child: IgnorePointer(
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 150,
              emissionFrequency: 0.02,
              maxBlastForce: 80,
              minBlastForce: 40,
              gravity: 0.25,
              shouldLoop: false,
            ),
          ),
        ),

        /// LEFT CANNON
        Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: 0.3,
              numberOfParticles: 80,
              emissionFrequency: 0.03,
              maxBlastForce: 70,
              minBlastForce: 30,
              gravity: 0.3,
            ),
          ),
        ),

        /// RIGHT CANNON
        Positioned(
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi - 0.3,
              numberOfParticles: 80,
              emissionFrequency: 0.03,
              maxBlastForce: 70,
              minBlastForce: 30,
              gravity: 0.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: 'Weekly Winners',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchTop3(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FolkErrorRetry(
              message: "Couldn't load the winners just now.",
              onRetry: () => setState(() {}),
            );
          }
          if (!snapshot.hasData) {
            return const LeaderboardGhost(rows: 3);
          }

              final users = snapshot.data!;

              if (!_badgeShown) {
                _badgeShown = true;

                WidgetsBinding.instance.addPostFrameCallback((_) async {

                  final currentName = widget.username;

                  if (users.length > 0 && users[0]['name'] == currentName) {
                    await showBadgeDialog(context, "1st_badge");
                  }

                });
              }

              /// ✅ SHOW MESSAGE IF NO USERS OR TOP SCORE IS 0
              if (users.isEmpty ||
                  (users[0]['total_score'] ?? 0).toDouble() == 0) {

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.7, end: 1),
                      duration: FolkMotion.of(
                          context, const Duration(milliseconds: 1200)),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) {
                        return Transform.scale(
                          scale: scale,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                "🏆",
                                style: TextStyle(fontSize: 120),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                "Results will be announced on Sunday",
                                textAlign: TextAlign.center,
                                style: text.screenTitle.copyWith(fontSize: 26),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Keep participating to see your name here ✨",
                                textAlign: TextAlign.center,
                                style: text.body.copyWith(fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              }

              return _winnersBody(users);
        },
      ),
    );
  }
}

class FlippingPodiumCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  final Duration duration;
  final double width;

  const FlippingPodiumCard({
    super.key,
    required this.front,
    required this.back,
    required this.width,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  State<FlippingPodiumCard> createState() => _FlippingPodiumCardState();
}

class _FlippingPodiumCardState extends State<FlippingPodiumCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool isFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  void toggleCard() {
    _controller.duration = FolkMotion.of(context, widget.duration);
    _controller.reverseDuration = FolkMotion.of(context, widget.duration);
    if (isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    isFront = !isFront;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: toggleCard,
      child: SizedBox(
        width: widget.width,
        height: 340, // important: give full height
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final angle = _animation.value * 3.1416;

            final transform = Matrix4.identity()
              ..setEntry(3, 2, 0.002) // stronger perspective
              ..rotateY(angle);

            return Transform(
              transform: transform,
              alignment: Alignment.center,
              child: angle <= 3.1416 / 2
                  ? widget.front
                  : Transform(
                      transform: Matrix4.rotationY(3.1416),
                      alignment: Alignment.center,
                      child: widget.back,
                    ),
            );
          },
        ),
      ),
    );
  }
}



