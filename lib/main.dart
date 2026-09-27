 import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
 import 'package:flutter/material.dart';
 import 'package:folk_app/pages/CompleteProfile.dart';
import 'package:folk_app/pages/SplashScreen.dart';
 import 'package:folk_app/pages/Welcome.dart';
import 'package:folk_app/services/DeleteEveryMonthSadhana.dart';
import 'package:folk_app/services/QuestionsSeed.dart';
 import 'package:folk_app/services/PushNotification.dart';
 import 'package:folk_app/services/UpdateToken.dart';
 import 'package:folk_app/utils/BottomNavBar.dart';
 import 'package:folk_app/utils/ColorProvider.dart';
 import 'package:folk_app/utils/FloatingAssistantOverlay.dart';
 import 'package:folk_app/utils/VoiceRoomOverlay.dart';
import 'package:folk_app/utils/NotificationRouter.dart';
import 'package:folk_app/utils/MalaLoading.dart';
 import 'package:provider/provider.dart';
 import 'package:sizer/sizer.dart';
 import 'package:firebase_auth/firebase_auth.dart';
 import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/CompetitionResults.dart';

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
   await Firebase.initializeApp();

   runApp(
     ChangeNotifierProvider(
       create: (_) => ColorProvider(),
       child: Sizer(
         builder: (context, orientation, deviceType) {
           return MaterialApp(
             debugShowCheckedModeBanner: false,
             theme: ThemeData(fontFamily: 'Satoshi'),
             home: const SplashScreen(), // 👈 Start with splash
           );
         },
       ),
     ),
   );

   // 🔥 Run everything else in background (non-blocking)
   Future.microtask(() async {
     await FirebaseCM().initNotifications();
     await updateFCMToken();
     await ensureUserCompetitionDocument();
     final CompetitionResultService service = CompetitionResultService();
     await service.checkAndRunWeeklyLazyTrigger(
       service.generateWeeklyTop3,
     );
     await service.checkAndRunMonthlyLazyTrigger(
       service.generateTop3Monthly,
     );
     User? user = FirebaseAuth.instance.currentUser;

     if (user != null) {
       await initializeQuestionsIfNeeded(user.uid);
     }
     runMonthlyDeleteInBackground();
   });
 }

 void runMonthlyDeleteInBackground() {
   unawaited(deletePreviousToPreviousMonthData('sadhana-reports'));
   unawaited(deletePreviousToPreviousMonthData('hostel-sadhana'));
   unawaited(deleteScorecard());
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

   @override
   void initState() {
     super.initState();
     checkSignInStatus();
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
         debugShowCheckedModeBanner: false,
         theme: ThemeData(fontFamily: 'Satoshi'),
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
           future: isUserDataComplete(),
           builder: (context, snapshot) {
             if (snapshot.connectionState == ConnectionState.waiting) {
               return const Scaffold(
                 body: CustomLoader()
               );
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
 Future<void> ensureUserCompetitionDocument() async {

   final currentUser = FirebaseAuth.instance.currentUser;
   if (currentUser == null) return;

   // 🔹 Fetch name from users collection
   final userDoc = await FirebaseFirestore.instance
       .collection('users')
       .doc(currentUser.uid)
       .get();

   if (!userDoc.exists) return;

   final username = userDoc.data()?['name'];
   final role = userDoc.data()?['role'];
   if (username == null || username.toString().isEmpty) return;
   // Localites (Master Task, 2026-09-03) are excluded exactly like Hostel
   // residents — the competition/leaderboard feature is FOLK-only.
   if(role == "Stay at Hostel" || role == "Stay at Localite")return;

   print("First test passed");

   final docRef =
   FirebaseFirestore.instance.collection('competition').doc(username);

   await FirebaseFirestore.instance.runTransaction((transaction) async {
     final snapshot = await transaction.get(docRef);

     if (!snapshot.exists) {
       transaction.set(docRef, {
         "Name": username,

         "weekly.total_score": 0.0,
         "weekly.bhagavatam_class": 0.0,
         "weekly.daily_service": 0.0,
         "weekly.chanting_rounds": 0.0,
         "weekly.book_reading": 0.0,
         "weekly.extra_lecture": 0.0,
         "weekly.temple_multiplier": 0.0,
         "weekly.japa_multiplier": 0.0,
         "weekly.sleeping_multiplier": 0.0,
         "weekly.days_count": 0,

         "monthly.total_score": 0.0,
         "monthly.bhagavatam_class": 0.0,
         "monthly.daily_service": 0.0,
         "monthly.chanting_rounds": 0.0,
         "monthly.book_reading": 0.0,
         "monthly.extra_lecture": 0.0,
         "monthly.temple_multiplier": 0.0,
         "monthly.japa_multiplier": 0.0,
         "monthly.sleeping_multiplier": 0.0,
         "monthly.days_count": 0,
       });
       print("All test failed");
     }
     print("Second test passed");
   });
 }


