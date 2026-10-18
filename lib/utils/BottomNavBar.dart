import 'dart:async';

import 'package:flutter/material.dart';
import 'package:folk_app/pages/ABCDEScreen.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/pages/Profile.dart';
import 'package:folk_app/services/DailyMessageService.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/MainAppReached.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/utils/SeenMarkers.dart';
import 'package:folk_app/utils/UnseenDot.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/FolkPageBackground.dart';
import 'package:folk_app/widgets/FolkStatusBar.dart';
import 'package:folk_app/widgets/NavHostGhost.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// The four tabs' titles, the small muted line above two of them, the title bar and
// the pill's items. Top-level so the launch ghost (`widgets/StartupWaiting.dart`)
// draws the very same header and pill the tab host does.
const List<String> kHostTabTitles = ['Insights', 'Journey', 'Sadhana', 'Profile'];

const Map<int, String> kHostKickers = {
  0: "How you're doing",
  2: 'Your daily practice',
};

/// The tab's large title, in place of the AppBar the screens used to sit
/// under. Each tab's own screen starts below it, as it did below the AppBar.
Widget hostHeader(BuildContext context, int idx) {
  // Journey greets the student by name inside its own list ("Hare Krishna,"
  // and the first name), so it has no title bar of its own.
  if (idx == 1) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.fromLTRB(
        FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding, FolkSpace.sm),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A small muted line above the title (Insights and Sadhana).
          if (kHostKickers[idx] != null)
            Text(
              kHostKickers[idx]!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.folkText.body
                  .copyWith(color: context.folk.mutedText),
            ),
          Text(
            kHostTabTitles[idx],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.folkText.screenTitle,
          ),
        ],
      ),
    ),
  );
}

/// The pill's four items. [journeyUnseen] feeds the one unseen-content dot (on
/// Journey); the launch ghost passes none.
List<FolkNavItem> hostNavItems(BuildContext context,
    {Stream<bool>? journeyUnseen}) {
  final colors = context.folk;
  final titles = kHostTabTitles;
  return [
    FolkNavItem(
      label: titles[0],
      iconBuilder: (context, selected, color) => Icon(
        Icons.bar_chart_rounded,
        size: 22,
        color: color,
      ),
    ),
    // Master Task 2026-09-10, Part 6 item 5 — the only tab with an
    // unseen-content dot; see `_journeyUnseen`'s own doc comment for
    // why the other three don't get one. The dot is wrapped OUTSIDE
    // the selected/unselected icon cross-fade (`decorate`), so its
    // stream subscription survives the tab being selected.
    FolkNavItem(
      label: titles[1],
      decorate: journeyUnseen == null
          ? null
          : (context, icon) => StreamBuilder<bool>(
                stream: journeyUnseen,
                builder: (context, snap) => UnseenBadge(
                  show: snap.data ?? false,
                  offset: const Offset(0, -2),
                  ringColor: colors.surface,
                  child: icon,
                ),
              ),
      iconBuilder: (context, selected, color) => Icon(
        selected ? Icons.spa : Icons.spa_outlined,
        size: 22,
        color: color,
      ),
    ),
    FolkNavItem(
      label: titles[2],
      iconBuilder: (context, selected, color) => Icon(
        Icons.event_available_outlined,
        size: 22,
        color: color,
      ),
    ),
    FolkNavItem(
      label: titles[3],
      iconBuilder: (context, selected, color) => Icon(
        selected ? Icons.person_rounded : Icons.person_outline_rounded,
        size: 22,
        color: color,
      ),
    ),
  ];
}

class CurvedNavBar extends StatefulWidget {

  const CurvedNavBar(
    this.role, {
    super.key,
    this.loadUser,
    this.buildScreens,
    this.journeyUnseen,
    this.dailyMessage,
  });
  final String role;

  // Tests hand in their own loader, screens and unseen stream so the host can
  // run without Firebase; the app never sets these.
  @visibleForTesting
  final Future<({String name, String role})> Function()? loadUser;
  @visibleForTesting
  final List<Widget> Function(String userName, String role)? buildScreens;
  @visibleForTesting
  final Stream<bool>? journeyUnseen;
  @visibleForTesting
  final DailyMessageService? dailyMessage;

  @override
  State<CurvedNavBar> createState() => _CurvedNavBarState();
}

