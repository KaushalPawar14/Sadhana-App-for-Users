import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthServices {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> signUpUser(
      {required String email,
        required String password,
        required String name}) async {
    String res = 'Error occurred';
    try {
      bool nameExists = await checkIfNameExists(name);
      if (nameExists) {
        res = 'This name is already taken';
      }else if (name.isNotEmpty || password.isNotEmpty || email.isNotEmpty) {
        UserCredential userCredential = await _auth
            .createUserWithEmailAndPassword(email: email, password: password);

        await _firestore.collection("users").doc(userCredential.user!.uid).set(
            {'name': name, 'email': email, 'uid': userCredential.user!.uid});
        res = 'success';
      }
    } catch (e) {
      return e.toString();
    }
    return res;
  }
}

Future<bool> checkIfNameExists(String name) async {
  final querySnapshot = await FirebaseFirestore.instance
      .collection('users') // Replace with your collection name
      .where('name', isEqualTo: name)
      .get();
  print('Query snapshot: ${querySnapshot.docs.length} documents found');
  print('Query snapshot data: ${querySnapshot.docs.map((doc) => doc.data()).toList()}');

  return querySnapshot.docs.isNotEmpty;
}

