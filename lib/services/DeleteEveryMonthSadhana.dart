import 'package:cloud_firestore/cloud_firestore.dart';

String getMonthName(int month) {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];
  return months[month - 1];
}

Future<void> deletePreviousToPreviousMonthData(String rootCollection) async {
  final now = DateTime.now();

  // 👉 Calculate previous-to-previous month
  int targetMonth = now.month - 2;
  int targetYear = now.year;

  if (targetMonth <= 0) {
    targetMonth += 12;
    targetYear -= 1;
  }

  print("🧹 Deleting FULL month: ${getMonthName(targetMonth)}-$targetYear");

  final firestore = FirebaseFirestore.instance;

  final usersSnapshot = await firestore.collection('users').get();

  WriteBatch batch = firestore.batch();
  int deleteCount = 0;
  int totalDeleted = 0;

  for (final userDoc in usersSnapshot.docs) {
    final userName = userDoc.data()['name']?.toString().trim();

    // 🚨 Prevent empty doc id crash
    if (userName == null || userName.isEmpty) {
      print("⚠️ Skipping user with empty name: ${userDoc.id}");
      continue;
    }

    final datesRef = firestore
        .collection(rootCollection)
        .doc(userName)
        .collection('dates');

    final datesSnapshot = await datesRef.get();

    for (final dateDoc in datesSnapshot.docs) {
      final id = dateDoc.id; // dd-mm-yyyy

      final parts = id.split('-');
      if (parts.length != 3) {
        print("⚠️ Invalid format: $id");
        continue;
      }

      final docMonth = int.tryParse(parts[1]);
      final docYear = int.tryParse(parts[2]);

      if (docMonth == null || docYear == null) continue;

      // ✅ ONLY delete exact target month & year
      if (docMonth == targetMonth && docYear == targetYear) {
        print("🗑 Deleting: $id (User: $userName)");

        batch.delete(dateDoc.reference);
        deleteCount++;
        totalDeleted++;

        // Firestore limit
        if (deleteCount == 500) {
          await batch.commit();
          batch = firestore.batch();
          deleteCount = 0;
        }
      }
    }
  }

  if (deleteCount > 0) {
    await batch.commit();
  }

  print("✅ [$rootCollection] Deleted $totalDeleted documents of ${getMonthName(targetMonth)}-$targetYear");
}

Future<void> deleteScorecard() async{
  final firestore = FirebaseFirestore.instance;
  final now = DateTime.now();

  // 👉 Calculate previous-to-previous month
  int targetMonth = now.month;
  int targetYear = now.year;
// 🔹 Only delete scorecard for odd months
  final scorecardRef = firestore.collection('scorecard');
  final flagDocRef = scorecardRef.doc('flag');

// 1️⃣ Fetch the metadata from the flag document
  final flagSnapshot = await flagDocRef.get();
  final currentFlag = flagSnapshot.data()?['month_year'];

// Compose the current month-year string
  final currentMonthYear = "$targetMonth-$targetYear";

  print("Target month: $targetMonth");
  print("Target year: $targetYear");
  print("Current month-year flag: $currentFlag");

// 2️⃣ Check if the flag matches
  if (targetMonth.isOdd && currentFlag != currentMonthYear) {
    print("🗑 Deleting entire scorecard for odd month: $targetMonth-$targetYear");

    // Fetch all docs in scorecard
    final scorecardSnapshot = await scorecardRef.get();

    WriteBatch batch = firestore.batch();

    for (var doc in scorecardSnapshot.docs) {
      // Skip the flag document itself
      if (doc.id == 'flag') continue;

      batch.delete(doc.reference);
    }

    // Commit deletion
    await batch.commit();
    print("✅ Scorecard cleared for $currentMonthYear");

    // 3️⃣ Recreate empty scorecard with updated flag
    await flagDocRef.set({'month_year': currentMonthYear});
    print("✅ Flag updated in scorecard");
  } else {
    print("ℹ️ Scorecard not deleted. Flag matches or month is even.");
  }
}