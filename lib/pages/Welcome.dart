import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:folk_app/services/PostAuthRouter.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/AuthButton.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkPageBackground.dart';
import '../widgets/FolkStatusBar.dart';

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
    final colors = context.folk;
    final text = context.folkText;
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
      child: FolkStatusBar(
        child: Scaffold(
          backgroundColor: colors.pageBackground,
          body: FolkPageBackground(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding,
                    FolkSpace.md, FolkSpace.pagePadding, FolkSpace.xxl),
                child: Column(
                  children: [
                    EntryAnimation(
                      index: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
                        child: Image.asset(
                          'assets/images/img.png',
                          width: double.infinity,
                          height: MediaQuery.of(context).size.height * 0.4,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: FolkSpace.xxl),
                    EntryAnimation(
                      index: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome to the FOLK Students App',
                            textAlign: TextAlign.center,
                            style: text.screenTitle.copyWith(fontSize: 28),
                          ),
                          const SizedBox(height: FolkSpace.sm),
                          Text(
                            "Hare Krishna. \nNow it's easy to maintain your Sadhana report daily",
                            textAlign: TextAlign.center,
                            style: text.body.copyWith(height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    EntryAnimation(
                      index: 2,
                      child: AuthButton(
                        primary: true,
                        label: 'Sign in with Google',
                        leading: const _GoogleLogo(),
                        loading: isLoading,
                        onPressed: isLoading ? null : _signInWithGoogle,
                      ),
                    ),
                    const SizedBox(height: FolkSpace.md),
                    // "Sign in with email" — Master Task, 2026-09-14,
                    // Part 1.1. Genuinely visible, not hidden behind a
                    // gesture: Google Play's review team needs a
                    // credential that bypasses Google's own device-
                    // verification prompt, which no in-app setting can
                    // disable, so this has to be a real, discoverable
                    // option, not a workaround reviewers could read as
                    // deceptive.
                    EntryAnimation(
                      index: 3,
                      child: AuthButton(
                        label: 'Sign in with email',
                        leading: Icon(Icons.mail_outline_rounded,
                            size: 20, color: colors.text),
                        onPressed: isLoading
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EmailSignInPage(),
                                  ),
                                );
                              },
                      ),
                    ),
                    const SizedBox(height: FolkSpace.sm),
                    // Subtle, small — a hint for reviewers, never
                    // competing visually with either button above.
                  ],
                ),
              ),
            ),
          ),
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
