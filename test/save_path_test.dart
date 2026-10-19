// ignore_for_file: subtype_of_sealed_class (the two Fake* snapshot stand-ins at the bottom)
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/models/HostelSadhana.dart';
import 'package:folk_app/models/SadhanaReports.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/SadhanaReportSource.dart';
import 'package:folk_app/utils/SadhanaSave.dart';
import 'package:folk_app/widgets/NavHostGhost.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';

import 'text_scale_test.dart' show loadAppFonts;

// The Sadhana form save path and the two never-ending loaders. The save is
// handed in by the test, so no Submit ever reaches Firestore.
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

Widget app(Widget home) => MaterialApp(
      theme: FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

// The text currently in each TextField, in page order.
List<String> fieldTexts(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField, skipOffstage: false))
    .map((f) => f.controller!.text)
    .toList();

Future<void> pickDropdown(WidgetTester tester, int index, String option) async {
  final dd = find.byType(DropdownButtonFormField<String>, skipOffstage: false).at(index);
  await tester.ensureVisible(dd);
  await tester.tap(dd);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.tap(find.byType(PrimaryButton));
  await tester.pump();
}

// Lets the success/error banner's three-second timer run out.
Future<void> flushBanner(WidgetTester tester) => tester.pump(const Duration(seconds: 4));

// ---- hostel / localite form ---------------------------------------------
Future<void> fillHostel(WidgetTester tester, {String rounds = '16', String book = '30'}) async {
  final f = find.byType(TextField, skipOffstage: false);
  await tester.enterText(f.at(0), '2026-10-08'); // date
  await tester.enterText(f.at(1), '22:30'); // sleep
  await tester.enterText(f.at(2), '05:30'); // wake
  await tester.enterText(f.at(3), rounds);
  await tester.enterText(f.at(4), book);
  await tester.enterText(f.at(5), '19:15'); // japa
  await pickDropdown(tester, 0, '2 - Fully');
}

// ---- FOLK form --------------------------------------------------------------
Future<void> fillFolk(WidgetTester tester,
    {String rounds = '16', String book = '30', String academics = '60', String extra = 'more than 15 mins'}) async {
  final f = find.byType(TextField, skipOffstage: false);
  await tester.enterText(f.at(0), '2026-10-08'); // date
  await tester.enterText(f.at(1), '05:20'); // temple
  await tester.enterText(f.at(2), academics);
  await tester.enterText(f.at(3), rounds);
  await tester.enterText(f.at(4), book);
  await tester.enterText(f.at(5), '22:30'); // sleep
  await tester.enterText(f.at(6), '19:15'); // japa
  await pickDropdown(tester, 0, '2 - Fully'); // SB class
  await pickDropdown(tester, 1, '1 - Done partially'); // daily services
  await tester.ensureVisible(find.text(extra));
  await tester.tap(find.text(extra));
  await tester.pump();
}

