import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../utils/BadgeDialog.dart';
import '../utils/ColorProvider.dart';
import '../utils/MalaLoading.dart';

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
  late AnimationController _textController;
  late Animation<double> _textAnimation;
  bool _badgeShown = false;

  final PageController pageController =
      PageController(viewportFraction: 0.62, initialPage: 0);

  @override
  void initState() {
    super.initState();

    _confettiController = ConfettiController(duration: const Duration(seconds: 4));
    _confettiController.play(); // call play separately

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _textAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _textController.dispose();
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

    final weekSnap = await firestore
        .collection('competition-results')
        .doc('weekly')
        .collection('weeks')
        .doc(weekId)
        .get();

    final data = weekSnap.data()?['topUsers'];
    if (data == null) return [];

    return List<Map<String, dynamic>>.from(data);
  }

  Widget buildAnimatedMedal(int rank) {

    if (rank == 0) {
      return Lottie.asset(
        "assets/emoji/1st_medal.json",
        width: 130,
        repeat: true,
      );
    }

    if (rank == 1) {
      return Lottie.asset(
        "assets/emoji/2nd_medal.json",
        width: 125,
        repeat: true,
      );
    }

    if (rank == 2) {
      return Lottie.asset(
        "assets/emoji/3rd_medal.json",
        width: 125,
        repeat: true,
      );
    }

    return const Icon(Icons.star, size: 100);
  }

