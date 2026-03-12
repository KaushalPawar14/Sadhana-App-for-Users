import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/pages/Profile.dart';
import 'package:folk_app/pages/Scorecard.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CurvedNavBar extends StatefulWidget {

  const CurvedNavBar(this.role, {super.key});
  final String role;

  @override
  State<CurvedNavBar> createState() => _CurvedNavBarState();
}

class _CurvedNavBarState extends State<CurvedNavBar> {
  int currentIdx = 1; // Set default index to 1 for CalendarPage

  final List<String> titles = ['Folk analysis', 'Calendar', 'Profile'];
  late String userName; // Declare a variable to hold the username
  late String role;
  bool isLoading = true; // Flag to indicate loading state
  late List<Widget> screens; // ✅ declare late

  @override
  void initState() {
    super.initState();
    // Initialize screens with placeholders first
    screens = [
      Container(), // Placeholder for CompetitionPage
      Container(), // Placeholder for CalendarPage
      ProfilePage(),
    ];
    _fetchUserName(); // fetch user and then update screens
  }

  // Fetch the username from Firestore
  Future<void> _fetchUserName() async {
    try {
      var currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        var userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        userName = userDoc.data()?['name'] ?? 'Unknown User';
        role = userDoc.data()?['role'] ?? widget.role; // fallback to passed role

        // Update screens with actual pages now that role and username are known
        setState(() {
          screens = [
            CompetitionPage(role: role),
            CalendarPage(username: userName, role: role),
            ProfilePage(),
          ];
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching username from Firestore: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            titles[currentIdx],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 25,
              color: colorProvider.secondColor,
            ),
          ),
          backgroundColor: colorProvider.color,
        ),
        body: isLoading
            ? CustomLoader() // Show loading indicator
            : screens[currentIdx], // Show the correct screen
        bottomNavigationBar: CurvedNavigationBar(
          items: const <Widget>[
            Icon(
              Icons.dataset_outlined,
              size: 30,
              color: Colors.white,
            ),
            Icon(
              Icons.mark_unread_chat_alt_outlined,
              size: 30,
              color: Colors.white,
            ),
            Icon(
              Icons.person,
              size: 30,
              color: Colors.white,
            ),
          ],
          buttonBackgroundColor: const Color(0xFF835DF1),
          backgroundColor: colorProvider.color,
          color: const Color(0xFF835DF1),
          animationCurve: Curves.easeInOut,
          height: 60,
          animationDuration: const Duration(milliseconds: 250),
          index: currentIdx, // Set the initial selected index
          onTap: (index) {
            setState(() {
              currentIdx = index;
            });
          },
        ),
      );
    });
  }
}
