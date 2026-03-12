import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/pages/CompleteProfile.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:iconly/iconly.dart';
import 'package:sizer/sizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../services/Authentication.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterPage> {
  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  var focusNodeName = FocusNode();
  var focusNodeEmail = FocusNode();
  var focusNodePassword = FocusNode();
  bool isFocusedName = false;
  bool isFocusedEmail = false;
  bool isFocusedPassword = false;
  bool isLoading = false;
  bool _isPasswordVisible = false;

  final _formKey = GlobalKey<FormState>();

  // Role Dropdown
  String? selectedRole;
  List<String> roles = ['Stay at FOLK', 'Stay at Hostel'];

  Future<bool> isNameAlreadyTaken(String name) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('name', isEqualTo: name.trim())
        .get();

    return snapshot.docs.isNotEmpty;
  }

  void signUpUser() async {
    if (_formKey.currentState!.validate() && selectedRole != null) {
      setState(() => isLoading = true);

      String name = nameController.text.trim();
      String email = emailController.text.trim();
      String password = passwordController.text.trim();

      if (name.isEmpty) {
        showSnackbar(context, "Name cannot be empty", Colors.red, Icons.error);
        return;
      }
      // 🔥 CHECK IF NAME ALREADY EXISTS
      bool nameExists = await isNameAlreadyTaken(nameController.text);

      if (nameExists) {
        setState(() => isLoading = false);
        showSnackbar(context, "Username already taken", Colors.red, Icons.error);
        return;
      }

      try {
        // 🔥 CREATE USER WITH FIREBASE AUTH
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final User? currentUser = userCredential.user;

        if (currentUser != null) {
          // 🔥 STORE USER IN FIRESTORE
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .set({
            'uid': currentUser.uid,
            'name': name,
            'email': email,
            'role': selectedRole,
            'createdAt': Timestamp.now(),
          });

          await ensureUserCompetitionDocument();
        }

        setState(() => isLoading = false);

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => CompleteProfilePage()),
              (route) => false,
        );

      } on FirebaseAuthException catch (e) {
        setState(() => isLoading = false);

        if (e.code == 'email-already-in-use') {
          showSnackbar(context, "Email already registered", Colors.red, Icons.error);
        } else if (e.code == 'invalid-email') {
          showSnackbar(context, "Invalid email format", Colors.red, Icons.error);
        } else if (e.code == 'weak-password') {
          showSnackbar(context, "Password is too weak", Colors.red, Icons.error);
        } else {
          showSnackbar(context, e.message ?? "Signup failed", Colors.red, Icons.error);
        }
      }
    } else if (selectedRole == null) {
      showSnackbar(context, "Please select a role", Colors.red, Icons.error);
    } else {
      showSnackbar(context, "Please fix the errors in the form", Colors.red, Icons.error);
    }
  }


  @override
  void initState() {
    super.initState();
    focusNodeName.addListener(() => setState(() => isFocusedName = focusNodeName.hasFocus));
    focusNodeEmail.addListener(() => setState(() => isFocusedEmail = focusNodeEmail.hasFocus));
    focusNodePassword.addListener(() => setState(() => isFocusedPassword = focusNodePassword.hasFocus));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 4.h),
            decoration: BoxDecoration(color: Colors.white),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeInDown(
                    delay: const Duration(milliseconds: 900),
                    duration: const Duration(milliseconds: 1000),
                    child: IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: Icon(
                          IconlyBroken.arrow_left,
                          size: 3.6.h,
                        )),
                  ),
                  SizedBox(height: 2.h),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FadeInDown(
                        delay: const Duration(milliseconds: 800),
                        duration: const Duration(milliseconds: 900),
                        child: Text(
                          'Hare Krishna...',
                          style: TextStyle(fontSize: 25.sp, fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(height: 1.h),
                      FadeInDown(
                        delay: const Duration(milliseconds: 700),
                        duration: const Duration(milliseconds: 800),
                        child: Text(
                          'Folk Surat',
                          style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w400),
                        ),
                      ),
                      FadeInDown(
                        delay: const Duration(milliseconds: 600),
                        duration: const Duration(milliseconds: 700),
                        child: Text(
                          'Welcome you !',
                          style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w400),
                        ),
                      )
                    ],
                  ),
                  SizedBox(height: 6.h),
                  FadeInDown(
                    delay: const Duration(milliseconds: 700),
                    duration: const Duration(milliseconds: 800),
                    child: const Text(
                      'Name',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  FadeInDown(
                    delay: const Duration(milliseconds: 600),
                    duration: const Duration(milliseconds: 700),
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 0.8.h),
                      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: .3.h),
                      decoration: BoxDecoration(
                        color: isFocusedName ? Colors.white : Color(0xFFF1F0F5),
                        border: Border.all(width: 1, color: Color(0xFFD2D2D4)),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          if (isFocusedName)
                            BoxShadow(
                                color: Color(0xFF835DF1).withOpacity(.3),
                                blurRadius: 4.0,
                                spreadRadius: 2.0)
                        ],
                      ),
                      child: TextFormField(
                        controller: nameController,
                        style: TextStyle(fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Your Full Name'
                        ),
                        focusNode: focusNodeName,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please Enter Name';
                          }
                          // Check if first letter is uppercase
                          if (!RegExp(r'^[A-Z]').hasMatch(value.trim())) {
                            // Show snackbar
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              showSnackbar(context, "First letter of name must be capital", Colors.red, Icons.error);
                            });
                            return '';
                          }
                          return null;
                        },
                      ),

                    ),
                  ),
                  SizedBox(height: 3.h),
                  FadeInDown(
                    delay: const Duration(milliseconds: 500),
                    duration: const Duration(milliseconds: 600),
                    child: const Text(
                      'Email',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  FadeInDown(
                    delay: const Duration(milliseconds: 400),
                    duration: const Duration(milliseconds: 500),
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 0.8.h),
                      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: .3.h),
                      decoration: BoxDecoration(
                        color: isFocusedEmail ? Colors.white : Color(0xFFF1F0F5),
                        border: Border.all(width: 1, color: Color(0xFFD2D2D4)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please Enter Email';
                          }
                          final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                          if (!emailRegex.hasMatch(value)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                        controller: emailController,
                        style: TextStyle(fontWeight: FontWeight.w500),
                        decoration:
                        InputDecoration(border: InputBorder.none, hintText: 'Your Email'),
                        focusNode: focusNodeEmail,
                      ),
                    ),
                  ),
                  SizedBox(height: 3.h),
                  FadeInDown(
                    delay: const Duration(milliseconds: 300),
                    duration: const Duration(milliseconds: 400),
                    child: const Text(
                      'Password',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  FadeInDown(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 0.8.h),
                      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: .3.h),
                      decoration: BoxDecoration(
                        color: isFocusedPassword ? Colors.white : Color(0xFFF1F0F5),
                        border: Border.all(width: 1, color: Color(0xFFD2D2D4)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password cannot be empty';
                          }
                          if (value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          if (!RegExp(r'[A-Z]').hasMatch(value)) {
                            return 'Password must include at least one uppercase letter';
                          }
                          if (!RegExp(r'[a-z]').hasMatch(value)) {
                            return 'Password must include at least one lowercase letter';
                          }
                          if (!RegExp(r'[0-9]').hasMatch(value)) {
                            return 'Password must include at least one number';
                          }
                          return null;
                        },
                        controller: passwordController,
                        obscureText: !_isPasswordVisible,
                        style: TextStyle(fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey,
                              size: 16.sp,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                          border: InputBorder.none,
                          hintText: 'Password',
                        ),
                        focusNode: focusNodePassword,
                      ),
                    ),
                  ),
                  SizedBox(height: 3.h),
                  // Role Dropdown
                  FadeInDown(
                    delay: const Duration(milliseconds: 100),
                    duration: const Duration(milliseconds: 300),
                    child: const Text(
                      'Role',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(height: 0.8.h),
                  FadeInDown(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 5.w),
                      decoration: BoxDecoration(
                        color: Color(0xFFF1F0F5),
                        border: Border.all(width: 1, color: Color(0xFFD2D2D4)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(border: InputBorder.none),
                        hint: Text("Select Role"),
                        items: roles.map((role) {
                          return DropdownMenuItem<String>(
                            value: role,
                            child: Text(role),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedRole = val;
                          });
                        },
                        validator: (value) {
                          if (value == null) return "Please select a role";
                          return null;
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  FadeInUp(
                    delay: const Duration(milliseconds: 600),
                    duration: const Duration(milliseconds: 700),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              signUpUser();
                            },
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Color(0xFF835DF1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: isLoading
                                ? Center(child: const CircularProgressIndicator())
                                : FadeInUp(
                              delay: const Duration(milliseconds: 700),
                              duration: const Duration(milliseconds: 800),
                              child: Text(
                                'Register',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
