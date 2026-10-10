import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/models/HostelSadhana.dart';
import 'package:folk_app/models/SadhanaReports.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SadhanaSave.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/SadhanaFormWidgets.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Both Sadhana forms: where the time pickers open, the sleep-after-midnight rule,
// and that a field change rebuilds only that field. Real app fonts, 360 dp.
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

Widget app(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

Finder fields() => find.byType(TextField, skipOffstage: false);

Future<void> pickDropdown(WidgetTester tester, int index, String option) async {
  final dd = find.byType(DropdownButtonFormField<String>, skipOffstage: false).at(index);
  await tester.ensureVisible(dd);
  await tester.tap(dd);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> tapSubmit(WidgetTester tester) async {
  // A focused field keeps scrolling itself back into view; let go of it first.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PrimaryButton));
  await tester.pump();
  await tester.pump();
}

// FOLK form fields in page order: 0 date, 1 temple, 2 academics, 3 rounds, 4 book, 5 sleep, 6 japa.
Future<void> fillFolk(WidgetTester tester, {String sleep = '22:30'}) async {
  final f = fields();
  await tester.enterText(f.at(0), '2026-10-08');
  await tester.enterText(f.at(1), '05:20');
  await tester.enterText(f.at(2), '60');
  await tester.enterText(f.at(3), '16');
  await tester.enterText(f.at(4), '30');
  await tester.enterText(f.at(5), sleep);
  await tester.enterText(f.at(6), '19:15');
  await pickDropdown(tester, 0, '2 - Fully');
  await pickDropdown(tester, 1, '1 - Done partially');
  await tester.ensureVisible(find.text('more than 15 mins'));
  await tester.tap(find.text('more than 15 mins'));
  await tester.pump();
}

// Hostel form: 0 date, 1 sleep, 2 wake, 3 rounds, 4 book, 5 japa.
Future<void> fillHostel(WidgetTester tester, {String sleep = '22:30'}) async {
  final f = fields();
  await tester.enterText(f.at(0), '2026-10-08');
  await tester.enterText(f.at(1), sleep);
  await tester.enterText(f.at(2), '05:30');
  await tester.enterText(f.at(3), '16');
  await tester.enterText(f.at(4), '30');
  await tester.enterText(f.at(5), '19:15');
  await pickDropdown(tester, 0, '2 - Fully');
}

Future<SadhanaReport> submitFolk(WidgetTester tester, String sleep) async {
  late SadhanaReport saved;
  phone(tester);
  await tester.pumpWidget(app(QuestionsPage(saveReport: (r, d, e) async => saved = r)));
  await tester.pump();
  await fillFolk(tester, sleep: sleep);
  await tapSubmit(tester);
  await tester.pump(const Duration(seconds: 4));
  return saved;
}

Future<HostelSadhana> submitHostel(WidgetTester tester, String sleep) async {
  late HostelSadhana saved;
  phone(tester);
  await tester.pumpWidget(app(SadhanaPage(saveReport: (r, d) async => saved = r)));
  await tester.pump();
  await fillHostel(tester, sleep: sleep);
  await tapSubmit(tester);
  await tester.pump(const Duration(seconds: 4));
  return saved;
}

TimeOfDay pickerOpensAt(WidgetTester tester) => tester.widget<TimePickerDialog>(find.byType(TimePickerDialog)).initialTime;

Future<void> openPicker(WidgetTester tester, int fieldIndex) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(fields().at(fieldIndex));
  await tester.tap(fields().at(fieldIndex), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  test('normalizeSleepTime: 00:00-11:59 is saved as 23:59; a PM time as chosen', () {
    const at = TimeOfDay(hour: 23, minute: 59);
    expect(normalizeSleepTime(const TimeOfDay(hour: 0, minute: 30)), at);
    expect(normalizeSleepTime(const TimeOfDay(hour: 0, minute: 0)), at);
    expect(normalizeSleepTime(const TimeOfDay(hour: 1, minute: 15)), at);
    expect(normalizeSleepTime(const TimeOfDay(hour: 11, minute: 59)), at);
    expect(normalizeSleepTime(const TimeOfDay(hour: 12, minute: 0)), const TimeOfDay(hour: 12, minute: 0));
    expect(normalizeSleepTime(const TimeOfDay(hour: 22, minute: 45)), const TimeOfDay(hour: 22, minute: 45));
    expect(normalizeSleepTime(at), at);
    expect(kSleepAfterMidnightNote, 'Times after midnight are recorded as 11:59 PM.');
  });

  group('FOLK form (QuestionsPage)', () {
    testWidgets('pickers open on 5:00 AM (temple) and 10:00 PM (sleep); japa finish and the rest are unchanged', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const QuestionsPage()));
      await tester.pump();

      await openPicker(tester, 1); // temple
      expect(pickerOpensAt(tester), const TimeOfDay(hour: 5, minute: 0));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await openPicker(tester, 5); // sleep
      expect(pickerOpensAt(tester), const TimeOfDay(hour: 22, minute: 0));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await openPicker(tester, 6); // japa finish: still the current time
      final now = TimeOfDay.now();
      final opens = pickerOpensAt(tester);
      expect((opens.hour * 60 + opens.minute) - (now.hour * 60 + now.minute), inInclusiveRange(-1, 1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fields().evaluate().length, 7);
    });

    testWidgets('picking OK on the sleep picker keeps 22:00; picking an AM time shows and records 23:59', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const QuestionsPage()));
      await tester.pump();
      await openPicker(tester, 5);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields().at(5)).controller!.text, '22:00');

      await openPicker(tester, 5);
      await tester.tap(find.text('AM'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields().at(5)).controller!.text, '23:59');
    });

    testWidgets('a temple entry picked in the dialog is saved as chosen (no sleep rule on it)', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const QuestionsPage()));
      await tester.pump();
      await openPicker(tester, 1);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields().at(1)).controller!.text, '05:00');
    });

    testWidgets('the muted note is under the sleep field, once', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const QuestionsPage()));
      await tester.pump();
      expect(find.text(kSleepAfterMidnightNote, skipOffstage: false), findsOneWidget);
      final note = find.text(kSleepAfterMidnightNote, skipOffstage: false);
      final sleepField = fields().at(5);
      expect(tester.getRect(note).top, greaterThan(tester.getRect(sleepField).bottom));
      expect(tester.getRect(note).top - tester.getRect(sleepField).bottom, lessThan(20));
    });

    for (final c in [('00:30', '23:59'), ('22:45', '22:45'), ('11:59', '23:59'), ('00:00', '23:59'), ('12:00', '12:00'), ('23:59', '23:59'), ('1:05', '23:59')]) {
      testWidgets('submitting sleep ${c.$1} saves ${c.$2}', (tester) async {
        final report = await submitFolk(tester, c.$1);
        expect(report.toMap()['sleepTiming'], c.$2);
        // everything else is exactly as entered
        final m = report.toMap();
        expect(m['templeEntry'], '05:20');
        expect(m['finishTiming'], '19:15');
        expect(m['chantRounds'], 16);
        expect(m['bookReading'], 30);
      });
    }

    testWidgets('validation is unchanged: an empty form still says so and saves nothing', (tester) async {
      var saves = 0;
      phone(tester);
      await tester.pumpWidget(app(QuestionsPage(saveReport: (r, d, e) async => saves++)));
      await tester.pump();
      await tapSubmit(tester);
      expect(find.text('Please fill all the fields!'), findsOneWidget);
      expect(saves, 0);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('validation is unchanged: a bad number and a bad time stop the save, each message on its own field', (tester) async {
      var saves = 0;
      phone(tester);
      await tester.pumpWidget(app(QuestionsPage(saveReport: (r, d, e) async => saves++)));
      await tester.pump();
      await fillFolk(tester, sleep: 'late');
      await tester.enterText(fields().at(3), '12.5');
      await tapSubmit(tester);
      expect(find.text(kWholeNumberMessage), findsOneWidget);
      expect(find.text('Pick this time again'), findsOneWidget); // the bad sleep time
      expect(saves, 0);
      await tester.pump(const Duration(seconds: 4));
      // typing in the rounds field clears only its own message
      await tester.enterText(fields().at(3), '16');
      await tester.pump();
      expect(find.text(kWholeNumberMessage), findsNothing);
      expect(find.text('Pick this time again'), findsOneWidget);
      // picking a sleep time clears that one
      await openPicker(tester, 5);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Pick this time again'), findsNothing);
    });
  });

  group('hostel / localite form (SadhanaPage)', () {
    testWidgets('the sleep picker opens on 10:00 PM; wake-up and japa finish are unchanged; note shown once', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const SadhanaPage()));
      await tester.pump();
      await openPicker(tester, 1); // sleep
      expect(pickerOpensAt(tester), const TimeOfDay(hour: 22, minute: 0));
      await tester.tap(find.text('AM'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields().at(1)).controller!.text, '23:59');

      await openPicker(tester, 2); // wake-up: the current time, as before
      final now = TimeOfDay.now();
      final opens = pickerOpensAt(tester);
      expect((opens.hour * 60 + opens.minute) - (now.hour * 60 + now.minute), inInclusiveRange(-1, 1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(kSleepAfterMidnightNote, skipOffstage: false), findsOneWidget);
    });

    for (final c in [('00:30', '23:59'), ('22:45', '22:45'), ('11:59', '23:59'), ('12:00', '12:00')]) {
      testWidgets('submitting sleep ${c.$1} saves ${c.$2}', (tester) async {
        final report = await submitHostel(tester, c.$1);
        expect(report.toMap()['sleepTiming'], c.$2);
        expect(report.toMap()['wakeUpTime'], '05:30');
        expect(report.toMap()['finishTiming'], '19:15');
      });
    }
  });

  group('smoothness: a field change rebuilds that field, not the form', () {
    testWidgets('choosing a drop-down answer / option / typing rebuilds only the one card; each card is a repaint boundary', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const QuestionsPage()));
      await tester.pump();

      final cards = find.byType(FormQuestionCard, skipOffstage: false);
      expect(cards.evaluate().length, 10);
      for (final e in cards.evaluate()) {
        var isBoundary = false;
        e.visitChildren((c) => isBoundary = c.widget is RepaintBoundary);
        expect(isBoundary, isTrue, reason: 'each card is wrapped in its own RepaintBoundary');
      }

      final rebuilt = <String>[];
      final old = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is FormQuestionCard) rebuilt.add((element.widget as FormQuestionCard).question);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = old);
      debugPrintRebuildDirtyWidgets = false;

      // a drop-down answer
      await pickDropdown(tester, 0, '2 - Fully');
      expect(rebuilt.toSet().length, lessThanOrEqualTo(1), reason: 'drop-down rebuilt: $rebuilt');
      rebuilt.clear();
      // the extra-lecture option
      await tester.ensureVisible(find.text('No'));
      await tester.tap(find.text('No'));
      await tester.pump();
      expect(rebuilt.toSet().length, lessThanOrEqualTo(1), reason: 'option rebuilt: $rebuilt');
      rebuilt.clear();
      // typing
      await tester.enterText(fields().at(3), '16');
      await tester.pump();
      expect(rebuilt, isEmpty, reason: 'typing rebuilds no card: $rebuilt');
      // a picked time
      await openPicker(tester, 5);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(rebuilt, isEmpty, reason: 'a picked time rebuilds no card: $rebuilt');
    });
  });

  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('both forms draw without overflow, with the note — ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
        phone(tester, scale);
        for (final page in [const QuestionsPage(), const SadhanaPage()]) {
          await tester.pumpWidget(app(page, dark: dark));
          await tester.pump();
          expect(tester.takeException(), isNull);
          final note = find.text(kSleepAfterMidnightNote, skipOffstage: false);
          expect(note, findsOneWidget);
          await tester.ensureVisible(note);
          await tester.pump();
          final box = tester.renderObject<RenderParagraph>(note);
          expect(box.didExceedMaxLines, isFalse);
          expect(tester.getRect(note).right, lessThanOrEqualTo(360 - 20 - 16 + .5));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
