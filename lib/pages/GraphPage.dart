import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../scores/AllGraphs.dart';
import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/ScoreWidgets.dart';

class Graphpagedashboard extends StatefulWidget {
  final String role;
  const Graphpagedashboard({super.key, required this.role});

  @override
  State<Graphpagedashboard> createState() => _GraphpagedashboardState();
}

class _GraphpagedashboardState extends State<Graphpagedashboard>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> users = [];

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

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: 'Users for Graph',
      onBack: () => Navigator.pop(context),
      body: users.isEmpty
          ? _buildLoadingShimmer()
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: users.length,
              padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding,
                  FolkSpace.lg, FolkSpace.pagePadding, 28),
              itemBuilder: (context, index) {
                final user = users[index];

                return EntryAnimation(
                  index: index,
                  child: FolkCard(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    radius: FolkShape.tileRadius,
                    semanticLabel: 'Graphs for ${user['name']}',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AllGraph(username: user['name']),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: FolkGradients.violet,
                          ),
                          child: const Icon(
                            Icons.person,
                            color: FolkColors.onGradient,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            user['name'],
                            style: text.bodyStrong,
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: context.folk.mutedText, size: 26),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// Ghost rows while the users load
  Widget _buildLoadingShimmer() {
    return const LeaderboardGhost(rows: 8);
  }
}
