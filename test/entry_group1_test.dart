import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/EmailSignIn.dart';
import 'package:folk_app/pages/SplashScreen.dart';
import 'package:folk_app/pages/Welcome.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/AuthButton.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Phase 11c group 1: Splash, Welcome and email sign-in, at 360 dp, text scale
// 1.0 / 1.3 / 1.6, light and dark. None of them touches Firebase until a
// sign-in is attempted; where a test does attempt one, there is no Firebase app,
// so the sign-in fails at once and exercises each screen's own failure path.
void phone(WidgetTester tester, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Widget app(Widget home, {bool dark = false, bool reduce = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text scale $scale, 360 dp';

      group('Welcome — $s', () {
        testWidgets('renders; both buttons at least 56 dp; nothing overflows', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const WelcomePage(), dark: dark));
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text('Welcome to the FOLK Students App'), findsOneWidget);
          expect(find.textContaining("Now it's easy to maintain your Sadhana report daily"), findsOneWidget);
          final buttons = tester.widgetList<AuthButton>(find.byType(AuthButton)).toList();
          expect(buttons.map((b) => b.label), ['Sign in with Google', 'Sign in with email']);
          for (final b in find.byType(AuthButton).evaluate()) {
            await tester.ensureVisible(find.byWidget(b.widget));
            expect(tester.getSize(find.byWidget(b.widget)).height, greaterThanOrEqualTo(56));
          }
        });

        testWidgets('"Sign in with email" still opens the email sign-in page', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const WelcomePage(), dark: dark, reduce: true));
          await tester.pump();
          await tester.ensureVisible(find.text('Sign in with email'));
          await tester.tap(find.text('Sign in with email'));
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          expect(find.byType(EmailSignInPage), findsOneWidget);
        });
      });

      group('Welcome — Google sign-in paths — $s', () {
        const channel = MethodChannel('plugins.flutter.io/google_sign_in');
        tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

        testWidgets('busy while Google answers; a failure shows the same message and frees both buttons', (tester) async {
          phone(tester, scale);
          final answer = Completer<Object?>();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) => answer.future);
          await tester.pumpWidget(app(const WelcomePage(), dark: dark, reduce: true));
          await tester.pump();
          await tester.ensureVisible(find.text('Sign in with Google'));
          await tester.tap(find.text('Sign in with Google'));
          await tester.pump();
          // busy: the Google button shows a spinner and the email one is disabled
          expect(find.descendant(of: find.byType(AuthButton).first, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
          expect(tester.widgetList<AuthButton>(find.byType(AuthButton)).every((b) => b.onPressed == null), isTrue);
          answer.completeError(PlatformException(code: 'sign_in_failed'));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(find.text('Google Sign-In failed. Please try again.'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.widgetList<AuthButton>(find.byType(AuthButton)).every((b) => b.onPressed != null), isTrue);
          await tester.pump(const Duration(seconds: 4));
        });

        testWidgets('cancelling the Google account picker just frees the buttons, no message', (tester) async {
          phone(tester, scale);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => null);
          await tester.pumpWidget(app(const WelcomePage(), dark: dark, reduce: true));
          await tester.pump();
          await tester.ensureVisible(find.text('Sign in with Google'));
          await tester.tap(find.text('Sign in with Google'));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(find.text('Google Sign-In failed. Please try again.'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.widgetList<AuthButton>(find.byType(AuthButton)).every((b) => b.onPressed != null), isTrue);
        });
      });

      group('Email sign-in — $s', () {
        testWidgets('renders with a back button, two fields and Sign in; nothing overflows', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const EmailSignInPage(), dark: dark));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text('Sign in with email'), findsOneWidget);
          expect(find.text('Email'), findsOneWidget);
          expect(find.text('Password'), findsWidgets);
          expect(find.byType(TextFormField), findsNWidgets(2));
          expect(find.bySemanticsLabel('Back'), findsOneWidget);
          await tester.ensureVisible(find.byType(PrimaryButton));
          expect(tester.getSize(find.byType(PrimaryButton)).height, greaterThanOrEqualTo(56));
        });

        testWidgets('the validators are unchanged: required fields and the email pattern', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const EmailSignInPage(), dark: dark));
          await tester.pump();
          await tester.ensureVisible(find.byType(PrimaryButton));
          await tester.tap(find.byType(PrimaryButton));
          await tester.pump();
          expect(find.text('Please enter your email'), findsOneWidget);
          expect(find.text('Please enter your password'), findsOneWidget);
          await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
          await tester.tap(find.byType(PrimaryButton));
          await tester.pump();
          expect(find.text('Enter a valid email address'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'error text does not overflow');
        });

        testWidgets('the password can be shown and hidden', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const EmailSignInPage(), dark: dark));
          await tester.pump();
          bool obscured() => tester.widget<EditableText>(find.descendant(of: find.byType(TextFormField).last, matching: find.byType(EditableText))).obscureText;
          expect(obscured(), isTrue);
          await tester.tap(find.byTooltip('Show password'));
          await tester.pump();
          expect(obscured(), isFalse);
          await tester.tap(find.byTooltip('Hide password'));
          await tester.pump();
          expect(obscured(), isTrue);
        });

        testWidgets('a failed sign-in shows the same message, keeps the fields and frees the button', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const EmailSignInPage(), dark: dark, reduce: true));
          await tester.pump();
          await tester.enterText(find.byType(TextFormField).first, 'student@example.com');
          await tester.enterText(find.byType(TextFormField).last, 'secret');
          await tester.ensureVisible(find.byType(PrimaryButton));
          await tester.tap(find.byType(PrimaryButton));
          await tester.pump();
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(find.text('Sign-in failed. Please check your connection and try again.'), findsOneWidget);
          expect(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(CircularProgressIndicator)), findsNothing);
          expect(find.text('student@example.com'), findsOneWidget);
          await tester.pump(const Duration(seconds: 4));
        });
      });

      group('Splash — $s', () {
        for (final reduce in [false, true]) {
          testWidgets('shows the tagline${reduce ? ' (reduce motion: no running animation)' : ''}', (tester) async {
            phone(tester, scale);
            await tester.pumpWidget(app(const SplashScreen(), dark: dark, reduce: reduce));
            await tester.pump(const Duration(milliseconds: 1700));
            expect(tester.takeException(), isNull, reason: s);
            expect(find.text("Let's Improve Our Sadhana Together !!"), findsOneWidget);
            expect(find.byType(FloatingParticles), findsOneWidget);
            if (reduce) {
              expect(tester.binding.transientCallbackCount, 0, reason: 'particles and text stand still');
            } else {
              expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'particles drift');
            }
            // Leave before its own five-second timer would navigate (that needs Firebase),
            // then let the timer run out harmlessly.
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 6));
          });
        }
      });
    }
  }
}
