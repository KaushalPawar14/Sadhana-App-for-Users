import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:folk_app/pages/Achievements.dart';
import 'package:folk_app/pages/AssignedTasks.dart';
import 'package:folk_app/pages/BookPageList.dart';
import 'package:folk_app/pages/Welcome.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';


class ProfilePage extends StatefulWidget {
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {

  String? name;
  String? email;
  String? role;
  String? mobileNumber;
  late String uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CustomLoader());
            }

            if (snapshot.hasError) {
              return Center(child: Text("Error: ${snapshot.error}"));
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Center(child: Text("No Data"));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;

            name = data['name'] ?? "";
            email = data['email'] ?? "";
            role = data['role'] ?? "Not mentioned";
            mobileNumber = data['mobileNumber'];

            return _buildUI(context); // 👈 move your current UI into this
          },
        ),
      );
    });
  }

  Widget _buildUI(BuildContext context) {

    final colorProvider = Provider.of<ColorProvider>(context, listen: false);

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: SizedBox()),
                            IconButton(
                              onPressed: () {
                                Provider.of<ColorProvider>(context,
                                    listen: false)
                                    .toggleColor();
                              },
                              icon: Icon(Icons.dark_mode,
                                  color: colorProvider.secondColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),

                        /// Profile header
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.white.withOpacity(0.3),
                                child: const Icon(
                                  CupertinoIcons.person_alt,
                                  size: 34,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name ?? "",
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      role ??
                                          "", // <-- Show role instead of email
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 30),

                        /// Floating menu items
                        FloatingCard(
                          child: itemProfileCard(
                            'Book read',
                            'Share your books reading history',
                            CupertinoIcons.book,
                                () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          BooksSelectionScreen()));
                            },
                          ),
                        ),
                        FloatingCard(
                          delay: 400,
                          child: Material(
                            color: Colors
                                .transparent, // if you want ripple visible, use a non-transparent color
                            borderRadius: BorderRadius.circular(25),
                            child: itemProfileCard(
                              'Allotted Tasks',
                              "Let’s Explore Your Understanding",
                              CupertinoIcons.mail,
                                  () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            AssignedTasks(uid: uid)));
                              }, // can leave empty
                            ),
                          ),
                        ),
                        FloatingCard(
                          delay: 400,
                          child: Material(
                            color: Colors
                                .transparent, // if you want ripple visible, use a non-transparent color
                            borderRadius: BorderRadius.circular(25),
                            child: itemProfileCard(
                              'My Achievements',
                              "Your All Badges and Tags",
                              CupertinoIcons.mail,
                                  () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            AchievementsPage(username: name ?? "")));
                              }, // can leave empty
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        /// Logout button
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange[500],
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 15),
                            ),
                            onPressed: () {
                              showLogoutDialog(context);
                            },
                            child: const Text(
                              "Log Out",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              )

            ],
          ),
        ),
      ),
    );
  }

  Widget itemProfileCard(
      String title, String subtitle, IconData iconData, VoidCallback onTap) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurpleAccent, Colors.deepPurple.shade300],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26.withOpacity(0.25),
                  spreadRadius: 2,
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ListTile(
              title: Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white),
              ),
              subtitle: Text(
                subtitle,
                style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Colors.white70),
              ),
              leading: Icon(iconData, color: Colors.white, size: 28),
              onTap: onTap,
            ),
          ),
        );
      },
    );
  }
}

class FloatingCard extends StatefulWidget {
  final Widget child;
  final int delay;
  const FloatingCard({super.key, required this.child, this.delay = 0});

  @override
  _FloatingCardState createState() => _FloatingCardState();
}

class _FloatingCardState extends State<FloatingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _animation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Start repeating after optional delay
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

void showLogoutDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Log Out"),
        content: const Text("Do you really want to log out?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => WelcomePage()),
                  (route) => false,
                );
              } catch (e) {
                debugPrint("Error during logout: $e");
              }
            },
            child: const Text("Yes"),
          ),
        ],
      );
    },
  );
}
