// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import '../models/SadhanaReports.dart';
//
// class CompetitionService {
//   final FirebaseFirestore firestore = FirebaseFirestore.instance;
//
//   /// Update the competition scores automatically for a user
//   Future<void> updateScores(
//       String username,
//       SadhanaReport report, {
//         required double extraLecture, // pass directly
//       }) async {
//     try {
//       // 1️⃣ Calculate Base Points
//       double bhagavatam = report.classHearing.toDouble(); // 2/1/0
//       double dailyService = report.dailyServices.toDouble(); // 2/1/0
//       double chanting = report.chantRounds / 4; // 1 point per 4 rounds
//       double bookReading = report.bookReading / 30; // 1 point per 30 mins
//
//       double baseTotal = bhagavatam +
//           dailyService +
//           chanting +
//           bookReading +
//           extraLecture;
//
//       // 2️⃣ Calculate Multipliers
//       double templeMultiplier = _templeMultiplier(report.templeEntry);
//       double japaMultiplier = _japaMultiplier(report.finishTiming);
//       double sleepMultiplier = _sleepMultiplier(report.sleepTiming);
//
//       // 3️⃣ Final Daily Score
//       double totalScore =
//           baseTotal * templeMultiplier * japaMultiplier * sleepMultiplier;
//
//       totalScore = double.parse(totalScore.toStringAsFixed(2));
//
//       // 4️⃣ Firestore reference
//       DocumentReference userDoc =
//       firestore.collection('competition').doc(username);
//
//       // 5️⃣ Atomic Addition Update
//       await userDoc.set({
//         'Name': username,
//
//         // -------- WEEKLY --------
//         'weekly.bhagavatam_class': FieldValue.increment(bhagavatam),
//         'weekly.daily_service': FieldValue.increment(dailyService),
//         'weekly.chanting_rounds': FieldValue.increment(chanting),
//         'weekly.book_reading': FieldValue.increment(bookReading),
//         'weekly.extra_lecture': FieldValue.increment(extraLecture),
//         'weekly.total_score': FieldValue.increment(totalScore),
//         'weekly.days_count': FieldValue.increment(1),
//
//         // multipliers (ADD daily)
//         'weekly.temple_multiplier': FieldValue.increment(templeMultiplier),
//         'weekly.japa_multiplier': FieldValue.increment(japaMultiplier),
//         'weekly.sleeping_multiplier': FieldValue.increment(sleepMultiplier),
//
//         // -------- MONTHLY --------
//         'monthly.bhagavatam_class': FieldValue.increment(bhagavatam),
//         'monthly.daily_service': FieldValue.increment(dailyService),
//         'monthly.chanting_rounds': FieldValue.increment(chanting),
//         'monthly.book_reading': FieldValue.increment(bookReading),
//         'monthly.extra_lecture': FieldValue.increment(extraLecture),
//         'monthly.total_score': FieldValue.increment(totalScore),
//         'monthly.days_count': FieldValue.increment(1),
//
//         // -------- MONTHLY --------
//         'monthly.temple_multiplier': FieldValue.increment(templeMultiplier),
//         'monthly.japa_multiplier': FieldValue.increment(japaMultiplier),
//         'monthly.sleeping_multiplier': FieldValue.increment(sleepMultiplier),
//       }, SetOptions(merge: true));
//
//       debugPrint(
//           'Competition scores updated for $username → Daily Added: $totalScore');
//     } catch (e) {
//       debugPrint('Error updating competition scores: $e');
//     }
//   }
//
//   // ---------------- MULTIPLIERS ----------------
//   double _templeMultiplier(TimeOfDay time) {
//     final minutes = time.hour * 60 + time.minute;
//     if (minutes <= 330) return 1.25; // before 5:30 am
//     if (minutes <= 390) return 1.15; // before 6:30 am
//     if (minutes <= 450) return 1.05; // before 7:30 am
//     return 1.0;
//   }
//
//   double _japaMultiplier(TimeOfDay time) {
//     final minutes = time.hour * 60 + time.minute;
//     if (minutes <= 600) return 1.25; // before 10:00 am
//     if (minutes <= 780) return 1.15; // before 1:00 pm
//     if (minutes <= 960) return 1.05; // before 4:00 pm
//     return 1.0;
//   }
//
//   double _sleepMultiplier(TimeOfDay time) {
//     final minutes = time.hour * 60 + time.minute;
//     if (minutes <= 22 * 60 + 15) return 1.25; // before 10:15 pm
//     if (minutes <= 22 * 60 + 45) return 1.15; // before 10:45 pm
//     if (minutes <= 23 * 60 + 10) return 1.05; // before 11:10 pm
//     return 1.0;
//   }
// }
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/SadhanaReports.dart';

