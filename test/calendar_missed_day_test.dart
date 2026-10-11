import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SadhanaStats.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/SadhanaDayCell.dart';
import 'package:folk_app/widgets/SadhanaDayDialog.dart';
import 'package:table_calendar/table_calendar.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Calendar: tapping a MISSED (red) day opens the right sadhana form with the Date of
// Submission already filled; the Submit button still opens it empty; a submitted day
// still opens its details; today and the future are unchanged.

void phone(WidgetTester tester, [double scale = 1.0]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Widget host(Widget home, {bool dark = false, bool reduce = true}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: home,
    );

final now = DateTime.now();
final today = DateTime(now.year, now.month, now.day);

/// A day a few days back: shown on the current month's page when it is in this month,
/// otherwise (the first days of a month) on the previous month's page.
DateTime missedDay() => today.subtract(const Duration(days: 4));
DateTime submittedDay() => today.subtract(const Duration(days: 2));

String ymd(DateTime d) => d.toString().split(' ')[0];

Finder dayCell(int day) => find.descendant(of: find.byType(TableCalendar<dynamic>), matching: find.text('$day'));

Future<StreamController<Set<String>>> open(
  WidgetTester tester, {
  String role = 'Stay at FOLK',
  bool dark = false,
  bool reduce = true,
  double scale = 1.0,
  Set<String> submitted = const {},
}) async {
  phone(tester, scale);
  final controller = StreamController<Set<String>>.broadcast();
  addTearDown(controller.close);
  await tester.pumpWidget(host(
    CalendarPage(
      username: 'Asha',
      role: role,
      datesStream: controller.stream,
      dayReader: (name, id) async => {'chantRounds': 16, 'bookReading': 30, 'classHearing': 2},
    ),
    dark: dark,
    reduce: reduce,
  ));
  controller.add({sadhanaDateKey(submittedDay()), ...submitted});
  await tester.pump();
  await tester.pump();
  return controller;
}

/// Shows the page the day is on (the previous month for the first days of a month).
Future<void> showDay(WidgetTester tester, DateTime day) async {
  if (day.month != today.month) {
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
  }
}

String dateFieldText(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField).first).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('a red (missed) day opens the form for that date', () {
    for (final role in ['Stay at FOLK', 'Stay at Hostel', 'Stay at Localite']) {
      testWidgets('$role: the right form, Date of Submission filled with that date', (tester) async {
        await open(tester, role: role);
        final day = missedDay();
        await showDay(tester, day);
        await tester.tap(dayCell(day.day));
        await tester.pumpAndSettle();
        final foklk = role == 'Stay at FOLK';
        expect(find.byType(QuestionsPage), foklk ? findsOneWidget : findsNothing);
        expect(find.byType(SadhanaPage), foklk ? findsNothing : findsOneWidget);
        expect(find.text('Date of Submission'), findsOneWidget);
        expect(dateFieldText(tester), ymd(day), reason: 'the same format the date picker writes');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the date stays editable: the field opens the same picker, which starts on that date', (tester) async {
      await open(tester);
      final day = missedDay();
      await showDay(tester, day);
      await tester.tap(dayCell(day.day));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // the picker starts on the pre-filled date; confirming keeps it
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dateFieldText(tester), ymd(day));
    });

    testWidgets('the form is not locked to the date: it can be cleared and typed over by the picker', (tester) async {
      await open(tester);
      final day = missedDay();
      await showDay(tester, day);
      await tester.tap(dayCell(day.day));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.readOnly || field.keyboardType == TextInputType.none, isTrue, reason: 'a picker field, as before');
      expect(field.onTap, isNotNull);
    });

    testWidgets('after the report is saved and the student is back, that day is green', (tester) async {
      final stream = await open(tester);
      final day = missedDay();
      await showDay(tester, day);
      SadhanaDayState stateOf() => tester.widget<SadhanaDayCell>(find.ancestor(of: dayCell(day.day), matching: find.byType(SadhanaDayCell)).first).state;
      expect(stateOf(), SadhanaDayState.missed);
      await tester.tap(dayCell(day.day));
      await tester.pumpAndSettle();
      expect(find.byType(QuestionsPage), findsOneWidget);
      // the save lands (the dates stream now carries the day), then back
      stream.add({sadhanaDateKey(submittedDay()), sadhanaDateKey(day)});
      await tester.pump();
      Navigator.of(tester.element(find.byType(QuestionsPage))).pop();
      await tester.pumpAndSettle();
      await showDay(tester, day);
      expect(stateOf(), SadhanaDayState.submitted);
    });
  });

  group('everything else on the calendar is unchanged', () {
    for (final role in ['Stay at FOLK', 'Stay at Hostel']) {
      testWidgets('$role: the Submit Sadhana button opens the form with the date EMPTY', (tester) async {
        await open(tester, role: role);
        await tester.scrollUntilVisible(find.byType(PrimaryButton), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byType(PrimaryButton));
        await tester.pumpAndSettle();
        expect(find.byType(role == 'Stay at FOLK' ? QuestionsPage : SadhanaPage), findsOneWidget);
        expect(dateFieldText(tester), isEmpty);
      });
    }

    testWidgets('a submitted day still opens the day-details pop-up, not a form', (tester) async {
      await open(tester);
      final day = submittedDay();
      await showDay(tester, day);
      await tester.tap(dayCell(day.day));
      await tester.pumpAndSettle();
      expect(find.byType(SadhanaDayDialog), findsOneWidget);
      expect(find.byType(QuestionsPage), findsNothing);
      expect(find.byType(SadhanaPage), findsNothing);
    });

    testWidgets('today opens nothing', (tester) async {
      await open(tester);
      await tester.tap(dayCell(today.day));
      await tester.pumpAndSettle();
      expect(find.byType(QuestionsPage), findsNothing);
      expect(find.byType(SadhanaPage), findsNothing);
      expect(find.byType(SadhanaDayDialog), findsNothing);
    });

    testWidgets('a future day opens nothing (it cannot even be selected)', (tester) async {
      await open(tester);
      final future = today.add(const Duration(days: 3));
      if (future.month == today.month) {
        await tester.tap(dayCell(future.day), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(find.byType(QuestionsPage), findsNothing);
      expect(find.byType(SadhanaPage), findsNothing);
    });
  });

  group('the page transition', () {
    testWidgets('with reduce motion the form is simply there on the next frame', (tester) async {
      await open(tester, reduce: true);
      final day = missedDay();
      await showDay(tester, day);
      await tester.tap(dayCell(day.day));
      await tester.pump();
      await tester.pump();
      expect(find.byType(QuestionsPage), findsOneWidget, reason: 'instant under reduce motion');
    });

    testWidgets('without reduce motion it fades and rises in, over about 0.3 s', (tester) async {
      await open(tester, reduce: false);
      await tester.pumpAndSettle(); // the calendar's own entrance has finished
      final day = missedDay();
      await showDay(tester, day);
      await tester.tap(dayCell(day.day));
      await tester.pump(); // the route is pushed
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(QuestionsPage), findsOneWidget);
      expect(find.byType(FadeTransition), findsWidgets, reason: 'a fade is running');
      await tester.pumpAndSettle();
      expect(dateFieldText(tester), ymd(day));
    });
  });

  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('${dark ? 'dark' : 'light'}, text $scale, real fonts: the pre-filled form draws without overflow', (tester) async {
        for (final role in ['Stay at FOLK', 'Stay at Hostel']) {
          await tester.pumpWidget(const SizedBox());
          await open(tester, role: role, dark: dark, scale: scale);
          final day = missedDay();
          await showDay(tester, day);
          await tester.tap(dayCell(day.day));
          await tester.pumpAndSettle();
          expect(dateFieldText(tester), ymd(day));
          expect(tester.takeException(), isNull, reason: '$role dark=$dark scale=$scale');
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
