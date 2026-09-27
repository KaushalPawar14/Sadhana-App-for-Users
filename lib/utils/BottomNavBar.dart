import 'dart:async';

import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:folk_app/pages/ABCDEScreen.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/pages/Profile.dart';
import 'package:folk_app/pages/Scorecard.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:folk_app/utils/SeenMarkers.dart';
import 'package:folk_app/utils/UnseenDot.dart';
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
  int currentIdx = 2; // Set default index to 2 for CalendarPage

  final List<String> titles = ['Folk analysis', 'Journey', 'Calendar', 'Profile'];
  late String userName; // Declare a variable to hold the username
  late String role;
  bool isLoading = true; // Flag to indicate loading state
  late List<Widget> screens; // ✅ declare late

  /// Master Task 2026-09-10, Part 6 item 5 — "Journey" (idx 1) is the only
  /// tab hosting content with unseen state (it embeds `ABCDEScreen`, whose
  /// five cards already carry their own per-card dots, plus the Phase 7
  /// "RDUA Friends" tile). Folk analysis/Calendar/Profile have no feature
  /// from this task's inventory, so they stay plain, undotted icons. Built
  /// once here, never in `build()`.
  late final Stream<bool> _journeyUnseen;

  @override
  void initState() {
    super.initState();
    // Initialize screens with placeholders first
    screens = [
      Container(), // Placeholder for CompetitionPage
      const ABCDEScreen(),
      Container(), // Placeholder for CalendarPage
      ProfilePage(),
    ];
    _fetchUserName(); // fetch user and then update screens
    _buildUnseenStreams();
  }

  Stream<Timestamp?> _maxTimestamp(
      Stream<QuerySnapshot<Map<String, dynamic>>> query, String field) {
    return query.map((snap) {
      Timestamp? max;
      for (final doc in snap.docs) {
        final ts = doc.data()[field];
        if (ts is Timestamp && (max == null || ts.compareTo(max) > 0)) {
          max = ts;
        }
      }
      return max;
    });
  }

  Stream<bool> _anyOf(List<Stream<bool>> sources) {
    late StreamController<bool> controller;
    final latest = List<bool?>.filled(sources.length, null);
    final subs = <StreamSubscription>[];

    void emit() {
      if (latest.any((v) => v == null)) return;
      controller.add(latest.any((v) => v == true));
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        for (var i = 0; i < sources.length; i++) {
          subs.add(sources[i].listen((v) {
            latest[i] = v;
            emit();
          }));
        }
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return controller.stream;
  }

  void _buildUnseenStreams() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _journeyUnseen = Stream.value(false);
      return;
    }
    final db = FirebaseFirestore.instance;

    final associationsUnseen = SeenMarkers.unseenFrom(
      _maxTimestamp(
          db.collection('associations').where('studentUid', isEqualTo: uid).snapshots(),
          'updatedAt'),
      SeenMarkers.seenAt(uid, 'associations'),
    );

    final booksUnseen = SeenMarkers.unseenFrom(
      db
          .collection('booksRead')
          .where('uid', isEqualTo: uid)
          .snapshots()
          .map((snap) {
        Timestamp? max;
        for (final doc in snap.docs) {
          if (doc.data()['commitmentSetBy'] != 'guide') continue;
          final ts = doc.data()['commitmentSetAt'];
          if (ts is Timestamp && (max == null || ts.compareTo(max) > 0)) {
            max = ts;
          }
        }
        return max;
      }),
      SeenMarkers.seenAt(uid, 'bookCommitments'),
    );

    final serviceUnseen = SeenMarkers.unseenFrom(
      db
          .collection('serviceAssignments')
          .where('studentUid', isEqualTo: uid)
          .snapshots()
          .map((snap) {
        Timestamp? max;
        for (final doc in snap.docs) {
          if (doc.data()['statusUpdatedBy'] == uid) continue;
          final ts = doc.data()['statusUpdatedAt'];
          if (ts is Timestamp && (max == null || ts.compareTo(max) > 0)) {
            max = ts;
          }
        }
        return max;
      }),
      SeenMarkers.seenAt(uid, 'serviceAssignments'),
    );

    final expeditionsUnseen = SeenMarkers.unseenFrom(
      _maxTimestamp(db.collection('expeditions').snapshots(), 'createdAt'),
      SeenMarkers.seenAt(uid, 'expeditionTrips'),
    );

    final friendRequestsUnseen = SeenMarkers.unseenFrom(
      db
          .collection('friendRequests')
          .where('toUid', isEqualTo: uid)
          .snapshots()
          .map((snap) {
        Timestamp? max;
        for (final doc in snap.docs) {
          if (doc.data()['status'] != 'pending') continue;
          final ts = doc.data()['createdAt'];
          if (ts is Timestamp && (max == null || ts.compareTo(max) > 0)) {
            max = ts;
          }
        }
        return max;
      }),
      SeenMarkers.seenAt(uid, 'friendRequests'),
    );

    _journeyUnseen = _anyOf([
      associationsUnseen,
      booksUnseen,
      serviceUnseen,
      expeditionsUnseen,
      friendRequestsUnseen,
    ]);
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
            const ABCDEScreen(),
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
        // Three-button-navigation fix — same approach as the Guide app's
        // own `utils/BottomNavBar.dart` (`CurvedNavBar`), replicated here
        // rather than reinvented (Rule 1).
        //
        // ⚠️ NOT `SafeArea`. `SafeArea` insets the bar by
        // `MediaQuery.padding.bottom` and paints nothing in the reserved
        // strip, so whatever is behind shows through:
        //
        //   * Gesture navigation — the system's home-indicator pill is a
        //     thin OVERLAY (~24-34px) and reports a non-zero bottom
        //     inset. SafeArea therefore pushes the whole bar UP by that
        //     much and leaves a bare strip beneath it — the bar looks
        //     like it's floating above the screen edge.
        //   * 3-button navigation — the opaque system bar reports a
        //     larger inset (~48px), and reserving it is genuinely
        //     necessary, otherwise the bar sits underneath the system
        //     buttons — this app's own bug before this fix.
        //
        // The inset itself is right in both cases; painting nothing in
        // it is wrong. This `Container` reserves the identical runtime
        // inset but fills it with the bar's OWN colour, so the bar reads
        // as extending to the physical bottom edge on gesture devices
        // while still clearing the opaque bar in 3-button mode. No mode
        // detection, no magic numbers — one expression that adapts
        // because the inset itself differs.
        //
        // `viewPadding` rather than `padding` on purpose: `padding`
        // collapses to zero while a keyboard is open, which would make
        // the strip flicker away mid-typing.
        bottomNavigationBar: Container(
          color: const Color(0xFF835DF1),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewPadding.bottom,
          ),
          child: CurvedNavigationBar(
            items: <Widget>[
              const Icon(
                Icons.dataset_outlined,
                size: 30,
                color: Colors.white,
              ),
              // Master Task 2026-09-10, Part 6 item 5 — the only tab with
              // an unseen-content dot; see `_journeyUnseen`'s own doc
              // comment for why the other three don't get one.
              StreamBuilder<bool>(
                stream: _journeyUnseen,
                builder: (context, snap) => UnseenBadge(
                  show: snap.data ?? false,
                  offset: const Offset(4, 2),
                  // CurvedNavigationBar shows one widget per item, so the
                  // selected/unselected pair is resolved here.
                  child: Icon(
                    currentIdx == 1 ? Icons.spa : Icons.spa_outlined,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(
                Icons.mark_unread_chat_alt_outlined,
                size: 30,
                color: Colors.white,
              ),
              const Icon(
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
        ),
      );
    });
  }
}