class _CurvedNavBarState extends State<CurvedNavBar>
    with WidgetsBindingObserver {
  int currentIdx = 2; // Set default index to 2 for CalendarPage

  /// The tabs the student has opened. A tab's screen is built the first time
  /// it is selected and then kept alive (see the `IndexedStack` in `build`),
  /// so coming back to it neither rebuilds nor re-reads anything and its
  /// entry animation plays only on that first visit.
  final Set<int> _visited = {2};

  /// Today's message is made when the student opens (or comes back to) the
  /// app, so it is ready before they reach Journey. Null in tests that hand
  /// in their own `loadUser` without a service.
  DailyMessageService? get _dailyMessage =>
      widget.dailyMessage ??
      (widget.loadUser == null ? DailyMessageService.instance : null);

  final List<String> titles = kHostTabTitles;
  late String userName; // Declare a variable to hold the username
  late String role;

  // Follows this student's own `users` document, so a residence change made by a guide
  // (FOLK <-> Hostel <-> Localite) switches the screens and the rankings at once instead of
  // after the next restart.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  bool isLoading = true; // Flag to indicate loading state
  bool loadFailed = false; // LOGIC CHANGE: the profile read failed; show Retry
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
    WidgetsBinding.instance.addObserver(this);
    _dailyMessage?.onAppOpened();
    // The tab host is only ever built once registration is complete: tell the
    // floating buttons the student has reached the main app.
    MainAppReached.instance.enter();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _dailyMessage?.onAppOpened();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profileSub?.cancel();
    MainAppReached.instance.leave();
    super.dispose();
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
    if (widget.journeyUnseen != null) {
      _journeyUnseen = widget.journeyUnseen!;
      return;
    }
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
  //
  // LOGIC CHANGE: a failed read (or no signed-in user) used to leave the host
  // on its loader for good. It now sets [loadFailed], which shows an error with
  // a Retry button; Retry calls this again.
  Future<void> _fetchUserName() async {
    try {
      final injected = widget.loadUser;
      if (injected != null) {
        final loaded = await injected();
        userName = loaded.name;
        role = loaded.role;
      } else {
        var currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          throw StateError('No signed-in user');
        }
        var userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        userName = userDoc.data()?['name'] ?? 'Unknown User';
        role = userDoc.data()?['role'] ?? widget.role; // fallback to passed role
      }

      if (!mounted) return;
      // Update screens with actual pages now that role and username are known
      setState(() {
        screens = widget.buildScreens != null
            ? widget.buildScreens!(userName, role)
            : [
                CompetitionPage(role: role, username: userName),
                const ABCDEScreen(),
                CalendarPage(username: userName, role: role),
                ProfilePage(),
              ];
        loadFailed = false;
        isLoading = false;
      });
      _watchProfile();
    } catch (e) {
      print('Error fetching username from Firestore: $e');
      if (!mounted) return;
      setState(() => loadFailed = true);
    }
  }

  void _watchProfile() {
    if (_profileSub != null || widget.loadUser != null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null || !mounted || isLoading) return;
      final newRole = (data['role'] ?? '').toString();
      if (newRole.isEmpty || newRole == role) return;
      // The residence changed: the category (and so the rankings) changed with it.
      GenderDirectory.reset();
      setState(() {
        role = newRole;
        screens = [
          CompetitionPage(role: role, username: userName),
          const ABCDEScreen(),
          CalendarPage(username: userName, role: role),
          ProfilePage(),
        ];
      });
    }, onError: (_) {});
  }

  void _retryLoad() {
    setState(() {
      loadFailed = false;
      isLoading = true;
    });
    _fetchUserName();
  }

  Widget _header() => hostHeader(context, currentIdx);

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    return FolkStatusBar(
      child: Scaffold(
        // The pill floats; the body runs underneath it, so every tab screen
        // pads its own bottom by `FloatingPillNavBar.reservedHeight`.
        extendBody: true,
        backgroundColor: colors.pageBackground,
        body: FolkPageBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                EntryAnimation(index: 0, child: _header()),
                Expanded(
                  // Tab screens pad their own bottom explicitly (by
                  // `FloatingPillNavBar.reservedHeight`), so the Scaffold's
                  // automatic bottom padding is removed here — but ONLY
                  // `padding`. `MediaQuery.removePadding` also took the system
                  // bar's height out of `viewPadding`, which is what
                  // `reservedHeight` reads, so every tab padded itself too
                  // little (by the gesture-bar / 3-button-bar height) and its
                  // last item ended up behind the pill. `viewPadding` is kept.
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.paddingOf(context).copyWith(bottom: 0),
                    ),
                    child: loadFailed
                        ? NavHostError(onRetry: _retryLoad)
                        : isLoading
                            ? const NavHostGhost() // Ghost of the first tab while the name and role load
                            // Every opened tab stays alive underneath the
                            // visible one; the hidden ones do not tick.
                            : IndexedStack(
                                index: currentIdx,
                                children: [
                                  for (var i = 0; i < screens.length; i++)
                                    TickerMode(
                                      enabled: i == currentIdx,
                                      child: _visited.contains(i)
                                          ? screens[i]
                                          : const SizedBox.shrink(),
                                    ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Three-button-navigation fix (kept): the pill's own bottom padding
        // is `viewPadding.bottom`, so it clears the system bar in gesture and
        // 3-button modes alike — see `FloatingPillNavBar`. `viewPadding`
        // rather than `padding` so it does not collapse while a keyboard is
        // open.
        bottomNavigationBar: FloatingPillNavBar(
          currentIndex: currentIdx, // initial selection is index 2
          items: hostNavItems(context, journeyUnseen: _journeyUnseen),
          onTap: (index) {
            setState(() {
              currentIdx = index;
              _visited.add(index);
            });
          },
        ),
      ),
    );
  }
}
