import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> addBookForLevel({
  required String username,
  required String level, // "level1", "level2", "level3"
  required String bookName,
  required String startDate,
  String? endDate, // optional
  required bool madeNotes,
}) async {
  final firestore = FirebaseFirestore.instance;

  await firestore
      .collection('booksRead')
      .doc(username)
      .collection(level)  // 👈 level1/level2/level3
      .add({
    'bookName': bookName,
    'startDate': startDate,
    'endDate': endDate,
    'madeNotes': madeNotes,
  });
}
