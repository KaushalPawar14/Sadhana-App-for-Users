import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:folk_app/utils/SameGender.dart';
import '../services/PercentageServices.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GradientCard.dart';
import '../widgets/ScoreWidgets.dart';
import 'TopWeekResults.dart';

class WeeklyResultsPage extends StatefulWidget {
  const WeeklyResultsPage({Key? key}) : super(key: key);

  @override
  State<WeeklyResultsPage> createState() => _WeeklyResultsPageState();
}

class _WeeklyResultsPageState extends State<WeeklyResultsPage>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  Map<String, double> percentageChanges = {};
  bool isLoadingPercentage = true;
  bool isLoading = true;
  // 🔹 Track if new week exists
  bool showWeekDot = false;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  String? username;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — same
  /// fix as `MonthlyResults.dart`'s own twin fields; see that file's doc
  /// comment for the full reasoning.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _leaderboardStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _myRankStream;

  /// Who is of my gender (read once per student): your position counts only them.
  final Future<GenderDirectory> _genderDirectory = GenderDirectory.forCurrentUser();

  /// Hostel and Localite students have no daily services, extra lecture or temple
  /// entry in their form, so those parts are not shown to them.
  bool _hostelLocalite = false;

  @override
  void initState() {
    super.initState();
    _genderDirectory.then((d) {
      if (mounted && d.isHostelLocalite) setState(() => _hostelLocalite = true);
    }).catchError((Object _) {});
    _leaderboardStream = Stream.fromFuture(GenderDirectory.forCurrentUser()).asyncExpand(
            (directory) => firestore
                .collection('competition')
                .where('gender', isEqualTo: directory.mine)
                .where('category', isEqualTo: directory.category)
                .snapshots());
    fetchUsername();
    // Animation setup
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut, // gives a nice “pop” effect
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> loadPercentageChanges() async {
    if (username == null) return;

    final service = PercentageService();

    final result = await service.getWeeklyPercentageChange(
      username: username!,
    );

    setState(() {
      percentageChanges = result;
      isLoadingPercentage = false;
    });
  }

  Future<void> fetchUsername() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc = await firestore.collection('users').doc(uid).get();

    if (userDoc.exists) {
      username = userDoc.data()?['name'];

      if (username != null) {
        // fetch percentage changes here
        final service = PercentageService();
        percentageChanges = await service.getWeeklyPercentageChange(
          username: username!,
        );
        _myRankStream =
            firestore.collection('competition').doc(username).snapshots();
      }

      // now both username & percentages are ready
      setState(() {
        isLoading = false;
        isLoadingPercentage = false;
      });
      _controller.forward();
    }
  }

  Widget animatedWrapper(Widget child, double value) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.75, end: 1.0),
      duration: FolkMotion.of(context, const Duration(milliseconds: 4000)),
      curve: Curves.easeOutBack,
      builder: (context, scale, _) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
    );
  }

  Widget infoChip(String label, dynamic value, String key) {
    String display;

    if (value is int) {
      display = value.toString();
    } else {
      display = (value ?? 0).toDouble().toStringAsFixed(2);
    }

    double percent = percentageChanges[key] ?? 0;

    return animatedWrapper(
        ScoreStatTile(
          label: "$label: $display",
          footer: percentageText(key),
        ),
        percent);
  }

  Widget percentageText(String key) {
    double value = percentageChanges[key] ?? 0;

    if (isLoadingPercentage) {
      return SizedBox(
        height: 12,
        width: 12,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: context.folk.text),
      );
    }

    IconData icon;
    Color color;
    String text;

    if (value > 0) {
      icon = Icons.arrow_upward;
      color = FolkCalendarTokens.legendSubmitted;
      text = "+${value.toStringAsFixed(1)}%";
    } else if (value < 0) {
      icon = Icons.arrow_downward;
      color = FolkCalendarTokens.legendMissed;
      text = "-${value.abs().toStringAsFixed(1)}%";
    } else {
      icon = Icons.remove;
      color = context.folk.mutedText;
      text = "0%";
    }

    return TweenAnimationBuilder<double>(
      duration: FolkMotion.of(context, const Duration(milliseconds: 2000)),
      tween: Tween(begin: 0.5, end: value.abs()),
      builder: (context, animatedValue, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            Text(
              value == 0
                  ? "0%"
                  : "${value > 0 ? "+" : "-"}${animatedValue.toStringAsFixed(1)}%",
              style: context.folkText.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: context.folk.text,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildCurrentRank() {
    // Your place is worked out among students of your own gender only.
    return FutureBuilder<GenderDirectory>(
      future: _genderDirectory,
      builder: (context, directorySnapshot) {
        if (!directorySnapshot.hasData) return const SizedBox();
        final directory = directorySnapshot.data!;
        return StreamBuilder<QuerySnapshot>(
      stream: _leaderboardStream,
      builder: (context, snapshot) {

        if (!snapshot.hasData) {
          return const SizedBox();
        }

        final docs = snapshot.data!.docs;

        final place = positionAmongSameGender(
          directory,
          [
            for (final doc in docs)
              (
                name: ((doc.data() as Map<String, dynamic>)["Name"] ?? '').toString(),
                score: (((doc.data() as Map<String, dynamic>)["weekly.total_score"] ?? 0) as num)
                    .toDouble(),
              ),
          ],
          username ?? '',
        );
        int rank = place.rank;
        int totalUsers = place.outOf;

        return FolkCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Text(
            "📊 Your position: #$rank out of $totalUsers",
            textAlign: TextAlign.center,
            style: context.folkText.topBarTitle.copyWith(fontSize: 17),
          ),
        );
      },
    );
      },
    );
  }

  Widget buildUserCard(Map<String, dynamic> user, int rank) {
    final colors = context.folk;
    final text = context.folkText;
    final card = FolkCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Header: Name + Score
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your Score till now : ',
                  style: text.topBarTitle,
                ),
              ),
              TweenAnimationBuilder<double>(
                duration: FolkMotion.of(
                    context, const Duration(milliseconds: 800)),
                tween: Tween(begin: 0, end: user['score']),
                builder: (context, value, _) {
                  return Text(
                    value.toStringAsFixed(2),
                    style: text.stat.copyWith(color: colors.text),
                  );
                },
              )
            ],
          ),

          const SizedBox(height: 20),

          // 🔹 Performance Chips
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              infoChip("💻 SB Class", user['bhagavatam'],
                  "weekly.bhagavatam_class"),
              if (!_hostelLocalite)
                infoChip("🛕 Service", user['dailyService'],
                    "weekly.daily_service"),
              infoChip("📿 Chanting", user['chanting'],
                  "weekly.chanting_rounds"),
              infoChip("📚 Reading", user['bookReading'],
                  "weekly.book_reading"),
              if (!_hostelLocalite)
                infoChip("🎧 Lecture", user['extraLecture'],
                    "weekly.extra_lecture"),
              infoChip("📅 Days", user['days'], "weekly.days_count"),
            ],
          ),

          const SizedBox(height: 24),

          // 🔹 Multipliers Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(FolkShape.tileRadius),
            ),
            child: Wrap(
              spacing: 16, // horizontal spacing between items
              runSpacing: 8, // vertical spacing if items wrap
              children: [
                if (!_hostelLocalite)
                  Text("🛕 Temple x ${user['templeMultiplier']}  ",
                      style: text.bodyStrong),
                Text("📿 Japa x ${user['japaMultiplier']}  ",
                    style: text.bodyStrong),
                Text("😴 Sleep x ${user['sleepMultiplier']}",
                    style: text.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
    if (FolkMotion.reduced(context)) return card;
    return ScaleTransition(scale: _scaleAnimation, child: card);
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: 'Your This Week Results',
      onBack: () => Navigator.pop(context),
      body: isLoading
          ? const LeaderboardGhost(rows: 3)
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: username == null
                        ? const LeaderboardGhost(rows: 2)
                        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: _myRankStream,
                            builder: (context, snapshot) {
                              // 🔹 1. Loading state
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const LeaderboardGhost(rows: 2);
                              }

                              // 🔹 2. No snapshot data
                              if (!snapshot.hasData || snapshot.data == null) {
                                return Center(
                                    child: Text("No data available",
                                        style: text.body));
                              }

                              // 🔹 3. Document not found
                              if (!snapshot.data!.exists) {
                                return Center(
                                    child: Text("No weekly data available.",
                                        style: text.body));
                              }

                              // 🔹 4. Safe extraction
                              final data = snapshot.data!.data();

                              if (data == null) {
                                return Center(
                                    child:
                                        Text("Empty data", style: text.body));
                              }

                              // 🔹 5. Safe values
                              final userData = {
                                    "name": data['Name'] ?? "Unknown",
                                    "score": (data['weekly.total_score'] ?? 0)
                                        .toDouble(),
                                    "bhagavatam":
                                        (data['weekly.bhagavatam_class'] ?? 0)
                                            .toDouble(),
                                    "dailyService":
                                        (data['weekly.daily_service'] ?? 0)
                                            .toDouble(),
                                    "chanting":
                                        (data['weekly.chanting_rounds'] ?? 0)
                                            .toDouble(),
                                    "bookReading":
                                        (data['weekly.book_reading'] ?? 0)
                                            .toDouble(),
                                    "extraLecture":
                                        (data['weekly.extra_lecture'] ?? 0)
                                            .toDouble(),
                                    "templeMultiplier":
                                        (data['weekly.temple_multiplier'] ?? 0)
                                            .toDouble(),
                                    "japaMultiplier":
                                        (data['weekly.japa_multiplier'] ?? 0)
                                            .toDouble(),
                                    "sleepMultiplier":
                                        (data['weekly.sleeping_multiplier'] ??
                                                0)
                                            .toDouble(),
                                    "days": (data['weekly.days_count'] ?? 0)
                                        .toInt(),
                                  };

                              return Column(
                                children: [
                                  buildUserCard(userData, 1),
                                ],
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        FolkSpace.pagePadding, 0, FolkSpace.pagePadding, 0),
                    child: IdleFloat(
                      dy: 12,
                      child: GradientCard(
                        style: FolkGradientStyle.saffron,
                        semanticLabel: "🏆 Last Week Performance",
                        onTap: () {
                              if (username != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => WeeklyLeaderboardPage(
                                      username: username!,
                                    ),
                                  ),
                                );
                              }
                            },
                        child: Center(
                          child: Text(
                            "🏆 Last Week Performance",
                            style: text.cardTitle,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                  buildCurrentRank(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  DateTime getCurrentWeekStart() {
    final now = DateTime.now();
    // weekday: Sunday=7 in Dart, Monday=1
    int daysSinceSunday =
        now.weekday % 7; // Sunday=0, Monday=1, ..., Saturday=6
    final startOfWeek = now.subtract(Duration(days: daysSinceSunday));
    return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
  }

  bool isCurrentWeek(DateTime reportedDate) {
    final weekStart = getCurrentWeekStart();
    final weekEnd = weekStart.add(const Duration(days: 6));
    return (reportedDate.isAtSameMomentAs(weekStart) ||
        (reportedDate.isAfter(weekStart) &&
            reportedDate.isBefore(weekEnd.add(const Duration(days: 1)))));
  }

  bool isCurrentMonth(DateTime reportedDate) {
    final now = DateTime.now();
    return reportedDate.year == now.year && reportedDate.month == now.month;
  }
}
