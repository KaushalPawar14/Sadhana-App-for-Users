 import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
 import 'package:flutter/material.dart';
 import 'package:flutter_local_notifications/flutter_local_notifications.dart';
 import 'package:folk_app/pages/CompleteProfile.dart';
import 'package:folk_app/pages/SplashScreen.dart';
 import 'package:folk_app/pages/Welcome.dart';
import 'package:folk_app/services/AccessToken.dart';
import 'package:folk_app/services/DeleteEveryMonthSadhana.dart';
 import 'package:folk_app/services/PushNotification.dart';
 import 'package:folk_app/services/UpdateToken.dart';
 import 'package:folk_app/utils/BottomNavBar.dart';
 import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/utils/MalaLoading.dart';
 import 'package:provider/provider.dart';
 import 'package:sizer/sizer.dart';
 import 'package:firebase_auth/firebase_auth.dart';
 import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/CompetitionResults.dart';

 // Global instance of FlutterLocalNotificationsPlugin
 final FlutterLocalNotificationsPlugin localNotifications =
 FlutterLocalNotificationsPlugin();

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
     await initializeNotifications();
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

 Future<void> initializeNotifications() async {
   const AndroidInitializationSettings androidSettings =
   AndroidInitializationSettings('@mipmap/ic_launcher');
   InitializationSettings settings =
   const InitializationSettings(android: androidSettings);
   await localNotifications.initialize(settings);
 }

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

     // If document does not exist or name is null → Welcome page
     if (!userDoc.exists || userDoc.data()?['name'] == null) return null;

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
         debugShowCheckedModeBanner: false,
         theme: ThemeData(fontFamily: 'Satoshi'),
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
   if(role == "Stay at Hostel")return;

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


