import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:iconly/iconly.dart';
import 'package:sizer/sizer.dart';

import '../main.dart';
import '../services/ForgetPassword.dart';
import 'CompleteProfile.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String email = '', password = '';
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  var focusNodeEmail = FocusNode();
  var focusNodePassword = FocusNode();
  bool isFocusedEmail = false;
  bool isFocusedPassword = false;
  bool isLoading = false;
  bool _isPasswordVisible = false;

  Future<void> LoginProcess() async {
    setState(() {
      isLoading = true;
    });

    try {
      // 🔹 1. Sign in user
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      User? currentUser = userCredential.user;

      if (currentUser != null) {
        // 🔹 2. Check if user document exists using UID (not email)
        DocumentReference userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid);

        DocumentSnapshot userDoc = await userRef.get();

        // 🔹 3. If document doesn't exist, create a basic one
        if (!userDoc.exists) {
          await userRef.set({
            'email': currentUser.email,
            'name': currentUser.displayName?.trim() ?? 'User',
            'role': '',
            'mobileNumber': '',
            'createdByAdmin': false,
          });
        }

        // 🔹 4. Get updated user data
        final data =
            (await userRef.get()).data() as Map<String, dynamic>? ?? {};

        String? role = data['role'];
        String? mobile = data['mobileNumber'];

        setState(() {
          isLoading = false;
        });

        ensureUserCompetitionDocument();

        // 🔹 5. Redirect depending on profile completeness
        if (role == null ||
            role.isEmpty ||
            mobile == null ||
            mobile.isEmpty) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => CompleteProfilePage()),
                (route) => false,
          );
          return;
        }

        if (role == 'Stay at Hostel') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => CurvedNavBar(role)),
                (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => CurvedNavBar(role)),
                (route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        isLoading = false;
      });

      if (e.code == 'user-not-found') {
        showSnackbar(context, 'No user found', Colors.red, Icons.no_accounts);
      } else if (e.code == 'wrong-password') {
        showSnackbar(
            context, 'Wrong password', Colors.red, Icons.no_encryption_outlined);
      } else {
        showSnackbar(
            context,
            'One of the data is not matching. Please try again later.',
            Colors.red,
            Icons.error);
      }
    }
  }

  @override
  void initState() {
    // TODO: implement initState
    focusNodeEmail.addListener(() {
      setState(() {
        isFocusedEmail = focusNodeEmail.hasFocus;
      });
    });
    focusNodePassword.addListener(() {
      setState(() {
        isFocusedPassword = focusNodePassword.hasFocus;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
              child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Container(
              decoration: BoxDecoration(color: Colors.white),
              padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 5.h,
                    ),
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
                    SizedBox(
                      height: 2.h,
                    ),
                    Container(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeInDown(
                            delay: const Duration(milliseconds: 800),
                            duration: const Duration(milliseconds: 900),
                            child: Text(
                              'Hare Krishna...',
                              style: TextStyle(
                                fontSize: 25.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 1.h,
                          ),
                          FadeInDown(
                            delay: const Duration(milliseconds: 700),
                            duration: const Duration(milliseconds: 800),
                            child: Text(
                              'Welcome Back !!',
                              style: TextStyle(
                                fontSize: 25.sp,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          FadeInDown(
                            delay: const Duration(milliseconds: 600),
                            duration: const Duration(milliseconds: 700),
                            child: Text(
                              'Let\'s Sign You In',
                              style: TextStyle(
                                fontSize: 25.sp,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 5.h,
                    ),
                    FadeInDown(
                      delay: const Duration(milliseconds: 700),
                      duration: const Duration(milliseconds: 800),
                      child: const Text(
                        'Email',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FadeInDown(
                      delay: const Duration(milliseconds: 600),
                      duration: const Duration(milliseconds: 700),
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 0.8.h),
                        padding: EdgeInsets.symmetric(
                            horizontal: 5.w, vertical: .3.h),
                        decoration: BoxDecoration(
                            color: isFocusedEmail
                                ? Colors.white
                                : Color(0xFFF1F0F5),
                            border:
                                Border.all(width: 1, color: Color(0xFFD2D2D4)),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              if (isFocusedEmail)
                                BoxShadow(
                                    color: Color(0xFF835DF1).withOpacity(.3),
                                    blurRadius: 4.0,
                                    spreadRadius: 2.0
                                    // Glow Color
                                    )
                            ]),
                        child: TextFormField(
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please Enter Email';
                            }
                            final emailRegex =
                                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                            if (!emailRegex.hasMatch(value)) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                          controller: emailController,
                          style: TextStyle(fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                              border: InputBorder.none, hintText: 'Your Email'),
                          focusNode: focusNodeEmail,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 2.h,
                    ),
                    FadeInDown(
                      delay: const Duration(milliseconds: 500),
                      duration: const Duration(milliseconds: 600),
                      child: const Text(
                        'Password',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FadeInDown(
                      delay: const Duration(milliseconds: 400),
                      duration: const Duration(milliseconds: 500),
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 0.8.h),
                        padding: EdgeInsets.symmetric(
                            horizontal: 5.w, vertical: .3.h),
                        decoration: BoxDecoration(
                            color: isFocusedPassword
                                ? Colors.white
                                : Color(0xFFF1F0F5),
                            border:
                                Border.all(width: 1, color: Color(0xFFD2D2D4)),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              if (isFocusedPassword)
                                BoxShadow(
                                    color: Color(0xFF835DF1).withOpacity(.3),
                                    blurRadius: 4.0,
                                    spreadRadius: 2.0
                                    // Glow Color
                                    )
                            ]),
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
                          style: const TextStyle(fontWeight: FontWeight.w500),
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
                                    _isPasswordVisible =
                                        !_isPasswordVisible; // Toggle visibility
                                  });
                                },
                              ),
                              border: InputBorder.none,
                              hintText: 'Password'),
                          focusNode: focusNodePassword,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 15,
                    ),
                    FadeInDown(
                        delay: const Duration(milliseconds: 400),
                        duration: const Duration(milliseconds: 500),
                        child: forgetPassword()),
                    SizedBox(
                      height: 10,
                    ),
                    FadeInUp(
                      delay: const Duration(milliseconds: 300),
                      duration: const Duration(milliseconds: 400),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_formKey.currentState!.validate()) {
                                  setState(() {
                                    email = emailController.text;
                                    password = passwordController.text;
                                  });
                                  await LoginProcess();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  textStyle: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Satoshi'),
                                  backgroundColor: Color(0xFF835DF1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: 16)),
                              child: isLoading
                                  ? Center(child: const CircularProgressIndicator())
                                  : FadeInUp(
                                      delay: const Duration(milliseconds: 200),
                                      duration:
                                          const Duration(milliseconds: 300),
                                      child: Text(
                                        'Login',
                                        style: TextStyle(color: Colors.white),
                                      )),
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ))
        ],
      ),
    );
  }
}
