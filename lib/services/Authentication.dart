import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/StudentNameGuard.dart';

/// Unreachable dead code (zero call sites anywhere in this app — kept per
/// this project's convention of not deleting architecturally-relevant
/// code), fixed defensively in case it is ever resurrected.
class AuthServices {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> signUpUser(
      {required String email,
        required String password,
        required String name}) async {
    String res = 'Error occurred';
    try {
      final normalizedName = normalizeStudentName(name);
      bool nameExists = await checkIfNameExists(normalizedName);
      if (nameExists) {
        res = kNameTakenMessage;
      }else if (normalizedName.isNotEmpty || password.isNotEmpty || email.isNotEmpty) {
        UserCredential userCredential = await _auth
            .createUserWithEmailAndPassword(email: email, password: password);

        // `name` is written exactly ONCE, right here, at account creation.
        // Do NOT add a way to edit it later — see StudentNameGuard.dart for
        // why every name-keyed collection depends on it never changing
        // after this point.
        await _firestore.collection("users").doc(userCredential.user!.uid).set(
            {'name': normalizedName, 'email': email, 'uid': userCredential.user!.uid});
        res = 'success';
      }
    } catch (e) {
      return e.toString();
    }
    return res;
  }
}

/// Kept as a thin wrapper (rather than replacing every call site with
/// [isStudentNameTaken] directly) since this is unreachable dead code and
/// minimizing the diff here isn't load-bearing either way.
Future<bool> checkIfNameExists(String name) => isStudentNameTaken(name);

