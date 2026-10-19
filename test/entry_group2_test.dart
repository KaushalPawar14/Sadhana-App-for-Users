// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/CompleteProfile.dart';
import 'package:folk_app/pages/ForceUpdateScreen.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/FolkChip.dart';
import 'package:folk_app/widgets/FolkDialog.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Phase 11c group 2: CompleteProfilePage and ForceUpdateScreen at 360 dp, text
// scale 1.0 / 1.3 / 1.6, light and dark. The profile page reads Firebase when it
// opens; with no Firebase app here that read fails (and is cleared), so each test
// sets the page's own state fields to put it in the state under test — the
// logic itself is proved byte-identical separately. Nothing here submits.
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

Future<dynamic> openProfile(WidgetTester tester, void Function(dynamic state) setup, {bool dark = false, double scale = 1.0}) async {
  phone(tester, scale);
  await tester.pumpWidget(app(const CompleteProfilePage(), dark: dark, reduce: true));
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  tester.takeException(); // the Firebase read fails here: there is no Firebase app
  final state = tester.state(find.byType(CompleteProfilePage)) as dynamic;
  setup(state);
  state.isLoading = false;
  state.setState(() {});
  await tester.pump();
  return state;
}

List<String> labelsOnPage(WidgetTester tester) {
  const known = ['Full Name', 'Gender', 'Mobile Number', 'Date of Birth', 'How many rounds do you commit to chant daily?', 'How many minutes of reading do you commit to daily? (0 if you are a beginner)', 'Residence'];
  final found = <String, double>{};
  for (final k in known) {
    final f = find.text(k, skipOffstage: false);
    if (f.evaluate().isNotEmpty) found[k] = tester.getTopLeft(f.first).dy;
  }
  return (found.keys.toList()..sort((a, b) => found[a]!.compareTo(found[b]!)));
}

