import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/ABCDEScreen.dart' show PlaceholderScreen;
import 'package:folk_app/pages/Phase7Placeholders.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BadgeDialog.dart';
import 'package:folk_app/widgets/NavHostGhost.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/SadhanaFormWidgets.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Phase 11b group 3: the two Sadhana report forms, the badge dialog, the
// placeholder screens and the tab host's first-load ghost, at 360 dp, text
// scale 1.0 / 1.3 / 1.6, light and dark. The two forms and the dialog are the
// REAL screens: none of them touches Firebase until a report is submitted.
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

// The question titles in the order they appear on the page.
List<String> questionOrder(WidgetTester tester) => tester
    .widgetList<FormQuestionCard>(find.byType(FormQuestionCard))
    .map((c) => c.question)
    .toList();

const folkOrder = [
  'Date of Submission',
  'Time Entered Temple Hall',
  'SB Class - 7:20 AM to 7:55 AM',
  'Total Academics Study yesterday',
  'Daily Assigned Services',
  'Total rounds chanted yesterday',
  'Total book reading (in mins) yesterday',
  'Sleep time of yesterday',
  'Japa finish time of yesterday',
  'Heard extra lecture yesterday ?',
];

const hostelOrder = [
  'Date of Submission',
  'Sleep time of yesterday',
  'Waking Up Time for today?',
  'Total rounds chanted yesterday',
  'Heard Bhagavatam Class today ?',
  'Total book reading (in mins) yesterday',
  'Japa finish time of yesterday',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text scale $scale, 360 dp';

      group('Sadhana forms — $s', () {
        testWidgets('QuestionsPage (FOLK): same ten fields in the same order, no overflow, Submit reachable', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(QuestionsPage(), dark: dark, reduce: true));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(questionOrder(tester), folkOrder);
          // The three extra-lecture options and the Submit button exist and Submit can be scrolled to.
          expect(find.text('more than 30 mins', skipOffstage: false), findsOneWidget);
          expect(find.text('more than 15 mins', skipOffstage: false), findsOneWidget);
          await tester.scrollUntilVisible(find.byType(PrimaryButton), 300, scrollable: find.byType(Scrollable).first);
          expect(find.text('Submit'), findsOneWidget);
          for (final o in tester.widgetList<FormOptionRow>(find.byType(FormOptionRow, skipOffstage: false))) {
            expect(o.label.isNotEmpty, isTrue);
          }
          expect(tester.takeException(), isNull, reason: '$s after scrolling');
        });

        testWidgets('SadhanaPage (hostel/localite): same seven fields in the same order, no overflow', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(SadhanaPage(), dark: dark, reduce: true));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(questionOrder(tester), hostelOrder);
          await tester.scrollUntilVisible(find.byType(PrimaryButton), 300, scrollable: find.byType(Scrollable).first);
          expect(find.text('Submit'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$s after scrolling');
        });

        testWidgets('choosing a drop-down answer and an extra-lecture option still records it', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(QuestionsPage(), dark: dark, reduce: true));
          await tester.pump();
          // SB Class drop-down -> "2 - Fully"
          await tester.scrollUntilVisible(find.text('SB Class - 7:20 AM to 7:55 AM'), 200, scrollable: find.byType(Scrollable).first);
          await tester.tap(find.byType(DropdownButtonFormField<String>).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('2 - Fully').last);
          await tester.pumpAndSettle();
          expect(find.text('2 - Fully'), findsWidgets);
          // Extra lecture -> "more than 15 mins" becomes the selected row
          await tester.scrollUntilVisible(find.text('more than 15 mins'), 300, scrollable: find.byType(Scrollable).first);
          await tester.tap(find.text('more than 15 mins'));
          await tester.pump();
          final rows = tester.widgetList<FormOptionRow>(find.byType(FormOptionRow)).toList();
          expect(rows.map((r) => r.selected).toList(), [false, true, false]);
          for (final r in find.byType(FormOptionRow).evaluate()) {
            expect(tester.getSize(find.byWidget(r.widget)).height, greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull, reason: s);
        });

        testWidgets('number fields take digits; the date field does not open a keyboard', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(SadhanaPage(), dark: dark, reduce: true));
          await tester.pump();
          final fields = tester.widgetList<TextField>(find.byType(TextField, skipOffstage: false)).toList();
          // date, sleep(time), wake(time), rounds, book, japa(time): 6 text fields
          expect(fields.length, 6);
          expect(fields[0].keyboardType, TextInputType.none);
          expect(fields[3].keyboardType, TextInputType.number);
          expect(fields[4].keyboardType, TextInputType.number);
        });
      });

      group('Badge dialog — $s', () {
        for (final badge in ['gold_badge', '1st_badge']) {
          testWidgets('$badge: nothing overflows, stars drift, a tap outside still closes it', (tester) async {
            phone(tester, scale);
            await tester.pumpWidget(app(
              Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showBadgeDialog(context, badge),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
              dark: dark,
            ));
            await tester.tap(find.text('open'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 1200));
            expect(tester.takeException(), isNull, reason: s);
            expect(find.text('Congratulations!'), findsOneWidget);
            expect(find.text('You Won ✨'), findsOneWidget);
            expect(find.text(badge.replaceAll('_', ' ').toUpperCase()), findsOneWidget);
            expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'stars drift');
            // tap the barrier: it still dismisses
            await tester.tapAt(const Offset(4, 4));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            expect(find.text('Congratulations!'), findsNothing);
          });
        }

        testWidgets('reduce motion: shows at once, no ticker left running', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showBadgeDialog(context, 'silver_badge'),
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
          await tester.pump(const Duration(milliseconds: 400)); // route transition only
          expect(find.text('Congratulations!'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: s);
          await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
          expect(tester.binding.transientCallbackCount, 0, reason: 'no stars, no pop, no entrance');
        });
      });

      group('Placeholders and tab host ghost — $s', () {
        testWidgets('PlaceholderScreen', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const PlaceholderScreen(title: 'A rather long section title for the placeholder'), dark: dark));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text('Coming Soon'), findsOneWidget);
        });

        testWidgets('Phase7PlaceholderScreen', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(
            const Phase7PlaceholderScreen(Phase7Item(
              title: 'Japa card',
              description: 'A longer description of the module that is being prepared for students.',
              icon: Icons.spa,
              colour: Colors.teal,
              handoffLine: 'x',
            )),
            dark: dark,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text('Not available yet'), findsOneWidget);
          expect(find.text('Your guide will let you know when it is ready.'), findsOneWidget);
        });

        testWidgets('NavHostGhost: no spinner, no overflow, no ticker under reduce motion', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(app(const Scaffold(body: NavHostGhost()), dark: dark, reduce: true));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.binding.transientCallbackCount, 0);
        });
      });
    }
  }
}