const badNumbers = ['12.5', '1,5', '-3', '+4', '12a', 'ten', '1 2'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // ======================================================== helpers (pure)
  group('whole numbers and times', () {
    test('parseWholeNumber accepts digits only', () {
      expect(parseWholeNumber('16'), 16);
      expect(parseWholeNumber(' 16 '), 16);
      expect(parseWholeNumber('0'), 0);
      for (final bad in [...badNumbers, '', ' ', '1e3', '٣', '１２', '1234567890']) {
        expect(parseWholeNumber(bad), isNull, reason: '"$bad"');
      }
    });

    test('tryParseTime: valid times parse, anything else is null (never midnight)', () {
      expect(tryParseTime('05:30'), const TimeOfDay(hour: 5, minute: 30));
      expect(tryParseTime('9:05'), const TimeOfDay(hour: 9, minute: 5));
      expect(tryParseTime('8:00 PM'), const TimeOfDay(hour: 20, minute: 0));
      for (final bad in ['', 'noon', '25:00', '12:75', 'abc']) {
        expect(tryParseTime(bad), isNull, reason: '"$bad"');
      }
    });
  });

  group('profile is incomplete: nothing may be written', () {
    test('missing document, missing name, empty or blank name, wrong type', () {
      for (final c in [
        (false, 'Asha Devi'),
        (true, null),
        (true, ''),
        (true, '   '),
        (true, 42),
      ]) {
        expect(
          () => requireStudentName(userExists: c.$1, storedName: c.$2),
          throwsA(isA<SadhanaSaveException>().having((e) => e.failure, 'failure', SadhanaSaveFailure.profileIncomplete)),
          reason: '$c',
        );
      }
    });

    test('a real name comes back exactly as stored, and is never "Unknown User"', () {
      expect(requireStudentName(userExists: true, storedName: 'Asha Devi'), 'Asha Devi');
      expect(requireStudentName(userExists: true, storedName: ' Asha  Devi '), ' Asha  Devi ');
    });
  });

  group('runSadhanaSave maps every failure', () {
    Future<SadhanaSaveFailure> failureOf(Future<void> Function() save, {Duration timeout = const Duration(seconds: 1)}) async {
      try {
        await runSadhanaSave(save, timeout: timeout);
      } on SadhanaSaveException catch (e) {
        return e.failure;
      }
      fail('did not throw');
    }

    test('success returns', () async {
      await runSadhanaSave(() async {});
    });
    test('a SadhanaSaveException passes through unchanged', () async {
      expect(await failureOf(() async => throw const SadhanaSaveException(SadhanaSaveFailure.profileIncomplete)), SadhanaSaveFailure.profileIncomplete);
    });
    test('no answer in time -> timeout', () async {
      expect(await failureOf(() => Completer<void>().future, timeout: const Duration(milliseconds: 30)), SadhanaSaveFailure.timeout);
    });
    test('unavailable / deadline-exceeded -> timeout; permission-denied -> permission; other -> failed', () async {
      expect(await failureOf(() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')), SadhanaSaveFailure.timeout);
      expect(await failureOf(() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded')), SadhanaSaveFailure.timeout);
      expect(await failureOf(() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')), SadhanaSaveFailure.permission);
      expect(await failureOf(() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted')), SadhanaSaveFailure.failed);
      expect(await failureOf(() async => throw StateError('x')), SadhanaSaveFailure.failed);
    });
    test('the messages are the ones the student is meant to read', () {
      expect(sadhanaSaveMessage(SadhanaSaveFailure.profileIncomplete), 'Your profile is incomplete — please contact your guide.');
      expect(sadhanaSaveMessage(SadhanaSaveFailure.timeout), "Couldn't reach the server — please try again");
      expect(kSadhanaSaveTimeout, const Duration(seconds: 15));
    });
  });

  // ======================================================== hostel / localite
  group('SadhanaPage (hostel / localite) — save path', () {
    Future<List<(HostelSadhana, String)>> open(WidgetTester tester, Future<void> Function(HostelSadhana, String) save,
        {Duration timeout = const Duration(seconds: 15), double scale = 1.0}) async {
      final calls = <(HostelSadhana, String)>[];
      phone(tester, scale);
      await tester.pumpWidget(app(SadhanaPage(
        saveReport: (r, d) {
          calls.add((r, d));
          return save(r, d);
        },
        saveTimeout: timeout,
      )));
      await tester.pump();
      return calls;
    }

    testWidgets('empty form: the old message, nothing saved', (tester) async {
      final calls = await open(tester, (_, __) async {});
      await tapSubmit(tester);
      expect(find.text('Please fill all the fields!'), findsOneWidget);
      expect(calls, isEmpty);
      await flushBanner(tester);
    });

    for (final bad in badNumbers) {
      testWidgets('rounds "$bad" is rejected on that field; nothing saved, nothing cleared', (tester) async {
        final calls = await open(tester, (_, __) async {});
        await fillHostel(tester, rounds: bad);
        await tapSubmit(tester);
        expect(calls, isEmpty);
        expect(find.text(kWholeNumberMessage), findsOneWidget, reason: 'one message, under rounds');
        expect(find.text('Please correct the highlighted fields.'), findsOneWidget);
        expect(fieldTexts(tester)[3], bad);
        expect(fieldTexts(tester)[4], '30');
        expect(find.text('Sadhana submitted successfully'), findsNothing);
        // editing the field clears its message
        await tester.enterText(find.byType(TextField, skipOffstage: false).at(3), '16');
        await tester.pump();
        expect(find.text(kWholeNumberMessage), findsNothing);
        await flushBanner(tester);
      });
    }

    testWidgets('book reading is checked too, and both messages show together', (tester) async {
      final calls = await open(tester, (_, __) async {});
      await fillHostel(tester, rounds: '1.5', book: '2,5');
      await tapSubmit(tester);
      expect(calls, isEmpty);
      expect(find.text(kWholeNumberMessage), findsNWidgets(2));
      await flushBanner(tester);
    });

    testWidgets('success: saved once with the parsed numbers, THEN the banner and the clear', (tester) async {
      final completer = Completer<void>();
      final calls = await open(tester, (_, __) => completer.future);
      await fillHostel(tester);
      await tapSubmit(tester);
      // while the save is running: busy button, nothing cleared, no success yet
      expect(calls.length, 1);
      expect(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text('Sadhana submitted successfully'), findsNothing);
      expect(fieldTexts(tester)[3], '16');
      // a second tap while saving does nothing
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      expect(calls.length, 1);
      completer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Sadhana submitted successfully'), findsOneWidget);
      expect(fieldTexts(tester), everyElement(''));
      final (report, date) = calls.single;
      expect(date, '08-10-2026');
      expect(report.chantRounds, 16);
      expect(report.bookReading, 30);
      expect(report.classHearing, 2);
      expect(report.toMap()['wakeUpTime'], '05:30');
      expect(report.toMap()['sleepTiming'], '22:30');
      expect(report.toMap()['finishTiming'], '19:15');
      expect(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(CircularProgressIndicator)), findsNothing);
      await flushBanner(tester);
    });

    testWidgets('failure: a clear error, everything typed is kept, then a retry succeeds', (tester) async {
      var attempt = 0;
      final calls = await open(tester, (_, __) async {
        attempt++;
        if (attempt == 1) throw Exception('network');
      });
      await fillHostel(tester);
      final before = fieldTexts(tester);
      await tapSubmit(tester);
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't save your report — please try again"), findsOneWidget);
      expect(find.text('Sadhana submitted successfully'), findsNothing);
      expect(fieldTexts(tester), before);
      expect(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(CircularProgressIndicator)), findsNothing);
      await flushBanner(tester);
      await tapSubmit(tester);
      await tester.pump();
      await tester.pump();
      expect(calls.length, 2);
      expect(find.text('Sadhana submitted successfully'), findsOneWidget);
      expect(fieldTexts(tester), everyElement(''));
      await flushBanner(tester);
    });

    testWidgets('timeout: "Couldn\'t reach the server", input kept', (tester) async {
      final calls = await open(tester, (_, __) => Completer<void>().future, timeout: const Duration(milliseconds: 200));
      await fillHostel(tester);
      final before = fieldTexts(tester);
      await tapSubmit(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(calls.length, 1);
      expect(find.text("Couldn't reach the server — please try again"), findsOneWidget);
      expect(fieldTexts(tester), before);
      expect(find.text('Sadhana submitted successfully'), findsNothing);
      await flushBanner(tester);
    });

    testWidgets('profile incomplete: that message, input kept, nothing confirmed', (tester) async {
      final calls = await open(tester, (_, __) async => throw const SadhanaSaveException(SadhanaSaveFailure.profileIncomplete));
      await fillHostel(tester);
      final before = fieldTexts(tester);
      await tapSubmit(tester);
      await tester.pump();
      await tester.pump();
      expect(calls.length, 1);
      expect(find.text('Your profile is incomplete — please contact your guide.'), findsOneWidget);
      expect(fieldTexts(tester), before);
      expect(find.text('Sadhana submitted successfully'), findsNothing);
      await flushBanner(tester);
    });

    testWidgets('at text scale 1.6 the field messages and the busy button do not overflow', (tester) async {
      final completer = Completer<void>();
      await open(tester, (_, __) => completer.future, scale: 1.6);
      await fillHostel(tester, rounds: '12.5', book: '2,5');
      await tapSubmit(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField, skipOffstage: false).at(3), '16');
      await tester.enterText(find.byType(TextField, skipOffstage: false).at(4), '30');
      await tester.pump();
      await tapSubmit(tester);
      expect(tester.takeException(), isNull);
      completer.complete();
      await tester.pump();
      await tester.pump();
      await flushBanner(tester);
    });
  });

  // ======================================================== FOLK
  group('QuestionsPage (FOLK) — save path', () {
    Future<List<(SadhanaReport, String, double)>> open(WidgetTester tester, Future<void> Function(SadhanaReport, String, double) save,
        {Duration timeout = const Duration(seconds: 15)}) async {
      final calls = <(SadhanaReport, String, double)>[];
      phone(tester);
      await tester.pumpWidget(app(QuestionsPage(
        saveReport: (r, d, e) {
          calls.add((r, d, e));
          return save(r, d, e);
        },
        saveTimeout: timeout,
      )));
      await tester.pump();
      return calls;
    }

    testWidgets('empty form: the old message, nothing saved', (tester) async {
      final calls = await open(tester, (_, __, ___) async {});
      await tapSubmit(tester);
      expect(find.text('Please fill all the fields!'), findsOneWidget);
      expect(calls, isEmpty);
      await flushBanner(tester);
    });

    for (final bad in badNumbers) {
      testWidgets('rounds "$bad" is rejected on that field; nothing saved, nothing cleared', (tester) async {
        final calls = await open(tester, (_, __, ___) async {});
        await fillFolk(tester, rounds: bad);
        await tapSubmit(tester);
        expect(calls, isEmpty);
        expect(find.text(kWholeNumberMessage), findsOneWidget);
        expect(fieldTexts(tester)[3], bad);
        expect(fieldTexts(tester)[4], '30');
        expect(find.text('Sadhana submitted successfully'), findsNothing);
        await flushBanner(tester);
      });
    }

    testWidgets('book reading and academics are checked as well', (tester) async {
      final calls = await open(tester, (_, __, ___) async {});
      await fillFolk(tester, book: '3.0', academics: '1h');
      await tapSubmit(tester);
      expect(calls, isEmpty);
      expect(find.text(kWholeNumberMessage), findsNWidgets(2));
      await flushBanner(tester);
    });

    testWidgets('success: saved once with the parsed numbers and the extra-lecture points, THEN banner and clear', (tester) async {
      final completer = Completer<void>();
      final calls = await open(tester, (_, __, ___) => completer.future);
      await fillFolk(tester);
      await tapSubmit(tester);
      expect(calls.length, 1);
      expect(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text('Sadhana submitted successfully'), findsNothing);
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      expect(calls.length, 1);
      completer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Sadhana submitted successfully'), findsOneWidget);
      expect(fieldTexts(tester), everyElement(''));
      final (report, date, extra) = calls.single;
      expect(date, '08-10-2026');
      expect(report.chantRounds, 16);
      expect(report.bookReading, 30);
      expect(report.classHearing, 2);
      expect(report.dailyServices, 1);
      expect(extra, 1.0);
      await flushBanner(tester);
    });

    testWidgets('failure keeps input and a retry sends the same report again', (tester) async {
      var attempt = 0;
      final calls = await open(tester, (_, __, ___) async {
        attempt++;
        if (attempt == 1) throw StateError('boom');
      });
      await fillFolk(tester);
      final before = fieldTexts(tester);
      await tapSubmit(tester);
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't save your report — please try again"), findsOneWidget);
      expect(fieldTexts(tester), before);
      await flushBanner(tester);
      await tapSubmit(tester);
      await tester.pump();
      await tester.pump();
      expect(calls.length, 2);
      expect(calls[0].$1.toMap(), calls[1].$1.toMap());
      expect(find.text('Sadhana submitted successfully'), findsOneWidget);
      await flushBanner(tester);
    });

    testWidgets('timeout message, input kept', (tester) async {
      await open(tester, (_, __, ___) => Completer<void>().future, timeout: const Duration(milliseconds: 200));
      await fillFolk(tester);
      final before = fieldTexts(tester);
      await tapSubmit(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.text("Couldn't reach the server — please try again"), findsOneWidget);
      expect(fieldTexts(tester), before);
      await flushBanner(tester);
    });

    testWidgets('profile incomplete message, input kept', (tester) async {
      await open(tester, (_, __, ___) async => throw const SadhanaSaveException(SadhanaSaveFailure.profileIncomplete));
      await fillFolk(tester);
      final before = fieldTexts(tester);
      await tapSubmit(tester);
      await tester.pump();
      await tester.pump();
      expect(find.text('Your profile is incomplete — please contact your guide.'), findsOneWidget);
      expect(fieldTexts(tester), before);
      expect(find.text('Sadhana submitted successfully'), findsNothing);
      await flushBanner(tester);
    });
  });

  // ======================================================== loader 1: the dates stream
  group('availableDatesStream — the current category only, errors forwarded', () {
    late StreamController<QuerySnapshot<Map<String, dynamic>>> folk;
    late StreamController<QuerySnapshot<Map<String, dynamic>>> hostel;

    Stream<Set<String>> build() {
      folk = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
      hostel = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
      return availableDatesStream('Asha', snapshotsFor: (c) => (c == 'sadhana-reports' ? folk : hostel).stream);
    }

    setUp(() => ReportCategory.instance.debugSetRole('Stay at FOLK'));

    tearDown(() async {
      await folk.close();
      await hostel.close();
      ReportCategory.instance.debugReset();
    });

    test('a FOLK student: only the FOLK collection counts; the hostel collection is not even listened to', () async {
      final events = <Set<String>>[];
      final sub = build().listen(events.add);
      expect(hostel.hasListener, isFalse);
      folk.add(FakeSnapshot(['01-10-2026', '02-10-2026']));
      hostel.add(FakeSnapshot(['03-10-2026']));
      await Future<void>.delayed(Duration.zero);
      expect(events.single, {'01-10-2026', '02-10-2026'});
      await sub.cancel();
    });

    test('FOLK -> Hostel, live: the other category\'s days vanish at once, new reports count; Hostel -> FOLK: they return', () async {
      final events = <Set<String>>[];
      final sub = build().listen(events.add);
      folk.add(FakeSnapshot(['01-10-2026', '02-10-2026']));
      await Future<void>.delayed(Duration.zero);
      expect(events.last, {'01-10-2026', '02-10-2026'});

      ReportCategory.instance.debugSetRole('Stay at Hostel'); // a guide moves him, no restart
      await Future<void>.delayed(Duration.zero);
      expect(folk.hasListener, isFalse, reason: 'the FOLK collection is no longer read');
      expect(hostel.hasListener, isTrue);
      hostel.add(FakeSnapshot(<String>[])); // nothing filed as Hostel yet: every day red, zero submitted
      await Future<void>.delayed(Duration.zero);
      expect(events.last, <String>{});
      hostel.add(FakeSnapshot(['05-10-2026'])); // a new Hostel report counts
      await Future<void>.delayed(Duration.zero);
      expect(events.last, {'05-10-2026'});

      ReportCategory.instance.debugSetRole('Stay at Localite'); // Hostel and Localite are one category: no change
      await Future<void>.delayed(Duration.zero);
      expect(hostel.hasListener, isTrue);

      ReportCategory.instance.debugSetRole('Stay at FOLK'); // and back: the saved FOLK days return
      await Future<void>.delayed(Duration.zero);
      folk.add(FakeSnapshot(['01-10-2026', '02-10-2026']));
      await Future<void>.delayed(Duration.zero);
      expect(events.last, {'01-10-2026', '02-10-2026'});
      expect(hostel.hasListener, isFalse);
      await sub.cancel();
    });

    test('an error from the current collection reaches the listener, and no data is invented', () async {
      final events = <Set<String>>[];
      final errors = <Object>[];
      final sub = build().listen(events.add, onError: errors.add);
      folk.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect((errors.single as FirebaseException).code, 'permission-denied');
      expect(events, isEmpty);
      await sub.cancel();
    });

    testWidgets('the Calendar shows a friendly line and Retry instead of the ghost or the raw error', (tester) async {
      phone(tester);
      final controller = StreamController<Set<String>>();
      addTearDown(controller.close);
      await tester.pumpWidget(app(CalendarPage(username: 'Asha', role: 'Stay at Hostel', datesStream: controller.stream)));
      await tester.pump();
      expect(find.text("Couldn't load your calendar just now."), findsNothing, reason: 'ghost while waiting');
      controller.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("Couldn't load your calendar just now."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Error:'), findsNothing);
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.textContaining('Submit Sadhana'), findsNothing);
    });

    testWidgets('and with data the Submit Sadhana button is there', (tester) async {
      phone(tester);
      final controller = StreamController<Set<String>>();
      addTearDown(controller.close);
      await tester.pumpWidget(app(CalendarPage(username: 'Asha', role: 'Stay at Hostel', datesStream: controller.stream)));
      controller.add(<String>{});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.scrollUntilVisible(find.textContaining('Submit Sadhana'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Submit Sadhana'), findsOneWidget);
    });
  });

  // ======================================================== loader 2: the tab host
  group('CurvedNavBar — a failed first load shows Retry', () {
    testWidgets('error, Retry, then the screens', (tester) async {
      phone(tester);
      var loads = 0;
      final completer = Completer<({String name, String role})>();
      await tester.pumpWidget(app(CurvedNavBar(
        'Stay at Hostel',
        loadUser: () {
          loads++;
          if (loads == 1) throw StateError('offline');
          return completer.future;
        },
        buildScreens: (name, role) => [
          const Text('insights tab'),
          const Text('journey tab'),
          Text('sadhana tab for $name ($role)'),
          const Text('profile tab'),
        ],
        journeyUnseen: Stream<bool>.value(false),
      )));
      await tester.pump();
      await tester.pump();
      expect(loads, 1);
      expect(find.byType(NavHostError), findsOneWidget);
      expect(find.text("Couldn't load your profile"), findsOneWidget);
      expect(find.byType(NavHostGhost), findsNothing, reason: 'no loader forever');
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.getSize(find.byType(PrimaryButton)).height, greaterThanOrEqualTo(48));

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(loads, 2);
      expect(find.byType(NavHostError), findsNothing);
      expect(find.byType(NavHostGhost), findsOneWidget, reason: 'the ghost while it loads again');

      completer.complete((name: 'Asha', role: 'Stay at Hostel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('sadhana tab for Asha (Stay at Hostel)'), findsOneWidget);
      expect(find.byType(NavHostError), findsNothing);
    });

    testWidgets('Retry that fails again shows the error again', (tester) async {
      phone(tester);
      var loads = 0;
      await tester.pumpWidget(app(CurvedNavBar(
        'Stay at Hostel',
        loadUser: () async {
          loads++;
          throw StateError('still offline');
        },
        buildScreens: (n, r) => [for (var i = 0; i < 4; i++) const SizedBox()],
        journeyUnseen: Stream<bool>.value(false),
      )));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(loads, 2);
      expect(find.byType(NavHostError), findsOneWidget);
    });

    testWidgets('the error state does not overflow at text scale 1.6', (tester) async {
      phone(tester, 1.6);
      await tester.pumpWidget(app(const Scaffold(body: NavHostError(onRetry: _noop))));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

void _noop() {}

// Minimal stand-ins for Firestore snapshots (only `docs` and `id` are read).
class FakeDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FakeDoc(this.id);
  @override
  final String id;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSnapshot implements QuerySnapshot<Map<String, dynamic>> {
  FakeSnapshot(List<String> ids) : docs = [for (final i in ids) FakeDoc(i)];
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