class CompetitionService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Update competition scores for a user
  /// Weekly scores update only if `reportedDate` is in the current week (Sunday-start)
  /// Monthly scores update only if `reportedDate` is in the current month
  Future<void> updateScores(
      String username,
      SadhanaReport report,
      DateTime reportedDate, {
        required double extraLecture, // pass daily extra lecture
      }) async {
    // Check current week and month
    bool currentWeek = isCurrentWeek(reportedDate);
    bool currentMonth = isCurrentMonth(reportedDate);

    if (!currentMonth) {
      debugPrint("Cannot submit scores: reported month is not current");
      return;
    }

    try {
      // 1️⃣ Calculate Base Points
      double bhagavatam = report.classHearing.toDouble();
      double dailyService = report.dailyServices.toDouble();
      double chanting = report.chantRounds / 4; // 1 point per 4 rounds
      double bookReading = report.bookReading / 20; // 1 point per 30 mins

      double baseTotal = bhagavatam +
          dailyService +
          chanting +
          bookReading +
          extraLecture;

      // 2️⃣ Multipliers
      double templeMultiplier = _templeMultiplier(report.templeEntry);
      double japaMultiplier = _japaMultiplier(report.finishTiming);
      double sleepMultiplier = _sleepMultiplier(report.sleepTiming);

      // 3️⃣ Final Daily Score
      double totalScore =
          baseTotal * templeMultiplier * japaMultiplier * sleepMultiplier;
      totalScore = double.parse(totalScore.toStringAsFixed(2));

      // 4️⃣ Firestore reference
      DocumentReference userDoc =
      firestore.collection('competition').doc(username);

      Map<String, dynamic> dataToUpdate = {};

      // Weekly update only if current week
      if (currentWeek) {
        dataToUpdate.addAll({
          'weekly.bhagavatam_class': FieldValue.increment(bhagavatam*templeMultiplier*japaMultiplier*sleepMultiplier),
          'weekly.daily_service': FieldValue.increment(dailyService*templeMultiplier*japaMultiplier*sleepMultiplier),
          'weekly.chanting_rounds': FieldValue.increment(chanting*templeMultiplier*japaMultiplier*sleepMultiplier),
          'weekly.book_reading': FieldValue.increment(bookReading*templeMultiplier*japaMultiplier*sleepMultiplier),
          'weekly.extra_lecture': FieldValue.increment(extraLecture*templeMultiplier*japaMultiplier*sleepMultiplier),
          'weekly.total_score': FieldValue.increment(totalScore),
          'weekly.days_count': FieldValue.increment(1),
          'weekly.temple_multiplier': FieldValue.increment(templeMultiplier),
          'weekly.japa_multiplier': FieldValue.increment(japaMultiplier),
          'weekly.sleeping_multiplier': FieldValue.increment(sleepMultiplier),
        });
      }

      // Monthly update (only if current month)
      dataToUpdate.addAll({
        'monthly.bhagavatam_class': FieldValue.increment(bhagavatam*templeMultiplier*japaMultiplier*sleepMultiplier),
        'monthly.daily_service': FieldValue.increment(dailyService*templeMultiplier*japaMultiplier*sleepMultiplier),
        'monthly.chanting_rounds': FieldValue.increment(chanting*templeMultiplier*japaMultiplier*sleepMultiplier),
        'monthly.book_reading': FieldValue.increment(bookReading*templeMultiplier*japaMultiplier*sleepMultiplier),
        'monthly.extra_lecture': FieldValue.increment(extraLecture*templeMultiplier*japaMultiplier*sleepMultiplier),
        'monthly.total_score': FieldValue.increment(totalScore),
        'monthly.days_count': FieldValue.increment(1),
        'monthly.temple_multiplier': FieldValue.increment(templeMultiplier),
        'monthly.japa_multiplier': FieldValue.increment(japaMultiplier),
        'monthly.sleeping_multiplier': FieldValue.increment(sleepMultiplier),
      });

      await userDoc.set({'Name': username, ...dataToUpdate}, SetOptions(merge: true));

      debugPrint(
          'Scores updated for $username → Daily Added: $totalScore (Week:${currentWeek}, Month:${currentMonth})');
    } catch (e) {
      debugPrint('Error updating competition scores: $e');
    }
  }

  // ---------------- MULTIPLIERS ----------------
  double _templeMultiplier(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    if (minutes <= 330) return 1.25; // before 5:30 am
    if (minutes <= 390) return 1.15; // before 6:30 am
    if (minutes <= 450) return 1.05; // before 7:30 am
    return 1.0;
  }

  double _japaMultiplier(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    if (minutes <= 780) return 1.25; // before 1:00 pm
    if (minutes <= 1080) return 1.15; // before 6:00 pm
    if (minutes <= 1320) return 1.05; // before 10:00 pm
    return 1.0;
  }

  double _sleepMultiplier(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    if (minutes <= 22 * 60 + 15) return 1.25; // before 10:15 pm
    if (minutes <= 22 * 60 + 45) return 1.15; // before 10:45 pm
    if (minutes <= 23 * 60 + 15) return 1.05; // before 11:15 pm
    return 1.0;
  }

  // ---------------- WEEK/MONTH CHECKS ----------------
  DateTime getCurrentWeekStart() {
    final now = DateTime.now();
// Dart weekday: Monday=1 ... Sunday=7
    int daysSinceSunday = (now.weekday - DateTime.sunday + 7) % 7;

    final startOfWeek = now.subtract(Duration(days: daysSinceSunday));

    return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
  }

  bool isCurrentWeek(DateTime reportedDate) {
    final weekStart = getCurrentWeekStart();
    final weekEnd = weekStart.add(const Duration(days: 6));
    return (reportedDate.isAtSameMomentAs(weekStart) ||
        (reportedDate.isAfter(weekStart) && reportedDate.isBefore(weekEnd.add(const Duration(days:1)))));
  }

  bool isCurrentMonth(DateTime reportedDate) {
    final now = DateTime.now();
    return reportedDate.year == now.year && reportedDate.month == now.month;
  }
}