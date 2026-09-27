import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:folk_app/services/PostAuthRouter.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sizer/sizer.dart';

import 'EmailSignIn.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() {
      isLoading = true;
    });

    try {
      // 🔹 1. Run the Google Sign-In flow
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the Google account picker.
        setState(() {
          isLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 🔹 2. Sign in to Firebase with the Google credential
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      User? currentUser = userCredential.user;

      // 🔹 3. Everything past this point — does a Firestore doc exist, is
      // registration complete, where to navigate — is the SAME shared path
      // email sign-in also uses (Master Task, 2026-09-14, Part 1.3/1.4).
      // See `PostAuthRouter.dart` for what used to be steps 3-6 here.
      //
      // Bug fix, 2026-09-16 (real-device report): `isLoading` used to clear
      // HERE, before this call, on the reasoning that "the navigation this
      // performs replaces this whole screen either way" — true, but that
      // reasoning ignored that `routeAfterAuthentication` itself is NOT
      // instant (Firestore reads, the `currentUser?.reload()` call, then
      // navigation) — clearing the spinner before awaiting it left the
      // button showing its normal, idle state for however long that takes,
      // a visible dead pause before the screen actually changed. The
      // spinner must stay up for the ENTIRE wait, so `isLoading` is reset
      // only AFTER this call returns (by which point `routeAfterAuthentication`
      // has already navigated away and this widget is normally already
      // unmounted, per the `mounted` guard right below it).
      if (currentUser != null) {
        if (!mounted) return;
        await routeAfterAuthentication(context, currentUser);
      }
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    } on FirebaseAuthException catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      showSnackbar(
          context, 'Google Sign-In failed. Please try again.', Colors.red, Icons.error);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      showSnackbar(
          context, 'Google Sign-In failed. Please try again.', Colors.red, Icons.error);
    }
  }

  /// Back-button fix (2026-09-03) — same bug and same fix as
  /// `pages/Questions.dart`'s own `build()`: no `PopScope`/`WillPopScope`
  /// at all before this fix, so a hardware back press with the keyboard
  /// open could close the app instead of just the keyboard. Same
  /// `PopScope<Object?>` + `canPop: false` idiom, same `viewInsets.bottom >
  /// 0` keyboard-open check — with one addition the other, always-pushed
  /// screens don't need: this page is also rendered with an EMPTY back
  /// stack (`AnimatedLogin`'s own `home:`, `main.dart`), so a plain
  /// `Navigator.of(context).pop()` on keyboard-closed would silently do
  /// nothing there instead of exiting the app — the correct, pre-existing
  /// behaviour for a root screen once the keyboard is already closed.
  /// `Navigator.canPop()` tells the two cases apart at pop-time (this page
  /// is ALSO reached via a plain push from `Profile.dart`'s logout flow,
  /// where it does have a route to pop).
  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          FocusScope.of(context).unfocus();
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: SingleChildScrollView(
        child: SafeArea(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  FadeInDown(
                    delay: const Duration(milliseconds: 800),
                    duration: const Duration(milliseconds: 800),
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/images/img.png',
                          width: 100.w,
                          height: 50.h,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(color: Colors.white),
                    padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 1.6.w),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FadeInUp(
                                  delay: const Duration(milliseconds: 700),
                                  duration: const Duration(milliseconds: 800),
                                  child: Text(
                                    'Welcome to the FOLK Students App',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 25.sp, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                SizedBox(
                                  height: 1.h,
                                ),
                                FadeInUp(
                                  delay: const Duration(milliseconds: 900),
                                  duration: const Duration(milliseconds: 1000),
                                  child: Text(
                                    "Hare Krishna. \nNow it's easy to maintain your Sadhana report daily",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 15.sp, fontWeight: FontWeight.w400),
                                  ),
                                ),
                              ]),
                        ),
                        SizedBox(
                          height: 3.h,
                        ),
                        FadeInUp(
                          delay: const Duration(milliseconds: 1000),
                          duration: const Duration(milliseconds: 1100),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isLoading ? null : _signInWithGoogle,
                                  style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(color: Color(0xFFD2D2D4)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: EdgeInsets.symmetric(vertical: 14)),
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : FadeInUp(
                                          delay: Duration(milliseconds: 1100),
                                          duration: Duration(milliseconds: 1200),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const _GoogleLogo(),
                                              SizedBox(width: 3.w),
                                              Text(
                                                'Sign in with Google',
                                                style: TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'Satoshi',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              )
                            ],
                          ),
                        ),
                        SizedBox(height: 2.h),
                        // "Sign in with email" — Master Task, 2026-09-14,
                        // Part 1.1. Genuinely visible, not hidden behind a
                        // gesture: Google Play's review team needs a
                        // credential that bypasses Google's own device-
                        // verification prompt, which no in-app setting can
                        // disable, so this has to be a real, discoverable
                        // option, not a workaround reviewers could read as
                        // deceptive.
                        //
                        // Restyled (2026-09-15) to match the Google button
                        // above byte-for-byte — same `OutlinedButton.
                        // styleFrom` (background, border, shape, padding),
                        // same `Expanded`-in-a-`Row` full-width layout, same
                        // label TextStyle. Every value below is copied from
                        // that button, not re-derived, so the two can never
                        // silently drift apart in a future edit to one but
                        // not the other. Only the icon and label text
                        // differ, per this task's own instruction.
                        FadeInUp(
                          delay: const Duration(milliseconds: 1150),
                          duration: const Duration(milliseconds: 1250),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isLoading
                                      ? null
                                      : () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const EmailSignInPage(),
                                            ),
                                          );
                                        },
                                  style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(
                                          color: Color(0xFFD2D2D4)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      padding:
                                          EdgeInsets.symmetric(vertical: 14)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.mail_outline_rounded,
                                        size: 20,
                                        color: Color(0xFF835DF1),
                                      ),
                                      SizedBox(width: 3.w),
                                      Text(
                                        'Sign in with email',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Satoshi',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 0.8.h),
                        // Subtle, small — a hint for reviewers, never
                        // competing visually with either button above.
                        Center(
                          child: Text(
                            'For app review access',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'Satoshi',
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            )),
      ),
      ),
    );
  }
}

/// Lightweight text-based stand-in for the Google "G" mark.
/// Replace with the official Google branding asset for full brand compliance.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
