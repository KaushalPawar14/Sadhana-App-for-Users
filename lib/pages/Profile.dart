import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:folk_app/pages/Achievements.dart';
import 'package:folk_app/pages/AssignedTasks.dart';
import 'package:folk_app/pages/BookPageList.dart';
import 'package:folk_app/pages/ChantingCompetition.dart';
import 'package:folk_app/pages/NotificationPreferences.dart';
import 'package:folk_app/pages/Welcome.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../main.dart' show studentNavigatorKey;
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

  /// Null for every student who registered before the field existed. The card
  /// stays visible either way and simply invites them to fill it in.
  DateTime? dob;

  /// Null (or absent/0 in Firestore) means "no commitment set yet" — never
  /// treated as a real commitment of 0 rounds/day.
  int? commitmentRounds;

  late String uid;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — used
  /// to be constructed fresh directly in `build()`. This is a bottom-nav
  /// TAB (not a pushed route), rebuilt on every `Consumer<ColorProvider>`
  /// notification (e.g. the dark-mode toggle) even with no `setState` of
  /// its own — so this field matters more here than on a rarely-rebuilt
  /// pushed screen. Hoisted to a field, built once in `initState()`, right
  /// after `uid` itself is known — safe unconditionally, since `uid` is
  /// fixed for this tab's whole life.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _userStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  /// Back-button fix (2026-09-03) — same bug and same fix as
  /// `pages/Questions.dart`'s own `build()`: no `PopScope`/`WillPopScope`
  /// at all before this fix, so a hardware back press with the keyboard
  /// open could close the app instead of just the keyboard. Same
  /// `PopScope<Object?>` + `canPop: false` idiom, same `viewInsets.bottom >
  /// 0` keyboard-open check — with one addition the other, always-pushed
  /// screens don't need: this page is one tab body of `CurvedNavBar`
  /// (`utils/BottomNavBar.dart`), which every live entry point reaches via
  /// `Navigator.pushAndRemoveUntil` (`CompleteProfile.dart`, `Login.dart`,
  /// `Welcome.dart`) or as `AnimatedLogin`'s own `home:` (`main.dart`) —
  /// always an EMPTY back stack. A plain `Navigator.of(context).pop()` on
  /// keyboard-closed would silently do nothing there instead of exiting
  /// the app — the correct, pre-existing behaviour for a root screen once
  /// the keyboard is already closed. `Navigator.canPop()` tells the two
  /// cases apart at pop-time.
  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (MediaQuery.of(context).viewInsets.bottom > 0) {
            FocusScope.of(context).unfocus();
            return;
          }
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
          backgroundColor: colorProvider.color,
          body: StreamBuilder<DocumentSnapshot>(
            stream: _userStream,
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
              dob = data['dob'] is Timestamp
                  ? (data['dob'] as Timestamp).toDate()
                  : null;
              final rawCommitment = data['commitmentRounds'];
              commitmentRounds = rawCommitment is num && rawCommitment > 0
                  ? rawCommitment.toInt()
                  : null;

              return _buildUI(context); // 👈 move your current UI into this
            },
          ),
        ),
      );
    });
  }

  /// Lets a student set — or correct — their own date of birth.
  ///
  /// Writes only the `dob` field with merge, so nothing else on the user
  /// document is disturbed. The profile is a live StreamBuilder, so the card
  /// updates itself once the write lands.
  Future<void> _pickAndSaveDob() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(now.year - 20),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 10, now.month, now.day),
      helpText: 'Select your date of birth',
    );

    if (picked == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'dob': Timestamp.fromDate(picked)},
        SetOptions(merge: true),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save your date of birth")),
      );
    }
  }

  /// Lets a student set — or change — their own daily chanting commitment,
  /// any time (unlike `mobileNumber`/`dob`, which lock after first save).
  ///
  /// Same "write only this one field, with merge" discipline as
  /// [_pickAndSaveDob] — nothing else on the user document is disturbed.
  Future<void> _editCommitmentRounds() async {
    final controller =
        TextEditingController(text: commitmentRounds?.toString() ?? '');

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Chanting commitment"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Rounds per day',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n == null || n <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                      content: Text("Enter a whole number greater than 0")),
                );
                return;
              }
              Navigator.of(dialogContext).pop(n);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'commitmentRounds': result},
        SetOptions(merge: true),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save your commitment")),
      );
    }
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
                              'My Achievements',
                              "Your All Badges and Tags",
                              CupertinoIcons.mail,
                              () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => AchievementsPage(
                                            username: name ?? "")));
                              }, // can leave empty
                            ),
                          ),
                        ),

                        FloatingCard(
                          delay: 400,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(25),
                            child: itemProfileCard(
                              'Chanting Competition',
                              "See the group's live rounds target",
                              CupertinoIcons.flame,
                              () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const ChantingCompetitionPage()));
                              },
                            ),
                          ),
                        ),

                        /// NOTIFICATIONS — what this student wants to be told
                        /// about. Every type defaults to on, so this row only
                        /// ever removes noise the student chose to remove.
                        FloatingCard(
                          delay: 400,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(25),
                            child: itemProfileCard(
                              'Notifications',
                              "Choose what you are notified about",
                              CupertinoIcons.bell,
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        NotificationPreferencesPage(uid: uid),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        /// DATE OF BIRTH — always shown. Students who
                        /// registered before this field existed see an
                        /// invitation to add it rather than a blank or a crash.
                        FloatingCard(
                          delay: 400,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(25),
                            child: itemProfileCard(
                              'Date of Birth',
                              dob == null
                                  ? "Tap to add your date of birth"
                                  : DateFormat('dd MMM yyyy').format(dob!),
                              CupertinoIcons.gift,
                              _pickAndSaveDob,
                            ),
                          ),
                        ),

                        /// CHANTING COMMITMENT — always shown, editable any
                        /// time (unlike Date of Birth above, this never
                        /// locks — a student's own commitment can genuinely
                        /// change). This is the number the guide's compound
                        /// target evaluation checks against.
                        FloatingCard(
                          delay: 400,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(25),
                            child: itemProfileCard(
                              'Chanting Commitment',
                              commitmentRounds == null
                                  ? "Tap to set your daily rounds commitment"
                                  : "$commitmentRounds rounds per day",
                              CupertinoIcons.flame_fill,
                              _editCommitmentRounds,
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
            // ListTile paints its background/ink splashes via the nearest
            // Material ancestor — without one here, the Container's own
            // gradient above sits between it and the Scaffold's Material,
            // triggering "ListTile background color or ink splashes may
            // be invisible" (recurred three times in this project
            // already — same fix each time).
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(25),
              clipBehavior: Clip.antiAlias,
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

/// Bug fix, 2026-09-16 — real-device-confirmed root cause: this dialog's own
/// `builder` used to name its parameter `context`, SHADOWING the outer
/// `showLogoutDialog(BuildContext context)` parameter. `showDialog` defaults
/// to `useRootNavigator: true` (Flutter's own default, confirmed against the
/// SDK source), so the dialog's content — and therefore that shadowed
/// `context` — lives on the OUTER (root) navigator, the same one whose sole
/// route is `AnimatedLogin`. `Navigator.of(context).pushAndRemoveUntil(...,
/// (route) => false)` on THAT navigator removed every route on it, including
/// `AnimatedLogin` itself — taking `FloatingAssistantOverlay` and
/// `VoiceRoomOverlay` (both only ever constructed by `AnimatedLogin`'s own
/// inner `MaterialApp.builder`) down with it, for the rest of the process.
/// Confirmed on-device: `AnimatedLogin DISPOSED` logged at logout, and
/// `AnimatedLogin.build()` never logged again afterward.
///
/// Fixed two ways together, deliberately, since they close different halves
/// of the same class of mistake:
///  1. The dialog's own builder parameter is renamed to `dialogContext` —
///     eliminates the shadow itself, so `context` inside this function
///     always, unambiguously means the OUTER caller's context, matching the
///     already-established convention this project uses elsewhere
///     (`CompleteProfile.dart`'s own `_confirmMobileDialog`).
///  2. The actual "log out and go home" navigation uses
///     `studentNavigatorKey.currentState` directly — the SAME inner
///     (student) Navigator `AnimatedLogin`'s `MaterialApp` is keyed with,
///     already used the same way by `utils/NotificationRouter.dart` — rather
///     than `Navigator.of(...)` at all. This is the more robust half: even if
///     a future edit reintroduces a shadowed or otherwise-wrong `context`
///     here, this specific navigation cannot be misdirected to the wrong
///     Navigator, because it never resolves one from a BuildContext in the
///     first place.
void showLogoutDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Log Out"),
        content: const Text("Do you really want to log out?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await GoogleSignIn().signOut();
                await FirebaseAuth.instance.signOut();
                // Close the dialog first — it lives on the OUTER/root
                // navigator (showDialog's default), which the
                // studentNavigatorKey-based push below never touches, so
                // it would otherwise be left stranded on screen.
                Navigator.of(dialogContext).pop();
                studentNavigatorKey.currentState?.pushAndRemoveUntil(
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
