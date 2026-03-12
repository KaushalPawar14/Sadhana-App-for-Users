import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:sizer/sizer.dart';

import '../utils/MalaLoading.dart';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController roleController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();

  bool isLoading = true;
  bool isSubmitting = false;

  String? username;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // ✅ Directly fetch doc using UID
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        if (userData['role'] != null) roleController.text = userData['role'];
        if (userData['mobileNumber'] != null) {
          mobileController.text = userData['mobileNumber'];
        }
        username = (userData['name'] ?? '').toString().trim();
      } else {
        // If user doc doesn’t exist, we can get displayName or set default
        username = currentUser.displayName ?? "Unknown";
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isSubmitting = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      String userRole = roleController.text;

      // ✅ Always update the document with UID (no duplicates ever)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'name': (username != null && username!.trim().isNotEmpty)
            ? username!.trim()
            : (currentUser.displayName != null && currentUser.displayName!.trim().isNotEmpty)
            ? currentUser.displayName!.trim()
            : "Unknown",
        'email': currentUser.email,
        'role': userRole,
        'mobileNumber': mobileController.text,
        'uid': currentUser.uid, // helpful for reference
      }, SetOptions(merge: true));

      showSnackbar(context, "Profile Updated Successfully", Colors.green, Icons.thumb_up);

      // ✅ Conditional navigation
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => CurvedNavBar(userRole)),
            (route) => false,
      );
    } catch (e) {
      print('Error updating profile: $e');
      showSnackbar(context, "Process Failed", Colors.redAccent, Icons.thumb_down);
    }

    setState(() {
      isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? CustomLoader()
          : SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 4.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Complete Your Profile',
                    style: TextStyle(
                        fontSize: 24.sp, fontWeight: FontWeight.bold)),
                SizedBox(height: 4.h),

                // Role
                Text('Role',
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 1.h),
                DropdownButtonFormField<String>(
                  value: roleController.text.isNotEmpty
                      ? roleController.text
                      : null,
                  items: const [
                    DropdownMenuItem(
                        value: 'Stay at FOLK',
                        child: Text('Stay at FOLK')),
                    DropdownMenuItem(
                        value: 'Stay at Hostel',
                        child: Text('Stay at Hostel')),
                  ],
                  onChanged: roleController.text.isEmpty
                      ? (val) => roleController.text = val ?? ''
                      : null, // make readonly once selected
                  validator: (val) => (roleController.text.isEmpty)
                      ? 'Select your role'
                      : null,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 5.w, vertical: 1.5.h),
                  ),
                ),

                SizedBox(height: 2.h),

                // Mobile number
                Text('Mobile Number',
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 1.h),
                TextFormField(
                  controller: mobileController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Enter your mobile number',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 5.w, vertical: 1.5.h),
                  ),
                  enabled: mobileController.text.isEmpty,
                  validator: (val) {
                    if (mobileController.text.isEmpty) {
                      return 'Mobile number is required';
                    }
                    if (!RegExp(r'^\d{10}$')
                        .hasMatch(mobileController.text)) {
                      return 'Enter a valid 10-digit number';
                    }
                    return null;
                  },
                ),

                SizedBox(height: 4.h),

                ElevatedButton(
                  onPressed: isSubmitting ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? CustomLoader()
                      : Center(
                    child: Text(
                      'Submit',
                      style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
