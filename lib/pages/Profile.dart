import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/UpdateToken.dart';
import '../utils/Commitments.dart';
import '../utils/SadhanaReportSource.dart' show ReportCategory;
import '../widgets/CommitmentDialog.dart';
import '../utils/SameGender.dart';
import 'package:folk_app/pages/MyCompetitions.dart';
import 'package:folk_app/pages/MyMusicPage.dart';
import 'package:folk_app/pages/NotificationPreferences.dart';
import 'package:folk_app/pages/Welcome.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../main.dart' show studentNavigatorKey;
import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../theme/FolkTypography.dart';
import '../theme/ThemeModeController.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FloatingPillNavBar.dart';
import '../widgets/FolkSegmented.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/GradientCard.dart';
import '../widgets/LogoutButton.dart';
import '../widgets/ProfileMenuRow.dart';
import '../utils/GuideNameCache.dart';
import '../widgets/ProfileStatTiles.dart';
import '../services/StudentApi.dart';
import '../widgets/FolkErrorRetry.dart';

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

  /// Minutes of reading a day the student committed to; null = not set yet,
  /// 0 = a beginner.
  int? readingCommitmentMinutes;

  /// The most rounds / reading minutes the student ever reported in one day, from
  /// the user document (kept by the `updateBestStatsOn*` triggers). 0 until set.
  int bestChantRounds = 0;

  /// The guide the student is assigned to (`users.guideId`); empty when none.
  String guideId = '';

  /// The display name of the admin (Guide / Enabler) the student is assigned to,
  /// from the `getMyGuide` callable (a student cannot read `adminUsers`).
  String guideName = '';
  String _guideNameFor = '\u0000';

  /// True once the user document has carried `guideName` (the server stamps it): from then on the name comes from the
  /// user stream, as fast as the date of birth; the callable below is only the fallback for a document not stamped yet.
  bool _guideFromDoc = false;

  /// The most points the student earned in one day (multipliers included), from the user document (kept by the scoring
  /// trigger). 0 until set.
  int bestDayPoints = 0;

  void _readGuideName(Map<String, dynamic> data) {
    final stamped = stampedGuideName(data);
    if (stamped != null) {
      _guideFromDoc = true;
      final changed = guideName != stamped;
      guideName = stamped;
      _guideNameFor = guideId;
      if (changed && stamped.isNotEmpty) GuideNameCache.write(uid, stamped);
      return;
    }
    _refreshGuideName(guideId);
  }

  void _refreshGuideName(String forGuideId) {
    if (_guideNameFor == forGuideId) return;
    _guideNameFor = forGuideId;
    if (forGuideId.isEmpty) {
      guideName = '';
      return;
    }
    StudentApi.instance.getMyGuide().then((g) {
      if (!mounted || _guideNameFor != forGuideId) return;
      setState(() => guideName = g.displayName);
    }).catchError((_) {
      // keep whatever is shown; "Not assigned yet" when nothing was ever loaded
    });
  }
  int bestReadingMinutes = 0;

  late String uid;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — used
  /// to be constructed fresh directly in `build()`. This is a bottom-nav
  /// TAB (not a pushed route), rebuilt on every `Consumer<ColorProvider>`
  /// notification (e.g. the dark-mode toggle) even with no `setState` of
  /// its own — so this field matters more here than on a rarely-rebuilt
  /// pushed screen. Hoisted to a field, built once in `initState()`, right
  /// after `uid` itself is known — safe unconditionally, since `uid` is
  /// fixed for this tab's whole life.
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _userStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    // The last guide name seen on this phone, so "My Guide" has its answer before anything arrives.
    GuideNameCache.read(uid).then((cached) {
      if (cached != null && mounted && guideName.isEmpty && !_guideFromDoc) setState(() => guideName = cached);
    });
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
    final text = context.folkText;
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
        // The tab host paints the page background (with the top fade).
        backgroundColor: Colors.transparent,
        body: StreamBuilder<DocumentSnapshot>(
          stream: _userStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _swap('ghost', _ghostBody());
            }

            if (snapshot.hasError) {
              return _swap(
                  'error',
                  FolkErrorRetry(
                    message: "Couldn't load your profile just now.",
                    onRetry: () => setState(() {
                      _userStream = FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .snapshots();
                    }),
                  ));
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return _swap(
                  'empty', Center(child: Text("No Data", style: text.body)));
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
            final rawReading = data['readingCommitmentMinutes'];
            readingCommitmentMinutes =
                rawReading is num && rawReading >= 0 ? rawReading.toInt() : null;
            guideId = (data['guideId'] ?? '').toString();
            _readGuideName(data);
            final rawBestDay = data['bestDayPoints'];
            bestDayPoints = rawBestDay is num ? rawBestDay.round() : 0;
            final rawBestChant = data['bestChantRounds'];
            bestChantRounds = rawBestChant is num ? rawBestChant.toInt() : 0;
            final rawBestReading = data['bestReadingMinutes'];
            bestReadingMinutes =
                rawBestReading is num ? rawBestReading.toInt() : 0;

            return _swap('real', _buildUI(context)); // 👈 move your current UI into this
          },
        ),
      ),
    );
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
      // Colours only — the picker follows the Folk palette in both themes.
      builder: (pickerContext, child) {
        final colors = pickerContext.folk;
        final scheme = colors.isDark
            ? ColorScheme.dark(
                primary: colors.primaryBg,
                onPrimary: colors.primaryFg,
                surface: colors.surface,
                onSurface: colors.text,
              )
            : ColorScheme.light(
                primary: colors.primaryBg,
                onPrimary: colors.primaryFg,
                surface: colors.surface,
                onSurface: colors.text,
              );
        return Theme(
          data: Theme.of(pickerContext).copyWith(colorScheme: scheme),
          child: child!,
        );
      },
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

  /// Lets a student set — or change — both daily commitments (rounds and reading
  /// minutes), any time (unlike `mobileNumber`/`dob`, which lock after first save).
  ///
  /// Same "write only these fields, with merge" discipline as
  /// [_pickAndSaveDob] — nothing else on the user document is disturbed.
  Future<void> _editCommitment() async {
    final result = await showCommitmentDialog(
      context,
      current: Commitments(
        rounds: commitmentRounds ?? kDefaultChantCommitment,
        readingMinutes: readingCommitmentMinutes,
      ),
    );
    if (result == null) return;

    if (!await saveCommitments(result, uid: uid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save your commitment")),
      );
    }
  }

  /// Cross-fades between the ghost, an error and the real page. All three fill
  /// the same body, so nothing moves.
  Widget _swap(String key, Widget child) {
    return AnimatedSwitcher(
      duration: FolkMotion.of(context, FolkMotion.ghostCrossFade),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey<String>(key), child: child),
    );
  }

  /// While the profile document loads: the name card, the three stat tiles, the
  /// five-row menu card,
  /// the Appearance row and the Log Out button as ghosts, with the same page
  /// padding, gaps and sizes as the real page (88 / 5 rows of 64 + 12 / 72 / 56).
  /// The stream that ends this is unchanged.
  Widget _ghostBody() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        FolkSpace.pagePadding,
        FolkSpace.sm,
        FolkSpace.pagePadding,
        FloatingPillNavBar.reservedHeight(context) + FolkSpace.lg,
      ),
      child: const GhostScope(
        child: Column(
          children: [
            GhostPlaceholder(
                width: double.infinity, height: 88, showBars: false),
            SizedBox(height: FolkSpace.cardGap),
            ProfileStatTilesGhost(),
            SizedBox(height: FolkSpace.cardGap),
            GhostPlaceholder(
                width: double.infinity, height: 6 * 64 + 12, showBars: false),
            SizedBox(height: FolkSpace.cardGap),
            GhostPlaceholder(
                width: double.infinity, height: 72, showBars: false),
            SizedBox(height: FolkSpace.xxl),
            GhostPlaceholder(
              width: double.infinity,
              height: FolkShape.buttonHeight,
              radius: FolkShape.buttonRadius,
              showBars: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUI(BuildContext context) {
    final text = context.folkText;
    final themeController = context.watch<ThemeModeController>();

    // Name card: the student's name and residence, display only — there is no
    // way to edit either from here.
    final displayName = name ?? "";
    final initial =
        displayName.trim().isEmpty ? null : displayName.trim()[0].toUpperCase();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        // Bottom leaves room for the floating pill navigation.
        padding: EdgeInsets.fromLTRB(
          FolkSpace.pagePadding,
          FolkSpace.sm,
          FolkSpace.pagePadding,
          FloatingPillNavBar.reservedHeight(context) + FolkSpace.lg,
        ),
        child: Column(
          children: [
            /// Profile header
            EntryAnimation(
              index: 0,
              child: GradientCard(
                style: FolkGradientStyle.sky,
                decorate: false,
                padding: const EdgeInsets.all(FolkSpace.lg),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: FolkColors.gradientPlayButton,
                      ),
                      child: initial == null
                          ? const Icon(CupertinoIcons.person_alt, size: 28)
                          : Text(
                              initial,
                              style: text.cardTitle.copyWith(fontSize: 24),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: text.cardTitle.copyWith(fontSize: 22),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role ?? "", // <-- Show role instead of email
                            style: text.onGradientSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: FolkSpace.cardGap),

            /// Three stat tiles: best day of chanting, best day of reading, best
            /// day points (all stored on the user document by the server).
            EntryAnimation(
              index: 1,
              child: ProfileStatTiles(
                bestChantRounds: bestChantRounds,
                bestReadingMinutes: bestReadingMinutes,
                bestDayPoints: bestDayPoints,
              ),
            ),

            const SizedBox(height: FolkSpace.cardGap),

            /// Menu rows
            EntryAnimation(
              index: 2,
              child: _menuCard([
                // Books lives on Journey; the chanting competition and the badges
                // are one page now.
                _menuRow(
                  'My Competitions',
                  "Chanting competition and your badges",
                  Icons.emoji_events_outlined,
                  () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                MyCompetitionsPage(username: name ?? "")));
                  },
                ),

                /// MY GUIDE — display only: the display name of the admin
                /// (Guide or Enabler) the student is assigned to, from the
                /// student's own user document (`guideName`, kept by the
                /// server; the `getMyGuide` callable only backs up a document
                /// not stamped yet), or "Not assigned yet".
                _menuRow(
                  'My Guide',
                  guideRowSubtitle(guideName),
                  CupertinoIcons.person_2,
                  null,
                ),

                /// NOTIFICATIONS — what this student wants to be told
                /// about. Every type defaults to on, so this row only
                /// ever removes noise the student chose to remove.
                _menuRow(
                  'My Notifications',
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

                /// DATE OF BIRTH — always shown. Students who
                /// registered before this field existed see an
                /// invitation to add it rather than a blank or a crash.
                _menuRow(
                  'My Date of Birth',
                  dob == null
                      ? "Tap to add your date of birth"
                      : DateFormat('dd MMM yyyy').format(dob!),
                  CupertinoIcons.gift,
                  _pickAndSaveDob,
                ),

                /// CHANTING COMMITMENT — always shown, editable any
                /// time (unlike Date of Birth above, this never
                /// locks — a student's own commitment can genuinely
                /// change). This is the number the guide's compound
                /// target evaluation checks against.
                _menuRow(
                  'My Commitments',
                  commitmentRounds == null && readingCommitmentMinutes == null
                      ? "Tap to set your daily commitment"
                      : commitmentLine(Commitments(
                          rounds: commitmentRounds ?? kDefaultChantCommitment,
                          readingMinutes: readingCommitmentMinutes)),
                  CupertinoIcons.flame_fill,
                  _editCommitment,
                ),

                /// MY MUSIC - a "Coming soon" page for now (its contents will be specified later).
                _menuRow(
                  'My Music',
                  "Coming soon",
                  CupertinoIcons.music_note_2,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyMusicPage())),
                ),
              ]),
            ),

            const SizedBox(height: FolkSpace.cardGap),

            /// Appearance — replaces the old two-state dark toggle. Stored on
            /// this device only (see ThemeModeController).
            EntryAnimation(
              index: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: FolkSpace.md),
                decoration: _surfaceDecoration(context),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text("Appearance", style: text.chip),
                    ),
                    Expanded(
                      child: FolkSegmented<FolkThemeMode>(
                        value: themeController.mode,
                        onChanged: themeController.setMode,
                        segments: const [
                          FolkSegment(
                              value: FolkThemeMode.light, label: "Light"),
                          FolkSegment(
                              value: FolkThemeMode.dark, label: "Dark"),
                          FolkSegment(
                              value: FolkThemeMode.auto, label: "Auto"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: FolkSpace.xxl),

            /// Logout button
            EntryAnimation(
              index: 4,
              child: _logoutButton(context),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _surfaceDecoration(BuildContext context) {
    final colors = context.folk;
    return BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(FolkShape.cardRadius),
      boxShadow: colors.cardShadows,
    );
  }

  /// One white card holding every menu row.
  Widget _menuCard(List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _surfaceDecoration(context),
      child: Column(children: rows),
    );
  }

  /// One tappable row: an icon tile, a title, a one-line subtitle, a chevron.
  /// Press feedback is the shared 0.97 scale.
  Widget _menuRow(
          String title, String subtitle, IconData iconData, VoidCallback? onTap) =>
      ProfileMenuRow(
          title: title, subtitle: subtitle, icon: iconData, onTap: onTap);

  /// Log Out: a filled red button (the same in light and dark), white label and
  /// icon, opening the same confirm dialog.
  Widget _logoutButton(BuildContext context) =>
      LogoutButton(onPressed: () => showLogoutDialog(context));
}

ButtonStyle _dialogTextButton(FolkColors colors, FolkTypography text) =>
    TextButton.styleFrom(
      minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
      foregroundColor: colors.mutedText,
      textStyle: text.chip,
    );

ButtonStyle _dialogPrimaryButton(FolkColors colors, FolkTypography text) =>
    ElevatedButton.styleFrom(
      minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
      backgroundColor: colors.primaryBg,
      foregroundColor: colors.primaryFg,
      elevation: 0,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      textStyle: text.button,
    );

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
      final colors = dialogContext.folk;
      final text = dialogContext.folkText;
      return AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
        title: Text("Log Out", style: text.topBarTitle),
        content: Text("Do you really want to log out?", style: text.body),
        actions: [
          TextButton(
            style: _dialogTextButton(colors, text),
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text("No"),
          ),
          ElevatedButton(
            style: _dialogPrimaryButton(colors, text),
            onPressed: () async {
              try {
                // This phone's push token leaves this student first, so their reminders
                // can never arrive for whoever signs in next.
                await clearFCMToken();
                GenderDirectory.reset();
                ReportCategory.instance.stop();
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
