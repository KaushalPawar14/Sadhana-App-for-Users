import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../pages/CompleteProfile.dart';
import '../utils/BottomNavBar.dart';

/// The ONE post-authentication path — Master Task, 2026-09-14, Parts 1 & 3.
///
/// Before this, `Welcome.dart`'s Google sign-in had this logic written
/// inline, and nothing else used it. Adding a second sign-in method (email/
/// password) without extracting this would have meant a second, separately
/// maintained copy of "does this user have a complete profile" — exactly
/// the two-diverging-paths problem this task's Part 1.3 asks to avoid. Both
/// `Welcome.dart` (Google) and `EmailSignIn.dart` (email/password) call this
/// same function once they have a real, signed-in [User]; neither contains
/// any of its own post-auth logic any more.
///
/// This is also, unchanged, the fix for Part 3 (a signed-in user with no
/// Firestore document): whether that is a genuinely new account, a student
/// who was fully deleted (`Guides/.../StudentDeletion.dart`, 2026-09-14) and
/// is signing back in, or a registration that never finished writing its
/// first document, all three are indistinguishable here and all three are
/// handled the same way — a bare placeholder is created and the user is
/// sent to [CompleteProfilePage] to register, exactly as if they were new.
/// No error, no crash, nothing left half-done.
Future<void> routeAfterAuthentication(BuildContext context, User user) async {
  // Works around a real, documented firebase_auth/FlutterFire bug (2026-09-16
  // investigation): `authStateChanges()` does not reliably emit an event
  // right after `signInWithCredential`/`signInWithEmailAndPassword` complete
  // in the SAME process — see
  // https://github.com/firebase/flutterfire/issues/10159 and
  // https://github.com/FirebaseExtended/flutterfire/issues/3968. This is why
  // `FloatingAssistantOverlay`/`VoiceRoomOverlay` (both gated on the signed-
  // in user via a Firebase Auth stream, listening continuously from before
  // sign-in) never showed their icon until a full restart — restarting just
  // happens to take the RELIABLE path (a fresh subscription reading an
  // already-persisted session), not because anything about navigation
  // differs. `.reload()` is Firebase's own documented workaround: it forces
  // a real reload event, which `userChanges()` (not `authStateChanges()`,
  // which is why both overlay files were switched to it) is guaranteed to
  // react to. Failure here is non-fatal — worst case, the icon needs the
  // restart it always needed before this fix; nothing else in this function
  // depends on it.
  try {
    await FirebaseAuth.instance.currentUser?.reload();
  } catch (_) {
    // Non-fatal — see comment above.
  }

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final userDoc = await userRef.get();

  if (!userDoc.exists) {
    await userRef.set({
      'email': user.email,
      'createdByAdmin': false,
    });
  }

  final data = (await userRef.get()).data() ?? {};

  final name = data['name'] as String?;
  final role = data['role'] as String?;
  final mobile = data['mobileNumber'] as String?;

  await ensureUserCompetitionDocument();

  if (!context.mounted) return;

  if (name == null ||
      name.isEmpty ||
      role == null ||
      role.isEmpty ||
      mobile == null ||
      mobile.isEmpty) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => CompleteProfilePage()),
      (route) => false,
    );
    return;
  }

  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => CurvedNavBar(role)),
    (route) => false,
  );
}