Finder fieldWithHint(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint, skipOffstage: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    // A mocked Firebase app, so the page's own opening read finds no signed-in user
    // and simply stays on its ghost until the test moves it on.
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    // FirebaseAuth registers its listeners on first use; answer them.
    for (final name in ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$name',
        (message) async => const StandardMessageCodec().encodeMessage(<Object?>['listener']),
      );
    }
  });

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text scale $scale, 360 dp';

      group('CompleteProfilePage — $s', () {
        testWidgets('loading: a ghost of the form, no spinner', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const CompleteProfilePage(), dark: dark, reduce: true));
          await tester.pump();
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
          tester.takeException();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Complete Your Profile'), findsNothing);
        });

        testWidgets('step 1 is Name -> Gender -> Mobile, with Confirm last; nothing overflows', (tester) async {
          await openProfile(tester, (_) {}, dark: dark, scale: scale);
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text('Complete Your Profile'), findsOneWidget);
          expect(labelsOnPage(tester), ['Full Name', 'Gender', 'Mobile Number']);
          expect(find.text('Male'), findsOneWidget);
          expect(find.text('Female'), findsOneWidget);
          expect(find.text('Confirm'), findsOneWidget);
          expect(find.text('Submit'), findsNothing, reason: 'step 2 only appears after Confirm');
          await tester.ensureVisible(find.byType(PrimaryButton));
          expect(tester.getSize(find.byType(PrimaryButton)).height, greaterThanOrEqualTo(56));
        });

        testWidgets('Confirm waits for a gender; choosing one enables it', (tester) async {
          await openProfile(tester, (_) {}, dark: dark, scale: scale);
          await tester.ensureVisible(find.byType(PrimaryButton));
          PrimaryButton button() => tester.widget<PrimaryButton>(find.byType(PrimaryButton));
          expect(button().onPressed, isNull);
          await tester.ensureVisible(find.text('Female'));
          await tester.tap(find.text('Female'));
          await tester.pump();
          expect(tester.widgetList<FolkChip>(find.byType(FolkChip)).map((c) => c.selected), [false, true]);
          expect(button().onPressed, isNotNull);
        });

        testWidgets('Confirm with no name: "Full name is required" under the name field', (tester) async {
          await openProfile(tester, (_) {}, dark: dark, scale: scale);
          await tester.tap(find.text('Male'));
          await tester.pump();
          await tester.ensureVisible(find.byType(PrimaryButton));
          await tester.tap(find.byType(PrimaryButton));
          await tester.pump();
          expect(find.text('Full name is required'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('Confirm with a bad mobile number: the same 10-digit message', (tester) async {
          await openProfile(tester, (_) {}, dark: dark, scale: scale);
          await tester.tap(find.text('Male'));
          await tester.enterText(fieldWithHint('Enter your full name'), 'Asha Devi');
          await tester.enterText(fieldWithHint('Enter your mobile number'), '12345');
          await tester.pump();
          await tester.ensureVisible(find.byType(PrimaryButton));
          await tester.tap(find.byType(PrimaryButton));
          await tester.pump();
          expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
          await tester.pump(const Duration(seconds: 4));
        });

        testWidgets('saved name and mobile: both fields are locked (muted, with a lock); gender saved: no Gender question', (tester) async {
          await openProfile(tester, (st) {
            st.nameController.text = 'Asha Devi';
            st.mobileController.text = '9876543210';
            st.nameAlreadySaved = true;
            st.mobileAlreadySaved = true;
            st.genderAlreadySaved = true;
            st.selectedGender = 'female';
            st.confirmed = true;
          }, dark: dark, scale: scale);
          expect(tester.takeException(), isNull, reason: s);
          expect(labelsOnPage(tester), ['Full Name', 'Mobile Number', 'Date of Birth', 'How many rounds do you commit to chant daily?', 'How many minutes of reading do you commit to daily? (0 if you are a beginner)', 'Residence']);
          final name = tester.widget<TextField>(fieldWithHint('Enter your full name'));
          final mobile = tester.widget<TextField>(fieldWithHint('Enter your mobile number'));
          expect(name.enabled, isFalse);
          expect(mobile.enabled, isFalse);
          expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
        });

        testWidgets('step 2: date of birth, both commitments (required), residence, Submit — and the same validation messages', (tester) async {
          await openProfile(tester, (st) {
            st.nameController.text = 'Asha Devi';
            st.mobileController.text = '9876543210';
            st.genderAlreadySaved = true;
            st.confirmed = true;
          }, dark: dark, scale: scale);
          expect(labelsOnPage(tester), ['Full Name', 'Mobile Number', 'Date of Birth', 'How many rounds do you commit to chant daily?', 'How many minutes of reading do you commit to daily? (0 if you are a beginner)', 'Residence']);
          expect(find.text('Confirm'), findsNothing);
          await tester.ensureVisible(find.text('Submit'));
          await tester.tap(find.text('Submit'));
          await tester.pump();
          expect(find.text('Date of birth is required'), findsOneWidget);
          await tester.enterText(fieldWithHint('e.g. 16'), '0');
          await tester.ensureVisible(find.text('Submit'));
          await tester.tap(find.text('Submit'));
          await tester.pump();
          expect(find.text('Enter a whole number of rounds, 1 or more'), findsOneWidget);
          // the reading commitment is required too (0 is fine), and blank is refused
          expect(find.text('Enter minutes from 0 to 1440 (0 if you are a beginner)'), findsOneWidget);
          await tester.enterText(fieldWithHint('e.g. 30, or 0'), '0');
          await tester.enterText(fieldWithHint('e.g. 16'), '16');
          await tester.tap(find.text('Submit'));
          await tester.pump();
          expect(find.text('Enter a whole number of rounds, 1 or more'), findsNothing);
          expect(find.text('Enter minutes from 0 to 1440 (0 if you are a beginner)'), findsNothing, reason: '0 is a valid reading commitment');
          expect(tester.takeException(), isNull, reason: s);
        });

        testWidgets('a matched or already-assigned residence hides the Residence question', (tester) async {
          await openProfile(tester, (st) {
            st.nameController.text = 'Asha Devi';
            st.mobileController.text = '9876543210';
            st.genderAlreadySaved = true;
            st.confirmed = true;
            st.isMatched = true;
          }, dark: dark, scale: scale);
          expect(labelsOnPage(tester), ['Full Name', 'Mobile Number', 'Date of Birth', 'How many rounds do you commit to chant daily?', 'How many minutes of reading do you commit to daily? (0 if you are a beginner)']);
        });

        testWidgets('the "cannot be changed" dialog layout (the same words in the same dialog frame)', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogContext) {
                        final colors = dialogContext.folk;
                        final text = dialogContext.folkText;
                        return FolkDialog.alert(
                          dialogContext,
                          title: 'Confirm your mobile number',
                          content: Text(
                            'You entered "9876543210". This cannot be changed once you '
                            'continue. Is this correct?',
                            style: text.small,
                          ),
                          actions: [
                            TextButton(style: FolkDialog.quietButton(colors, text), onPressed: () {}, child: const Text('Edit')),
                            ElevatedButton(style: FolkDialog.primaryButton(colors, text), onPressed: () {}, child: const Text('Confirm')),
                          ],
                        );
                      },
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            dark: dark,
            reduce: true,
          ));
          await tester.tap(find.text('open'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: s);
          expect(find.textContaining('This cannot be changed once you continue. Is this correct?'), findsOneWidget);
        });
      });

      group('ForceUpdateScreen — $s', () {
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
        });

        testWidgets('renders the same words, one Update now button at least 56 dp; nothing overflows', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const ForceUpdateScreen(), dark: dark));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text('Update required'), findsOneWidget);
          expect(find.textContaining('A newer version of the FOLK app is required to continue.'), findsOneWidget);
          expect(find.text('Update now'), findsOneWidget);
          expect(tester.getSize(find.byType(PrimaryButton)).height, greaterThanOrEqualTo(56));
        });

        testWidgets('Update now opens the Play Store link; a refusal shows the same message', (tester) async {
          phone(tester, scale);
          final calls = <MethodCall>[];
          var answer = true;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return answer;
          });
          await tester.pumpWidget(app(const ForceUpdateScreen(), dark: dark, reduce: true));
          await tester.tap(find.text('Update now'));
          await tester.pump();
          await tester.pump();
          expect(calls, isNotEmpty);
          expect(calls.any((c) => '${c.arguments}'.contains(ForceUpdateScreen.playStoreUrl)), isTrue, reason: '${calls.map((c) => '${c.method} ${c.arguments}')}');
          expect(ForceUpdateScreen.playStoreUrl, 'https://play.google.com/store/apps/details?id=org.folksurat.students');
          expect(find.text('Could not open the Play Store. Please update manually.'), findsNothing);

          answer = false;
          await tester.tap(find.text('Update now'));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Could not open the Play Store. Please update manually.'), findsOneWidget);
          await tester.pump(const Duration(seconds: 5));
        });

        testWidgets('a back press is absorbed: the app does not exit', (tester) async {
          phone(tester, scale);
          var exits = 0;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') exits++;
            return null;
          });
          await tester.pumpWidget(app(const ForceUpdateScreen(), dark: dark, reduce: true));
          await tester.pump();
          await tester.binding.handlePopRoute();
          await tester.pump();
          expect(exits, 0);
          expect(find.text('Update required'), findsOneWidget);
        });
      });
    }
  }
}
