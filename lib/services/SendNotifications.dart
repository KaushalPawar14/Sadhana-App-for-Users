import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'PushNotification.dart';

void sendNotificationToAdmin(String date, String time, String sleep, String text) async {
  try {
    User? currentUser = FirebaseAuth.instance.currentUser;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser?.uid)
        .get();

    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    // Folk guides
    List<String> folkGuides = ["SBSD", "MMGD"];

    Set<String> adminTokens = {}; // use Set to avoid duplicates

    for (String folkGuide in folkGuides) {
      final adminDoc = await FirebaseFirestore.instance
          .collection('adminUsers')
          .doc(folkGuide)
          .get();

      String? token = adminDoc.data()?['fcmToken'];

      if (token != null && token.isNotEmpty) {
        adminTokens.add(token); // auto avoids duplicates
      }
    }

    // Send notification
    for (String token in adminTokens) {
      FirebaseCM().sendTokenNotification(
        token,
        "$userName for $date\n🪔 - $time and 😴 - $sleep",
        text,
      );
    }

    print("Notifications sent to all admins");

  } catch (e) {
    print('Error sending notification: $e');
  }
}
