import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/services/PostAuthRouter.dart';
import 'package:folk_app/utils/Snackbar.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/PrimaryButton.dart';
import '../widgets/SadhanaFormWidgets.dart';

/// Email/password sign-in — Master Task, 2026-09-14, Part 1. Added
/// specifically so Google Play's reviewers have a way in: signing into a
/// Gmail account from a reviewer's own device triggers Google's own
/// device-verification prompt, which no setting in this app can disable,
/// and which has caused two rejections. The Email/Password provider is
/// already enabled on this Firebase project — it backed the previous login
/// system (`pages/Login.dart`, now dead code) and existing accounts were
/// created under it, so nothing needed enabling in Firebase itself.
///
/// This is a SIGN-IN form only, deliberately — there is no self-serve
/// "create account with email/password" flow here, matching the task's own
/// scope (the one account this needs to authenticate is created directly in
/// the Firebase Console — see Part 4 of that task). `pages/Login.dart`'s own
/// password field enforces sign-UP-style complexity rules (8+ characters,
/// upper/lower/digit) — copying that into a SIGN-IN form would incorrectly
/// reject an existing, already-valid password that simply predates those
/// rules, so this form only requires the fields be non-empty and leaves
/// Firebase itself to say whether the password is actually correct.
///
/// Once signed in, this calls the exact same [routeAfterAuthentication]
/// Google sign-in uses (`Welcome.dart`) — one shared path, not two.
class EmailSignInPage extends StatefulWidget {
  const EmailSignInPage({super.key});

  @override
  State<EmailSignInPage> createState() => _EmailSignInPageState();
}

class _EmailSignInPageState extends State<EmailSignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
      // Newer Firebase Auth versions return one generic code for both a
      // wrong password and an unknown account, to avoid revealing which —
      // handled here so either SDK behaviour shows a clear message.
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      default:
        return 'Sign-in failed. Please try again.';
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = userCredential.user;

      // Bug fix, 2026-09-16 (real-device report) — same flaw as
      // `Welcome.dart`'s own Google sign-in: `_isLoading` used to clear
      // BEFORE this await, so the button returned to its idle "Sign in"
      // state for however long `routeAfterAuthentication` actually takes
      // (Firestore reads, the `currentUser?.reload()` call, then
      // navigation) — a visible dead pause before the screen changed. The
      // spinner now stays up for the whole wait; `_isLoading` resets only
      // after this call returns (by which point navigation has already
      // happened and this widget is normally already unmounted).
      if (user != null) {
        if (!mounted) return;
        await routeAfterAuthentication(context, user);
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showSnackbar(context, _messageFor(e), Colors.red, Icons.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showSnackbar(
        context,
        'Sign-in failed. Please check your connection and try again.',
        Colors.red,
        Icons.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    // Same back-button-vs-keyboard fix used by Login.dart/Welcome.dart/
    // Questions.dart — a hardware back press with the keyboard open should
    // close the keyboard, not the screen.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          FocusScope.of(context).unfocus();
          return;
        }
        Navigator.of(context).pop();
      },
      child: FolkScaffold(
        title: 'Sign in with email',
        onBack: () => Navigator.pop(context),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding,
              FolkSpace.xl, FolkSpace.pagePadding, FolkSpace.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email', style: text.bodyStrong),
                const SizedBox(height: FolkSpace.sm),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: text.body,
                  decoration: sadhanaFieldDecoration(context, hint: 'Your Email'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    final emailRegex =
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: FolkSpace.xl),
                Text('Password', style: text.bodyStrong),
                const SizedBox(height: FolkSpace.sm),
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  style: text.body,
                  decoration: sadhanaFieldDecoration(
                    context,
                    hint: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _isPasswordVisible
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: colors.mutedText,
                        size: 22,
                      ),
                      onPressed: () => setState(
                          () => _isPasswordVisible = !_isPasswordVisible),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                PrimaryButton(
                  label: 'Sign in',
                  loading: _isLoading,
                  onPressed: _isLoading ? null : _signIn,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
