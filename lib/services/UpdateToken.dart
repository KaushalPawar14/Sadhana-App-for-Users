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

// -----------------------------------------------------------------------------
// Keeping the push token with the person who is actually signed in.
//
// The token used to be written once, at app start. So: someone who signed in later in the
// same session, a new student who had just finished registering (no name yet at start), or
// a second account on the same phone got no notifications until the app was restarted; and
// the first account on a phone kept the token for good, so its reminders arrived while the
// other account was open (one phone's token was found under two student names).
//
// Now the token is (re)written every time the signed-in student changes, whenever the
// push service rotates it, and after registration; and it is removed at sign-out. The
// server also moves a token to the newest account that registers it.
// -----------------------------------------------------------------------------

String? _tokenOwnerUid;
bool _tokenWatchStarted = false;

// Starts the listeners once (safe to call again).
void watchFCMToken() {
  if (_tokenWatchStarted) return;
  _tokenWatchStarted = true;
  FirebaseAuth.instance.userChanges().listen((user) {
    if (user == null) {
      _tokenOwnerUid = null;
      return;
    }
    if (_tokenOwnerUid == user.uid) return;
    _tokenOwnerUid = user.uid;
    updateFCMToken();
  });
  FirebaseMessaging.instance.onTokenRefresh.listen((_) => updateFCMToken());
}

// At sign-out, BEFORE signing out: this student's document stops holding the phone's token
// and the phone gets a fresh one, so nothing meant for this student can reach whoever
// signs in next. Never throws (sign-out must always work).
Future<void> clearFCMToken() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final name = doc.data()?['name'];
      if (name is String && name.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('notification')
            .doc(name)
            .set({'FCMToken': FieldValue.delete()}, SetOptions(merge: true));
      }
    }
  } catch (_) {}
  try {
    await FirebaseMessaging.instance.deleteToken();
  } catch (_) {}
  _tokenOwnerUid = null;
}