// FRONT CARD WITH BIG MEDAL AND FANCY GRADIENT
  Widget podiumCard(Map<String, dynamic> user, int rank, double width) {

    final colorProvider = Provider.of<ColorProvider>(context, listen: false);
    /// PREMIUM METAL COLORS
    final gradients = [

      /// 🥇 GOLD — rich trophy gold
      [
        const Color(0xFF3B2A00), // deep shadow
        const Color(0xFFD4AF37), // true metallic gold
        const Color(0xFFFFF2B0), // strong reflection highlight
        const Color(0xFF6B4E00), // dark finishing edge
      ],

      /// 🥈 PLATINUM — luxury silver (not dull grey)
      [
        const Color(0xFF1F2328), // deep steel shadow
        const Color(0xFFBFC7CF), // metallic silver
        const Color(0xFFF8FAFC), // bright reflection
        const Color(0xFF3A4048), // edge depth
      ],

      /// 🥉 BRONZE — warm royal bronze
      [
        const Color(0xFF3A1F12), // deep bronze shadow
        const Color(0xFFCD7F32), // real bronze tone
        const Color(0xFFFFD19A), // highlight reflection
        const Color(0xFF6A3A1A), // rich edge finish
      ],

    ];

    final colors = gradients[rank];

    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.4, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorProvider.secondColor, // ✅ black border
          width: 0.2,             // adjust thickness
        ),

        /// SOFT DEEP SHADOW (premium look)
        boxShadow: [
          BoxShadow(
            color: colorProvider.secondColor,
            blurRadius: 0,
            spreadRadius: -10,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: colorProvider.secondColor,
            blurRadius: 0,
            spreadRadius: -2,
            offset: const Offset(2, -2),
          ),
        ],
      ),

      child: Stack(
        children: [

          /// TOP GLASS SHINE EFFECT
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.35),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          Column(
            children: [

              /// MEDAL
              Expanded(
                flex: 5,
                child: Center(
                  child: buildAnimatedMedal(rank),
                ),
              ),

              /// USER INFO
              Expanded(
                flex: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      /// NAME
                      Text(
                        user['name'] ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              blurRadius: 10,
                              color: Colors.black54,
                              offset: Offset(0, 3),
                            )
                          ],
                        ),
                      ),

                      const SizedBox(height: 33),

                      /// SCORE CHIP
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.25),
                              Colors.white.withOpacity(0.10),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),

                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 1.2,
                          ),

                          boxShadow: [

                            /// outer soft shadow
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),

                            /// subtle glow
                            BoxShadow(
                              color: Colors.white.withOpacity(0.15),
                              blurRadius: 10,
                              spreadRadius: -4,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),

                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [

                            /// small star icon adds premium feel
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.black,
                              size: 18,
                            ),

                            const SizedBox(width: 6),

                            Text(
                              "${(user['total_score'] ?? 0).toDouble().toStringAsFixed(2)} pts",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.6,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.black54,
                                    offset: Offset(0, 2),
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                      )

                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// BACK SIDE WITH FANCY GRADIENT AND SHADOW
  Widget buildBackSide(Map<String, dynamic> user, double width) {

    final colorProvider = Provider.of<ColorProvider>(context, listen: false);

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

    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(

        /// 🌌 PREMIUM ROYAL GRADIENT
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F2027),
            Color(0xFF203A43),
            Color(0xFF2C5364),
            Color(0xFF1C1C3A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, 0.4, 0.75, 1],
        ),

        borderRadius: BorderRadius.circular(24),

        /// deep luxury shadow
        boxShadow: [
          BoxShadow(
            color: colorProvider.secondColor,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),

      child: Column(
        children: [

          /// USER NAME HEADER
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(.25),
                  Colors.white.withOpacity(.05),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withOpacity(.25),
              ),
            ),
            child: Text(
              user['name'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.black,
                    offset: Offset(0, 3),
                  )
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          /// SCORES LIST
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: fields.map((key) {

                if (!user.containsKey(key)) {
                  return const SizedBox();
                }

                final value =
                (user[key] ?? 0).toDouble().toStringAsFixed(2);

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),

                  decoration: BoxDecoration(

                    /// glass row
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(.18),
                        Colors.white.withOpacity(.05),
                      ],
                    ),

                    borderRadius: BorderRadius.circular(14),

                    border: Border.all(
                      color: Colors.white.withOpacity(.18),
                    ),

                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.35),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),

                  child: Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                    children: [

                      /// PARAMETER NAME
                      Expanded(
                        child: Text(
                          format(key),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: .4,
                          ),
                        ),
                      ),

                      /// SCORE
                      Text(
                        "$value pts",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: .5,
                          shadows: [
                            Shadow(
                              blurRadius: 6,
                              color: Colors.black,
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          body: FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchTop3(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return CustomLoader();
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
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.7, end: 1),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) {

                      return Transform.scale(
                        scale: scale,
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [

                              Text(
                                "🏆",
                                style: TextStyle(fontSize: 150),
                              ),

                              SizedBox(height: 20),

                              Text(
                                "Results will be announced on Sunday",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.3,
                                  color: colorProvider.secondColor,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 12,
                                      color: Colors.black26,
                                      offset: Offset(0, 4),
                                    )
                                  ],
                                ),
                              ),

                              SizedBox(height: 12),

                              Text(
                                "Keep participating to see your name here ✨",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colorProvider.secondColor,
                                ),
                              ),

                            ],
                          ),
                        ),
                      );

                    },
                  ),
                );

              }

              return Stack(
                children: [
                  Positioned(
                    top: 58,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _textAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _textAnimation.value),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [

                              /// LEFT SIDE EMOJI
                              Lottie.asset(
                                "assets/emoji/party.json",
                                width: 55,
                                repeat: true,
                              ),

                              const SizedBox(width: 10),

                              /// TEXT
                              Text(
                                "Winners !!",
                                style: TextStyle(
                                  fontSize: 29,
                                  fontWeight: FontWeight.bold,
                                  color: colorProvider.secondColor,
                                  letterSpacing: 1.5,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 12,
                                      color: colorProvider.color,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 10),

                              /// RIGHT SIDE EMOJI (optional, looks better)
                              Lottie.asset(
                                "assets/emoji/party.json",
                                width: 55,
                                repeat: true,
                              ),

                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  /// LEADERBOARD
                  Padding(
                    padding: const EdgeInsets.only(top: 0), // adjust this value
                    child: SizedBox(
                      height: 690, // also slightly reduce height
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          return TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: Duration(milliseconds: 600 + (index * 150)),
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
                                    ? pageController.page ?? pageController.initialPage.toDouble()
                                    : 0;

                                double distance = (index - page);
                                double scale = (1 - 0.2 * distance.abs()).clamp(0.0, 1.0); // clamp to avoid negative
                                double angle = 0.3 * distance;

                                final matrix = Matrix4.identity()
                                  ..setEntry(3, 2, 0.001)
                                  ..rotateY(angle)
                                  ..scale(scale);

                                return Center(
                                  child: SizedBox(
                                    width: 330,  // must match your card width
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

                  Positioned(
                    top: 570,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Builder(builder: (context) {
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

                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.1, end: 1),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.bold,
                                    color: colorProvider.secondColor,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 8,
                                        color: Colors.black26,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),

                ],
              );
            },
          ),
        );
      },
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



