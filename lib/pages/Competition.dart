import 'package:flutter/material.dart';
import 'package:folk_app/pages/GraphPage.dart';
import 'package:folk_app/pages/Scorecard.dart';
import 'package:folk_app/scores/MonthlyResults.dart';
import 'package:folk_app/scores/WeeklyResults.dart';
import 'package:folk_app/utils/BadgeDialog.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';

class CompetitionPage extends StatefulWidget {
  final String role;
  const CompetitionPage({super.key, required this.role});

  @override
  State<CompetitionPage> createState() => _CompetitionPageState();
}

class _CompetitionPageState extends State<CompetitionPage> with TickerProviderStateMixin {
  int? selectedIndex;
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(6, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(seconds: 2 + index % 3), // slightly different durations
      )..repeat(reverse: true);
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0, end: 8).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> cards = [
      {"title": "Leaderboard", "icon": Icons.emoji_events, "color": Colors.deepPurpleAccent.shade100},
      {"title": "Graphical Analysis", "icon": Icons.show_chart, "color": Colors.deepPurpleAccent.shade700},
      {"title": "Weekly Performance", "icon": Icons.weekend_outlined, "color": Colors.deepPurpleAccent.shade200},
      {"title": "Monthly Performance", "icon": Icons.calendar_month_outlined, "color": Colors.deepPurpleAccent.shade200},
      {"title": "Best Performer", "icon": Icons.star, "color": Colors.deepPurpleAccent.shade700},
      {"title": "Want to improve?", "icon": Icons.add_task, "color": Colors.deepPurpleAccent.shade100},
    ];

    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: Padding(
          padding: const EdgeInsets.only(top: 50, left: 16, right: 16),
          child: GridView.builder(
            itemCount: cards.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 35,
              crossAxisSpacing: 20,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final card = cards[index];
              return GestureDetector(
                onTap: () {
                  if (widget.role == "Stay at Hostel" &&
                      card['title'] != "Graphical Analysis") {

                    showSnackbar(
                      context,
                      'Coming soon',
                      Colors.yellow,
                      Icons.watch_later_outlined,
                    );
                    return; // 🚨 stop further execution
                  }
                  if (card['title'] == "Leaderboard") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ScorecardPage()),
                    );
                  } else if (card['title'] == "Graphical Analysis") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Graphpagedashboard(role: widget.role,)),
                    );
                  } else if (card['title'] == "Weekly Performance") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => WeeklyResultsPage()),
                    );
                  } else if (card['title'] == "Monthly Performance") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => MonthlyResultsPage()),
                    );
                  } else {
                    showSnackbar(
                      context,
                      'Coming soon',
                      Colors.yellow,
                      Icons.watch_later_outlined,
                    );
                  }
                },
                child: AnimatedBuilder(
                  animation: _animations[index],
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, -_animations[index].value),
                      child: child,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      color: card['color'],
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: colorProvider.secondColor.withOpacity(0.5),

                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: selectedIndex == index
                          ? Border.all(color: Colors.yellowAccent, width: 3)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(card['icon'], size: 50, color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          card['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}
