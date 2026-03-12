import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/utils/Snackbar.dart';

class forgetPassword extends StatefulWidget {
  const forgetPassword({super.key});

  @override
  State<forgetPassword> createState() => _forgetPasswordState();
}

class _forgetPasswordState extends State<forgetPassword> {
  TextEditingController emailController = TextEditingController();
  final auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 35),
      child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          onTap: () {
            myDialogBox(context);
          },
          child: const Text(
            'Forget Password ?',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF835DF1)),
          ),
        ),
      ),
    );
  }

  // void myDialogBox(BuildContext context) {
  //   showDialog(
  //       context: context,
  //       builder: (BuildContext context) {
  //         return Dialog(
  //           shape:
  //               RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  //           child: Container(
  //             decoration: BoxDecoration(
  //                 color: Colors.white, borderRadius: BorderRadius.circular(20)),
  //             padding: EdgeInsets.all(20),
  //             child: Column(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 Row(
  //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                   children: [
  //                     Container(),
  //                     Text(
  //                       "Forgot your password",
  //                       style: TextStyle(
  //                           fontWeight: FontWeight.bold, fontSize: 18),
  //                     ),
  //                     IconButton(
  //                         onPressed: () {
  //                           Navigator.pop(context);
  //                         },
  //                         icon: Icon(Icons.close))
  //                   ],
  //                 ),
  //                 SizedBox(
  //                   height: 20,
  //                 ),
  //                 TextField(
  //                   controller: emailController,
  //                   decoration: InputDecoration(
  //                       border: OutlineInputBorder(),
  //                       labelText: "Enter the email address"),
  //                 ),
  //                 SizedBox(
  //                   height: 20,
  //                 ),
  //                 ElevatedButton(
  //                     style: ElevatedButton.styleFrom(
  //                         backgroundColor: Color(0xFF835DF1)),
  //                     onPressed: () async {
  //                       await auth
  //                           .sendPasswordResetEmail(email: emailController.text)
  //                           .then((value) {
  //                         showSnackbar(
  //                             context,
  //                             "Sent reset password link on gmail",
  //                             CupertinoColors.activeGreen,
  //                             Icons.mail_lock_outlined);
  //                       }).then((value) {
  //                         Navigator.pop(context);
  //                       }).onError((error, stackTrace) {
  //                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  //                             backgroundColor: Colors.red,
  //                             content: Text(
  //                               error.toString(),
  //                               style: TextStyle(fontSize: 20),
  //                             )));
  //                       });
  //                     },
  //                     child: const Text(
  //                       "Send",
  //                       style: TextStyle(
  //                           fontWeight: FontWeight.bold,
  //                           fontSize: 16,
  //                           color: Colors.white),
  //                     ))
  //               ],
  //             ),
  //           ),
  //         );
  //       });
  // }
  void myDialogBox(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40), // Spacer on the left for alignment
                    Flexible(
                      child: Text(
                        "Forgot your password",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Enter the email address",
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF835DF1),
                  ),
                  onPressed: () async {
                    await auth
                        .sendPasswordResetEmail(email: emailController.text)
                        .then((value) {
                      showSnackbar(
                        context,
                        "Sent reset password link on gmail",
                        CupertinoColors.activeGreen,
                        Icons.mail_lock_outlined,
                      );
                    }).then((value) {
                      Navigator.pop(context);
                    }).onError((error, stackTrace) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        backgroundColor: Colors.red,
                        content: Text(
                          error.toString(),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ));
                    });
                  },
                  child: const Text(
                    "Send",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}
