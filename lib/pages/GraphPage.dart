import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../scores/AllGraphs.dart';
import '../utils/ColorProvider.dart';

class Graphpagedashboard extends StatefulWidget {
  final String role;
  const Graphpagedashboard({super.key, required this.role});

  @override
  State<Graphpagedashboard> createState() => _GraphpagedashboardState();
}

class _GraphpagedashboardState extends State<Graphpagedashboard>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> users = [];
  int _scaleIndex = -1;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  // Fetch users from Firestore
// Fetch users from Firestore
  Future<void> _fetchUsers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: widget.role) // 🔹 Only same role users
          .get();

      final fetchedUsers = snapshot.docs
          .map((doc) => {
        'id': doc.id,
        'name': doc['name'],
      })
          .toList();

      setState(() {
        users = fetchedUsers;
      });
    } catch (e) {
      setState(() {
        users = [];
      });
    }
  }

  // Different gradient directions for variety
  final List<List<Alignment>> gradientDirections = [
    [Alignment.topLeft, Alignment.bottomRight],
    [Alignment.topRight, Alignment.bottomLeft],
    [Alignment.centerLeft, Alignment.centerRight],
    [Alignment.topCenter, Alignment.bottomCenter],
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            title: Text(
              'Users for Graph',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                letterSpacing: 0.8,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: users.isEmpty
              ? _buildLoadingShimmer()
              : ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: users.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemBuilder: (context, index) {
              final user = users[index];

              final gradient = LinearGradient(
                colors: [
                  colorProvider.thirdColor.withOpacity(0.95),
                  Colors.deepPurpleAccent.shade100.withOpacity(.80),
                ],
                begin: gradientDirections[index % gradientDirections.length][0],
                end: gradientDirections[index % gradientDirections.length][1],
              );

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 700 + (index * 120)),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 30 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _scaleIndex = index),
                    onTapUp: (_) => setState(() => _scaleIndex = -1),
                    onTapCancel: () => setState(() => _scaleIndex = -1),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AllGraph(username: user['name']),
                        ),
                      );
                    },
                    child: AnimatedScale(
                      scale: _scaleIndex == index ? 0.97 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: gradient,
                          boxShadow: [
                            BoxShadow(
                              color: colorProvider.secondColor.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.white.withOpacity(0.25),
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  user['name'],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.white, size: 26),
                            ],
                          ),
                        ),
                      ),
                    ),

                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Shimmer placeholder while loading users
  Widget _buildLoadingShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 10,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }
}
