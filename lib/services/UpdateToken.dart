// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
//
// class FCMTokenService {
//   final FirebaseAuth _auth = FirebaseAuth.instance;
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
//
//   Future<void> updateFCMToken() async {
//     User? user = _auth.currentUser;
//     if (user == null) return;
//
//     String? token = await _firebaseMessaging.getToken();
//     if (token != null) {
//       await _firestore.collection("notification").doc(user.displayName).set({
//         "fcm_token": token,
//         "updated_at": FieldValue.serverTimestamp(),
//       }, SetOptions(merge: true));
//     }
//   }
// }
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future <void> updateFCMToken() async {
  try {
    // Get the FCM token for the admin device
    String? Token = await FirebaseMessaging.instance.getToken();
    User? currentUser = FirebaseAuth.instance.currentUser;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser?.uid)
        .get();

    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    if (Token != null) {
      // Store the FCM token in Firestore under the 'admin' document
      await FirebaseFirestore.instance.collection('notification').doc(userName).set({
        'FCMToken': Token,
      }, SetOptions(merge: true));
      print('Admin FCM token updated successfully: $Token');
    } else {
      print('Failed to retrieve FCM token.');
    }
  } catch (e) {
    print('Error updating FCM token: $e');
  }
}
