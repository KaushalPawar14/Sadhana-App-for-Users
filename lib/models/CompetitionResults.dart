// CompetitionResults.dart

import 'dart:ffi';

import 'package:cloud_firestore/cloud_firestore.dart';

// ------------------- MODELS -------------------

class UserCompetitionResult {
  final String name;
  final double totalScore;
  final double bhagavatam;
  final double dailyService;
  final double chantingRounds;
  final double bookReading;
  final double extraLecture;
  final double templeMultiplier;
  final double japaMultiplier;
  final double sleepingMultiplier;

  UserCompetitionResult({
    required this.name,
    required this.totalScore,
    required this.bhagavatam,
    required this.dailyService,
    required this.chantingRounds,
    required this.bookReading,
    required this.extraLecture,
    required this.templeMultiplier,
    required this.japaMultiplier,
    required this.sleepingMultiplier,
  });

  Map<String, dynamic> toMap() => {
    "name": name,
    "total_score": totalScore,
    "bhagavatam": bhagavatam,
    "daily_service": dailyService,
    "chanting_rounds": chantingRounds,
    "book_reading": bookReading,
    "extra_lecture": extraLecture,
    "temple_multiplier": templeMultiplier,
    "japa_multiplier": japaMultiplier,
    "sleeping_multiplier": sleepingMultiplier,
  };

  factory UserCompetitionResult.fromMap(Map<String, dynamic> map) =>
      UserCompetitionResult(
        name: map['name'],
        totalScore: map['total_score'],
        bhagavatam: map['bhagavatam'],
        dailyService: map['daily_service'],
        chantingRounds: map['chanting_rounds'],
        bookReading: map['book_reading'],
        extraLecture: map['extra_lecture'],
        templeMultiplier: map['temple_multiplier'],
        japaMultiplier: map['japa_multiplier'],
        sleepingMultiplier: map['sleeping_multiplier'],
      );
}

class WeeklyResults {
  final String weekId; // YYYY-WW
  final List<UserCompetitionResult> topUsers;
  final DateTime generatedAt;

  WeeklyResults({
    required this.weekId,
    required this.topUsers,
    required this.generatedAt,
  });

  Map<String, dynamic> toMap() => {
    "topUsers": topUsers.map((u) => u.toMap()).toList(),
    "generatedAt": generatedAt.toIso8601String(),
  };
}

class MonthlyResults {
  final String monthId; // YYYY-MM
  final List<UserCompetitionResult> topUsers;
  final DateTime generatedAt;

  MonthlyResults({
    required this.monthId,
    required this.topUsers,
    required this.generatedAt,
  });

  Map<String, dynamic> toMap() => {
    "topUsers": topUsers.map((u) => u.toMap()).toList(),
    "generatedAt": generatedAt.toIso8601String(),
  };
}

// ------------------- FIRESTORE SERVICE -------------------

class CompetitionResultService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> saveWeeklyResults(WeeklyResults results) async {
    final docRef = firestore.collection('competition-results').doc('weekly').collection('weeks').doc(results.weekId);
    await docRef.set(results.toMap());

