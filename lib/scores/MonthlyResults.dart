import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:folk_app/scores/TopMonthResults.dart';
import 'package:provider/provider.dart';
import '../services/PercentageServices.dart';
import '../utils/ColorProvider.dart';
import '../utils/MalaLoading.dart';
import 'TopWeekResults.dart';

class MonthlyResultsPage extends StatefulWidget {
  const MonthlyResultsPage({Key? key}) : super(key: key);

  @override
  State<MonthlyResultsPage> createState() => _MonthlyResultsPageState();
}

class _MonthlyResultsPageState extends State<MonthlyResultsPage> with TickerProviderStateMixin {

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  Map<String, double> percentageChanges = {};
  bool isLoadingPercentage = true;
  bool isLoading = true;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  String? username;

  @override
  void initState() {
    super.initState();
    fetchUsername();
    // Animation setup
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
    );
    // 🔹 Floating animation for Last Week button
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Widget animatedWrapper(Widget child, double value) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.75, end: 1.0),
      duration: const Duration(milliseconds: 4000),
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

    Color glowColor = percent > 0
        ? Colors.green.withOpacity(0.3)
        : percent < 0
        ? Colors.red.withOpacity(0.3)
        : Colors.transparent;

    return animatedWrapper(
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey.shade100],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: glowColor,
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$label: $display",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              percentageText(key),
            ],
          ),
        ),
        percent);
  }

  Widget percentageText(String key) {
    double value = percentageChanges[key] ?? 0;

    if (isLoadingPercentage) {
      return SizedBox(
        height: 12,
        width: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    IconData icon;
    Color color;
    String text;

    if (value > 0) {
      icon = Icons.arrow_upward;
      color = Colors.green;
      text = "+${value.toStringAsFixed(1)}%";
    } else if (value < 0) {
      icon = Icons.arrow_downward;
      color = Colors.redAccent;
      text = "-${value.abs().toStringAsFixed(1)}%";
    } else {
      icon = Icons.remove;
      color = Colors.grey;
      text = "0%";
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 2000),
      tween: Tween(begin: 0, end: value.abs()),
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> loadPercentageChanges() async {
    if (username == null) return;

    final service = PercentageService();

    final result = await service.getMonthlyPercentageChange(
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
        percentageChanges = await service.getMonthlyPercentageChange(
          username: username!,
        );
      }

      // now both username & percentages are ready
      setState(() {
        isLoading = false;
        isLoadingPercentage = false;
      });
      _controller.forward();
    }
  }

  Widget buildCurrentRank() {

    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('competition').snapshots(),
      builder: (context, snapshot) {

        if (!snapshot.hasData) {
          return const SizedBox();
        }

        final docs = snapshot.data!.docs;

        List<Map<String, dynamic>> users = docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;

          return {
            "name": data["Name"],
            "score": (data["monthly.total_score"] ?? 0).toDouble()
          };
        }).toList();

        // 🔹 Sort by score (highest first)
        users.sort((a, b) => b["score"].compareTo(a["score"]));

        // 🔹 Find current user rank
        int rank = users.indexWhere((u) => u["name"] == username) + 1;
        final colorProvider = Provider.of<ColorProvider>(context, listen: false);
        int totalUsers = users.length;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: colorProvider.color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                color: Colors.black.withOpacity(0.08),
              )
            ],
          ),
          child: Text(
            "📊 Your position: #$rank out of $totalUsers",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: colorProvider.secondColor
            ),
          ),
        );
      },
    );
  }

  Widget buildUserCard(Map<String, dynamic> user, int rank) {
    return ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔹 Header: Name + Score
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your Score till now : ',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      user['score'].toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 🔹 Weekly Performance Chips
                Wrap(
                  spacing: 15,
                  runSpacing: 20,
                  children: [
                    infoChip("💻 SB Class", user['bhagavatam'], "monthly.bhagavatam_class"),
                    infoChip("🛕 Service", user['dailyService'], "monthly.daily_service"),
                    infoChip("📿 Chanting", user['chanting'], "monthly.chanting_rounds"),
                    infoChip("📚 Reading", user['bookReading'], "monthly.book_reading"),
                    infoChip("🎧 Lecture", user['extraLecture'], "monthly.extra_lecture"),
                    infoChip("📅 Days", user['days'], "monthly.days_count"),
                  ],
                ),

                const SizedBox(height: 26),

                // 🔹 Multipliers Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Wrap(
                    spacing: 16, // horizontal spacing between items
                    runSpacing: 8, // vertical spacing if items wrap
                    children: [
                      Text("🛕 Temple x ${user['templeMultiplier']}  ", style: TextStyle(fontWeight: FontWeight.bold),),
                      Text("📿 Japa x ${user['japaMultiplier']}  ",style: TextStyle(fontWeight: FontWeight.bold),),
                      Text("😴 Sleep x ${user['sleepMultiplier']}",style: TextStyle(fontWeight: FontWeight.bold),),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            title: Text(
              'Your This Month Results',
              style: TextStyle(
                  color: colorProvider.secondColor, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            backgroundColor: colorProvider.color,
          ),
          body: isLoading
              ? const Center(
            child: CustomLoader(),
          )
              : SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 30),
                Center(
                  child: username == null
                      ? CustomLoader()
                      : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: firestore
                        .collection('competition')
                        .doc(username)
                        .snapshots(),
                    builder: (context, snapshot) {
                      // 🔹 1. Loading state
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CustomLoader());
                      }

                      // 🔹 2. No snapshot data
                      if (!snapshot.hasData || snapshot.data == null) {
                        return Center(child: Text("No data available"));
                      }

                      // 🔹 3. Document not found
                      if (!snapshot.data!.exists) {
                        return Center(child: Text("No monthly data available."));
                      }

                      // 🔹 4. Safe extraction
                      final data = snapshot.data!.data();

                      if (data == null) {
                        return Center(child: Text("Empty data"));
                      }

                      // 🔹 5. Safe values
                      final userData = {
                        "name": data['Name'] ?? "Unknown",
                        "score": (data['monthly.total_score'] ?? 0).toDouble(),
                        "bhagavatam": (data['monthly.bhagavatam_class'] ?? 0).toDouble(),
                        "dailyService": (data['monthly.daily_service'] ?? 0).toDouble(),
                        "chanting": (data['monthly.chanting_rounds'] ?? 0).toDouble(),
                        "bookReading": (data['monthly.book_reading'] ?? 0).toDouble(),
                        "extraLecture": (data['monthly.extra_lecture'] ?? 0).toDouble(),
                        "templeMultiplier": (data['monthly.temple_multiplier'] ?? 0).toDouble(),
                        "japaMultiplier": (data['monthly.japa_multiplier'] ?? 0).toDouble(),
                        "sleepMultiplier": (data['monthly.sleeping_multiplier'] ?? 0).toDouble(),
                        "days": (data['monthly.days_count'] ?? 0).toInt(),
                      };

                      // ✅ Replace ListView with Column for proper scroll
                      return Column(
                        children: [
                          buildUserCard(userData, 1),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _floatAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, -_floatAnimation.value),
                      child: child,
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (username != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MonthlyLeaderboardPage(
                                username: username!,
                              ),
                            ),
                          );
                        }
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.deepPurple.shade900,
                                  Colors.deepPurple.shade400
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                              border: Border.all(
                                width: 2.9,
                                color: colorProvider.secondColor,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                "🏆 Last Month Performance",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                buildCurrentRank(),
              ],
            ),
          )
      );
    });
  }
}



