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
    User? currentUser = FirebaseAuth.instance.currentUser;
    // Nobody signed in (first launch, after logout): there is no token document
    // to write, and `doc(null)` would point at a random one.
    if (currentUser == null) return;
    String? Token = await FirebaseMessaging.instance.getToken();

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    final nameValue = userDoc.data()?['name'];
    // A student who has not finished registration has no name yet: no token
    // document (the name is its id) rather than a junk "Unknown User" one.
    if (nameValue is! String || nameValue.isEmpty) return;
    String userName = nameValue;

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