    // Prune older weeks
    final weeksSnapshot = await firestore.collection('competition-results').doc('weekly').collection('weeks').orderBy('generatedAt').get();
    if (weeksSnapshot.docs.length > 3) {
      final docsToDelete = weeksSnapshot.docs.sublist(0, weeksSnapshot.docs.length - 3);
      for (var doc in docsToDelete) {
        await doc.reference.delete();
      }
    }
  }

  Future<List<UserCompetitionResult>> generateTop3Monthly() async {
    final snapshot = await firestore
        .collection('competition')
        .orderBy(FieldPath(['monthly.total_score']), descending: true)
        .limit(3)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return UserCompetitionResult(
        name: data['Name'] ?? '',
        totalScore: ((data['monthly.total_score'] ?? 0) as num).toDouble(),
        bhagavatam: (data['monthly.bhagavatam_class'] ?? 0).toDouble(),
        dailyService: (data['monthly.daily_service'] ?? 0).toDouble(),
        chantingRounds: (data['monthly.chanting_rounds'] ?? 0).toDouble(),
        bookReading: (data['monthly.book_reading'] ?? 0).toDouble(),
        extraLecture: (data['monthly.extra_lecture'] ?? 0).toDouble(),
        templeMultiplier: (data['monthly.temple_multiplier'] ?? 1).toDouble(),
        japaMultiplier: (data['monthly.japa_multiplier'] ?? 1).toDouble(),
        sleepingMultiplier: (data['monthly.sleeping_multiplier'] ?? 1).toDouble(),
      );
    }).toList();
  }

  Future<List<UserCompetitionResult>> generateWeeklyTop3() async {
    final snapshot = await firestore
        .collection('competition')
        .orderBy(FieldPath(['weekly.total_score']), descending: true)
        .limit(3)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return UserCompetitionResult(
        name: data['Name'] ?? '',
        totalScore: ((data['weekly.total_score'] ?? 0) as num).toDouble(),
        bhagavatam: (data['weekly.bhagavatam_class'] ?? 0).toDouble(),
        dailyService: (data['weekly.daily_service'] ?? 0).toDouble(),
        chantingRounds: (data['weekly.chanting_rounds'] ?? 0).toDouble(),
        bookReading: (data['weekly.book_reading'] ?? 0).toDouble(),
        extraLecture: (data['weekly.extra_lecture'] ?? 0).toDouble(),
        templeMultiplier: (data['weekly.temple_multiplier'] ?? 1).toDouble(),
        japaMultiplier: (data['weekly.japa_multiplier'] ?? 1).toDouble(),
        sleepingMultiplier: (data['weekly.sleeping_multiplier'] ?? 1).toDouble(),
      );
    }).toList();
  }

  Future<void> saveMonthlyResults(MonthlyResults results) async {
    final docRef = firestore.collection('competition-results').doc('monthly').collection('months').doc(results.monthId);
    await docRef.set(results.toMap());

    // Prune older months
    final monthsSnapshot = await firestore.collection('competition-results').doc('monthly').collection('months').orderBy('generatedAt').get();
    if (monthsSnapshot.docs.length > 2) {
      final docsToDelete = monthsSnapshot.docs.sublist(0, monthsSnapshot.docs.length - 2);
      for (var doc in docsToDelete) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> updateWeeklyUsers() async {
    final now = DateTime.now();

    int daysSinceSunday = now.weekday % 7;
    final weekStart = now.subtract(Duration(days: daysSinceSunday));
    final weekId = "${weekStart.year}-W${_weekNumber(weekStart)}";

    // ---- collect users ----
    final snapshot = await firestore.collection('competition').get();
    List<Map<String, dynamic>> participants = [];

    for (var doc in snapshot.docs) {
      final data = doc.data();

      Map<String, dynamic> weeklyFields = {};
      data.forEach((key, value) {
        if (key.startsWith('weekly.')) {
          weeklyFields[key] = value;
        }
      });

      if (weeklyFields.isNotEmpty) {
        participants.add({
          "username": doc.id,
          ...weeklyFields,
        });
      }
    }

    // ---- save week doc ----
    final weekRef = firestore
        .collection('competition-results')
        .doc('weekly-participants')
        .collection('weeks')
        .doc(weekId);

    await weekRef.set({
      "participants": participants,
      "generatedAt": DateTime.now().toIso8601String(),
    });

    // ---- prune (keep only 3 weeks) ----
    final weeksSnapshot = await firestore
        .collection('competition-results')
        .doc('weekly-participants')
        .collection('weeks')
        .orderBy('generatedAt')
        .get();

    if (weeksSnapshot.docs.length > 3) {
      final toDelete =
      weeksSnapshot.docs.sublist(0, weeksSnapshot.docs.length - 3);

      for (var doc in toDelete) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> updateMonthlyUsers() async {
    final now = DateTime.now();

    final firstDay = DateTime(now.year, now.month, 1);
    final monthId =
        "${firstDay.year}-${firstDay.month.toString().padLeft(2, '0')}";

    // ---- collect users ----
    final snapshot = await firestore.collection('competition').get();
    List<Map<String, dynamic>> participants = [];

    for (var doc in snapshot.docs) {
      final data = doc.data();

      Map<String, dynamic> monthlyFields = {};
      data.forEach((key, value) {
        if (key.startsWith('monthly.')) {
          monthlyFields[key] = value;
        }
      });

      if (monthlyFields.isNotEmpty) {
        participants.add({
          "username": doc.id,
          ...monthlyFields,
        });
      }
    }

    // ---- save month doc ----
    final monthRef = firestore
        .collection('competition-results')
        .doc('monthly-participants')
        .collection('months')
        .doc(monthId);

    await monthRef.set({
      "participants": participants,
      "generatedAt": DateTime.now().toIso8601String(),
    });

    // ---- prune (keep only 2 months) ----
    final monthsSnapshot = await firestore
        .collection('competition-results')
        .doc('monthly-participants')
        .collection('months')
        .orderBy('generatedAt')
        .get();

    if (monthsSnapshot.docs.length > 2) {
      final toDelete =
      monthsSnapshot.docs.sublist(0, monthsSnapshot.docs.length - 2);

      for (var doc in toDelete) {
        await doc.reference.delete();
      }
    }
  }

  // ------------------- LAZY TRIGGERS -------------------

  int _weekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final difference = date.difference(firstDayOfYear).inDays;
    return ((difference + firstDayOfYear.weekday) / 7).ceil();
  }

  Future<void> checkAndRunWeeklyLazyTrigger(
      Future<List<UserCompetitionResult>> Function() generateTopUsers) async {

    final now = DateTime.now();
    print("checkAndRunWeeklyLazyTrigger is started");

    // --- 1️⃣ Compute Tuesday-to-Monday week start ---
    int daysSinceSunday = now.weekday % 7;
    final weekStart = now.subtract(Duration(days: daysSinceSunday));
    final weekId = "${weekStart.year}-W${_weekNumber(weekStart)}";

    // --- 2️⃣ Reference to weekly_meta to check last finalized week ---
    final metaRef = firestore.collection('competition-results').doc('weekly_meta');
    final metaSnap = await metaRef.get();
    final lastFinalized = metaSnap.data()?['last_week_finalized'];

    // Already finalized for this week → do nothing
    if (lastFinalized == weekId) return;
    await metaRef.set({
      'last_week_finalized': weekId,
    });
    // --- 3️⃣ Generate top users ---
    final topUsers = await generateTopUsers();
    // Debug print in console
    for (var u in topUsers) {
      print("📊 User: ${u.name}");
    }
    if (topUsers.isEmpty) return;
    print("checkAndRunWeeklyLazyTrigger is on the way");

    // only index 0 gets weekly winner badge
    final winnerName = topUsers[0].name;

// find user in users collection
    final userQuery = await firestore
        .collection("users")
        .where("name", isEqualTo: winnerName)
        .limit(1)
        .get();

    if (userQuery.docs.isNotEmpty && topUsers[0].totalScore != 0) {
      final userDocId = userQuery.docs.first.id;

      await firestore.collection("users").doc(userDocId).set(
      {
        "weekly-winner": FieldValue.increment(1),
      },
      SetOptions(merge: true),
      );
    }

    // --- 4️⃣ Save weekly results ---
    final results = WeeklyResults(
      weekId: weekId,
      topUsers: topUsers,
      generatedAt: DateTime.now(),
    );
    await saveWeeklyResults(results);
    await updateWeeklyUsers();
    // --- 5️⃣ Reset weekly fields for all users ---
    await _resetWeeklyFields();

    // --- 6️⃣ Mark this week as finalized ---
  }

  Future<void> _resetWeeklyFields() async {
    final snapshot = await firestore.collection('competition').get();

    for (var doc in snapshot.docs) {
      await doc.reference.update({
        FieldPath(['weekly.total_score']): 0,
        FieldPath(['weekly.bhagavatam_class']): 0,
        FieldPath(['weekly.daily_service']): 0,
        FieldPath(['weekly.chanting_rounds']): 0,
        FieldPath(['weekly.book_reading']): 0,
        FieldPath(['weekly.extra_lecture']): 0,
        FieldPath(['weekly.temple_multiplier']): 0,
        FieldPath(['weekly.japa_multiplier']): 0,
        FieldPath(['weekly.sleeping_multiplier']): 0,
        FieldPath(['weekly.days_count']): 0,
      });
    }
    print("All Values for weekly reset successfully");
  }

  Future<void> _resetMonthlyFields() async {
    final snapshot = await firestore.collection('competition').get();

    for (var doc in snapshot.docs) {
      await doc.reference.update({
        FieldPath(['monthly.total_score']): 0,
        FieldPath(['monthly.bhagavatam_class']): 0,
        FieldPath(['monthly.daily_service']): 0,
        FieldPath(['monthly.chanting_rounds']): 0,
        FieldPath(['monthly.book_reading']): 0,
        FieldPath(['monthly.extra_lecture']): 0,
        FieldPath(['monthly.temple_multiplier']): 0,
        FieldPath(['monthly.japa_multiplier']): 0,
        FieldPath(['monthly.sleeping_multiplier']): 0,
        FieldPath(['monthly.days_count']): 0,
      });
    }
  }

  Future<void> checkAndRunMonthlyLazyTrigger(
      Future<List<UserCompetitionResult>> Function() generateTopUsers,
      ) async {
    final now = DateTime.now();

    // nearest 1st date of current month
    final firstDayOfCurrentMonth = DateTime(now.year, now.month, 1);

    // monthId = YYYY-MM from that 1st date
    final monthId =
        "${firstDayOfCurrentMonth.year}-${firstDayOfCurrentMonth.month.toString().padLeft(2, '0')}";

    final metaRef =
    firestore.collection('competition-results').doc('monthly_meta');

    final metaSnap = await metaRef.get();
    final lastFinalized = metaSnap.data()?['last_month_finalized'];

    if (lastFinalized == monthId) return;

    await metaRef.set({
      'last_month_finalized': monthId,
    });

    print("Now Monthly has started to work!!!");

    final topUsers = await generateTopUsers();
    if (topUsers.isEmpty) return;

    // badge field names according to rank
    final badgeFields = [
      "monthly-gold",
      "monthly-silver",
      "monthly-bronze",
    ];

    for (int i = 0; i < topUsers.length && i < 3; i++) {

      if (topUsers[0].totalScore == 0) break;
      final winnerName = topUsers[i].name;

      // find user in "users" collection by Name
      final userQuery = await firestore
          .collection("users")
          .where("name", isEqualTo: winnerName)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) continue;

      final userDocId = userQuery.docs.first.id;

      // increment badge count
      await firestore.collection("users").doc(userDocId).set({
        badgeFields[i]: FieldValue.increment(1),
      }, SetOptions(merge: true));
    }

    final results = MonthlyResults(
      monthId: monthId,
      topUsers: topUsers,
      generatedAt: DateTime.now(),
    );

    await saveMonthlyResults(results);
    print("Now we are going to update this month");
    await updateMonthlyUsers();
    await _resetMonthlyFields();
  }
}