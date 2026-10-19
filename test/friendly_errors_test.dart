import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/LeaderboardPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/widgets/FolkErrorRetry.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:table_calendar/table_calendar.dart';

import 'text_scale_test.dart' show loadAppFonts;

// A failed read must never put the technical error on screen ("[cloud_firestore/permission-
// denied] ...") and must never leave a ghost or a blank: every screen says one friendly
// line and offers Retry, and Retry reads again.

const rawFirestoreError =
    '[cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation.';

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

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

void expectNoRawError(WidgetTester tester) {
  expect(find.textContaining('permission-denied'), findsNothing);
  expect(find.textContaining('cloud_firestore'), findsNothing);
  expect(find.textContaining('Error:'), findsNothing);
  expect(find.textContaining('Exception'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  tearDown(() => GenderDirectory.useForTests(null));

  group('FolkErrorRetry', () {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 1.6]) {
        testWidgets('says one friendly line and a hint, and Retry calls back (${dark ? 'dark' : 'light'}, text x$scale)', (tester) async {
          phone(tester, scale);
          var retries = 0;
          await tester.pumpWidget(host(
            Scaffold(body: FolkErrorRetry(message: "Couldn't load this thing just now.", onRetry: () => retries++)),
            dark: dark,
          ));
          expect(find.text("Couldn't load this thing just now."), findsOneWidget);
          expect(find.text(FolkErrorRetry.hint), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'no overflow at any text size');
          await tester.tap(find.byType(PrimaryButton));
          expect(retries, 1);
        });
      }
    }

    testWidgets('compact has no big icon and still offers Retry', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const Scaffold(body: FolkErrorRetry(message: 'x', onRetry: _noop, compact: true))));
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('FolkRetryScope runs its builder again on Retry', (tester) async {
      phone(tester);
      var builds = 0;
      await tester.pumpWidget(host(Scaffold(
        body: FolkRetryScope(builder: (context, retry) {
          builds++;
          return FolkErrorRetry(message: 'm', onRetry: retry);
        }),
      )));
      final before = builds;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(builds, greaterThan(before));
    });
  });

  group('Sadhana calendar', () {
    testWidgets('a failed read: a friendly line and Retry, never the raw error; Retry reads again and the calendar returns', (tester) async {
      phone(tester);
      final controller = StreamController<Set<String>>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(host(CalendarPage(
        username: 'Asha',
        role: 'Stay at FOLK',
        datesStream: controller.stream,
        dayReader: (name, id) async => {'chantRounds': 16},
      )));
      controller.addError(rawFirestoreError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text("Couldn't load your calendar just now."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expectNoRawError(tester);
      expect(find.byType(TableCalendar<dynamic>), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      controller.add({'01-01-2026'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
    });
  });

  group('the Leaderboard', () {
    testWidgets('a failed read: a friendly line + Retry, no raw error; Retry reads again and the board returns', (tester) async {
      phone(tester);
      GenderDirectory.useForTests(() async => const GenderDirectory(mine: 'male', femaleNames: {}, femaleUids: {}));
      final controller = StreamController<Map<String, Map<String, dynamic>>>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(host(LeaderboardPage(username: 'Asha', docsStream: controller.stream, changesLoader: (_) async => {})));
      await tester.pump();
      await tester.pump();
      controller.addError(Exception(rawFirestoreError));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("Couldn't load the leaderboard just now."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expectNoRawError(tester);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      controller.add({'Asha': {'weekly.total_score': 12.0}});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Asha'), findsWidgets);
      expectNoRawError(tester);
    });
  });

  group('source guarantee', () {
    test('no screen prints a raw error into a Text', () {
      final offenders = <String>[];
      final raw = RegExp(r"""Text\(\s*["']Error: \$""");
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        if (raw.hasMatch(text)) offenders.add(f.path);
        if (RegExp(r"""Text\(\s*["'][^"']*\$\{[a-zA-Z_.]*\.error\}""").hasMatch(text)) offenders.add('${f.path} (snapshot.error)');
      }
      expect(offenders, isEmpty, reason: 'a failed read must show a friendly line + Retry (FolkErrorRetry), never the error text');
    });
  });
}

void _noop() {}
