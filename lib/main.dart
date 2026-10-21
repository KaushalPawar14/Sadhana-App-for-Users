import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
 import 'package:flutter/material.dart';
 import 'package:flutter/services.dart';
 import 'package:folk_app/pages/CompleteProfile.dart';
import 'package:folk_app/pages/BookReaderPage.dart' show ReaderLook;
import 'package:folk_app/pages/SplashScreen.dart';
 import 'package:folk_app/pages/Welcome.dart';
import 'package:folk_app/services/QuestionsSeed.dart';
 import 'package:folk_app/services/PushNotification.dart';
 import 'package:folk_app/services/UpdateToken.dart';
 import 'package:folk_app/utils/BottomNavBar.dart';
 import 'package:folk_app/theme/FolkTheme.dart';
 import 'package:folk_app/theme/FolkTokens.dart';
 import 'package:folk_app/theme/ThemeModeController.dart';
 import 'package:folk_app/utils/ColorProvider.dart';
 import 'package:folk_app/utils/AssistantRouteVisibility.dart';
 import 'package:folk_app/utils/FloatingAssistantOverlay.dart';
 import 'package:folk_app/utils/VoiceRoomOverlay.dart';
import 'package:folk_app/utils/NotificationRouter.dart';
import 'package:folk_app/utils/ReadingSessionStore.dart';
import 'package:folk_app/widgets/StartupWaiting.dart';
 import 'package:provider/provider.dart';
 import 'package:sizer/sizer.dart';
 import 'package:firebase_auth/firebase_auth.dart';
 import 'package:cloud_firestore/cloud_firestore.dart';

 /// Deep-link routing (Master Task, 2026-09-10 — Part 3). Attached to the
 /// INNER `MaterialApp` below (`_AnimatedLoginState.build()`), not the
 /// outer one in `main()` — the outer `MaterialApp`'s own Navigator only
 /// ever holds two routes for the app's entire lifetime (`SplashScreen`,
 /// then a `pushReplacement` to `AnimatedLogin`; see `SplashScreen.dart`),
 /// while the inner one is where every real screen (`CurvedNavBar` and
 /// everything pushed from within it) actually lives — the one a
 /// notification tap needs to push onto. `utils/NotificationRouter.dart`
 /// uses this same key rather than declaring its own, so there is exactly
 /// one Navigator a deep link can ever target.
 final GlobalKey<NavigatorState> studentNavigatorKey =
     GlobalKey<NavigatorState>();

 void main() async {
   WidgetsFlutterBinding.ensureInitialized();
   // Portrait only (the manifest locks it too, so there is no rotation flash
   // before Flutter starts).
   await SystemChrome.setPreferredOrientations(
       const [DeviceOrientation.portraitUp]);
   await Firebase.initializeApp();
   final themeController = await ThemeModeController.load();
   // The reading mode last used on this device, so a book opens in its own colours from the first frame.
   await ReaderLook.primeFromDevice();

   runApp(
     MultiProvider(
       providers: [
         ChangeNotifierProvider<ThemeModeController>.value(
           value: themeController,
         ),
         // Follows the Light/Dark/Auto setting, so every screen that still
         // reads ColorProvider changes with it.
         ChangeNotifierProvider<ColorProvider>(
           create: (context) => ColorProvider(loadLegacyPrefs: false)
             ..bindTo(context.read<ThemeModeController>()),
         ),
       ],
       child: Sizer(
         builder: (context, orientation, deviceType) {
           return MaterialApp(
             debugShowCheckedModeBanner: false,
             theme: FolkTheme.light,
             darkTheme: FolkTheme.dark,
             themeMode: context.watch<ThemeModeController>().themeMode,
             themeAnimationDuration:
                 FolkMotion.of(context, FolkMotion.theme),
             home: const SplashScreen(), // 👈 Start with splash
           );
         },
       ),
     ),
   );

   // 🔥 Run everything else in background (non-blocking)
   Future.microtask(() async {
     // Reading time of a book that was open when the app was killed is added to its day now (waits for a sign-in itself; never blocks).
     unawaited(recoverLeftoverReading());
     await FirebaseCM().initNotifications();
     await updateFCMToken();
     watchFCMToken(); // follow sign-ins, token rotation and sign-out from here on
     User? user = FirebaseAuth.instance.currentUser;

     if (user != null) {
       await initializeQuestionsIfNeeded(user.uid);
     }
     // Monthly sadhana/scorecard cleanup now runs server-side (monthlySadhanaRetention).
   });
 }

 // ⚠️ `initializeNotifications()` (a second, separate call to
 // `FlutterLocalNotificationsPlugin().initialize(...)`, with NO
 // `onDidReceiveNotificationResponse` callback) used to run here, right
 // after `FirebaseCM().initNotifications()` already registered that exact
 // callback. Both Dart-side plugin instances talk to the SAME native
 // platform channel, so this second, callback-less `initialize()` call
 // was overwriting the first's tap-handler registration on every launch —
 // Part 1's second real bug (alongside the splash-race one fixed above):
 // a notification tapped while the app was already in the FOREGROUND
 // (the one launch state that goes through a locally-shown notification,
 // not `getInitialMessage`/`onMessageOpenedApp`) had its routing silently
 // erased before the user ever tapped it. Removed entirely — this
 // function did nothing `FirebaseCM().initNotifications()` doesn't already
 // do correctly. (`services/LocalNotifications.dart` defines an unrelated,
 // already-unimported, already-dead copy of this same function name —
 // confirmed by grep, not touched here, since it was never being called by
 // anything and is not part of this bug.)

 class AnimatedLogin extends StatefulWidget {
   const AnimatedLogin({super.key});

   @override
   State<AnimatedLogin> createState() => _AnimatedLoginState();
 }

 class _AnimatedLoginState extends State<AnimatedLogin> {
   User? currentUser;
   String role = '';
   late final Future<bool?> _dataComplete;

   @override
   void initState() {
     super.initState();
     checkSignInStatus();
     // Asked ONCE. `build()` used to call `isUserDataComplete()` inline, so
     // every rebuild (the Light/Dark/Auto switch rebuilds this widget through
     // `context.watch<ThemeModeController>()`) handed the FutureBuilder a new
     // future; it dropped back to "waiting", showed the loader, and re-created
     // `CurvedNavBar` on its default tab.
     _dataComplete = isUserDataComplete();
     // Splash-race fix (Master Task, 2026-09-10 — Part 1/2) — see
     // `markAppReady()`'s own doc comment in `utils/NotificationRouter.dart`
     // for exactly why a post-frame callback here, rather than a call from
     // `SplashScreen`'s own timer, is the correct signal.
     WidgetsBinding.instance.addPostFrameCallback((_) => markAppReady());
   }

   void checkSignInStatus() {
     setState(() {
       currentUser = FirebaseAuth.instance.currentUser;
     });
   }

   // Check if required user data is complete
   Future<bool?> isUserDataComplete() async {
     if (currentUser == null) return false;

     final userDoc = await FirebaseFirestore.instance
         .collection('users')
         .doc(currentUser!.uid)
         .get();

     // If document does not exist or name is missing → Welcome page. Part 3
     // hardening (Master Task, 2026-09-14): also treats a blank string the
     // same as a missing field — `''` was never actually written by any
     // live code path (the placeholder `Welcome.dart`/`EmailSignIn.dart`
     // create omits `name` entirely rather than setting it blank), but
     // checking `.isEmpty` too, matching `PostAuthRouter.dart`'s own
     // completeness check exactly, closes that gap defensively rather than
     // relying on it never happening.
     final nameValue = userDoc.data()?['name'];
     if (!userDoc.exists || nameValue == null || (nameValue is String && nameValue.isEmpty)) {
       return null;
     }

     final userData = userDoc.data()!;
     role = userData['role'] ?? '';
     final mobileNumber = userData['mobileNumber'] ?? '';

     // Return true only if all required fields are complete
     return role.isNotEmpty && mobileNumber.isNotEmpty;
   }

   @override
   Widget build(BuildContext context) {
     return Sizer(
       builder: (context, orientation, deviceType) => MaterialApp(
         navigatorKey: studentNavigatorKey,
         // Lets the floating assistant button hide while the assistant screen
         // itself is on top.
         navigatorObservers: [AssistantRouteVisibility.instance],
         debugShowCheckedModeBanner: false,
         theme: FolkTheme.light,
         darkTheme: FolkTheme.dark,
         themeMode: context.watch<ThemeModeController>().themeMode,
         themeAnimationDuration: FolkMotion.of(context, FolkMotion.theme),
         // Floating assistant button (Stage 5, 2026-08-24) and the RDUA
         // Friends "who's in the room" icon (same root level, same reason —
         // see FloatingAssistantOverlay.dart / VoiceRoomOverlay.dart) both
         // wrap whatever route this MaterialApp's own Navigator is showing,
         // so each persists across every push/pop instead of belonging to
         // one screen. Nested rather than siblings so both can independently
         // sit anywhere on screen without one clipping the other's hit area.
         builder: (context, navChild) => FloatingAssistantOverlay(
           child: VoiceRoomOverlay(
             child: navChild ?? const SizedBox.shrink(),
           ),
         ),
         home: currentUser != null
             ? FutureBuilder<bool?>(
           future: _dataComplete,
           builder: (context, snapshot) {
             if (snapshot.connectionState == ConnectionState.waiting) {
               // No spinner: the tab host's own ghost frame from the first
               // frame (see `widgets/StartupWaiting.dart`).
               return StartupWaiting(signedIn: currentUser != null);
             } else if (snapshot.hasData) {
               if (snapshot.data == null) {
                 // Name missing → WelcomePage
                 return WelcomePage();
               } else if (snapshot.data == true) {
                 // Data complete → pass role to CurvedNavBar
                 return CurvedNavBar(role);
               } else {
                 // Missing some fields → CompleteProfilePage
                 return CompleteProfilePage();
               }
             } else {
               // Fallback → WelcomePage
               return WelcomePage();
             }
           },
         )
             : WelcomePage(),
       ),
     );
   }
 }

 // The competition document is written by the server from the student's reports
 // (functions/scoreRecompute.js); the app no longer creates or updates it.
