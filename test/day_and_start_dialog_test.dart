import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SadhanaStats.dart';
import 'package:folk_app/widgets/CommitmentDateDialog.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/SadhanaDayDialog.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The Calendar's day-details dialog and the books' commitment-date dialog.
// Real app fonts, 360 dp, text scale 1.0 / 1.3 / 1.6, light and dark, reduce motion.
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

const fullReport = <String, dynamic>{
  'chantRounds': 16,
  'bookReading': 90,
  'classHearing': 2,
  'dailyServices': 1,
  'templeEntry': '05:20',
  'finishTiming': '19:15',
  'sleepTiming': '22:30', // not a row today, not a row now
};

final today = DateTime.now();
String key(DateTime d) => sadhanaDateKey(d);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // ============================================================== calendar
  group('Calendar: a submitted day opens a dialog', () {
    late List<(String, String)> reads;
    Completer<Map<String, dynamic>?>? gate;

    Future<void> openCalendar(WidgetTester tester,
        {bool dark = false, bool reduce = true, double scale = 1.0, Future<Map<String, dynamic>?> Function(String, String)? reader}) async {
      reads = [];
      phone(tester, scale);
      await tester.pumpWidget(host(
        CalendarPage(
          username: 'Asha',
          role: 'Stay at FOLK',
          datesStream: Stream.value(<String>{key(today)}),
          dayReader: (name, id) {
            reads.add((name, id));
            return (reader ?? (_, __) async => fullReport)(name, id);
          },
        ),
        dark: dark,
        reduce: reduce,
      ));
      await tester.pump();
      await tester.pump();
    }

    Finder dayCell(int day) =>
        find.descendant(of: find.byType(TableCalendar<dynamic>), matching: find.text('$day'));

    double extent(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent;

    testWidgets('tapping the submitted day opens the dialog: date header, one row per stat, same labels, no emoji, no inline card', (tester) async {
      await openCalendar(tester);
      final before = extent(tester);
      await tester.tap(dayCell(today.day));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.byType(SadhanaDayDialog), findsOneWidget);
      expect(find.text(DateFormat('EEEE, d MMM yyyy').format(today)), findsOneWidget);
      for (final row in [
        ('Chanting Rounds', '16'),
        ('Book Reading', '90'),
        ('Class Hearing', '2'),
        ('Daily Services', '1'),
        ('Temple Entry', '05:20'),
        ('Finish Timing', '19:15'),
      ]) {
        final inDialog = find.byType(SadhanaDayDialog);
        expect(find.descendant(of: inDialog, matching: find.text(row.$1)), findsOneWidget, reason: row.$1);
        expect(find.descendant(of: inDialog, matching: find.text(row.$2)), findsOneWidget, reason: row.$2);
      }
      expect(find.descendant(of: find.byType(SadhanaDayDialog), matching: find.text('22:30')), findsNothing, reason: 'sleep was never a row');
      // no emoji clutter, and the old card's title is gone
      final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(SadhanaDayDialog), matching: find.byType(Text)))) {
        expect(emoji.hasMatch(t.data ?? ''), isFalse, reason: t.data);
      }
      expect(find.text('Sadhana Stats'), findsNothing);
      // the same read, once, by this student's name and the dd-MM-yyyy id
      expect(reads, [('Asha', key(today))]);

      // behind the dialog nothing grew
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(extent(tester), before, reason: 'the page does not grow below the calendar');
      expect(find.text('Sadhana Stats'), findsNothing);
    });

    testWidgets('X, a tap outside, and the system back button each close it', (tester) async {
      await openCalendar(tester);
      Future<void> open() async {
        await tester.tap(dayCell(today.day));
        await tester.pumpAndSettle();
        expect(find.byType(SadhanaDayDialog), findsOneWidget);
      }

      await open();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(SadhanaDayDialog), findsNothing, reason: 'X');

      await open(); // the same day again: it opens every time
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(SadhanaDayDialog), findsNothing, reason: 'tap outside');

      await open();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SadhanaDayDialog), findsNothing, reason: 'back');
      expect(reads.length, 3, reason: 'one read per opening');
    });

    testWidgets('closing lets go of the day: the Submit button is back', (tester) async {
      await openCalendar(tester);
      expect(find.byType(PrimaryButton), findsOneWidget);
      await tester.tap(dayCell(today.day));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(PrimaryButton), findsOneWidget);
    });

    testWidgets('while it loads the rows are ghosts; then the rows replace them', (tester) async {
      gate = Completer<Map<String, dynamic>?>();
      await openCalendar(tester, reader: (_, __) => gate!.future);
      await tester.tap(dayCell(today.day));
      await tester.pump();
      await tester.pump();
      expect(find.descendant(of: find.byType(SadhanaDayDialog), matching: find.byType(GhostPlaceholder)), findsNWidgets(3));
      expect(find.text('Chanting Rounds'), findsNothing);
      gate!.complete(fullReport);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(SadhanaDayDialog), matching: find.byType(GhostPlaceholder)), findsNothing);
      expect(find.text('Chanting Rounds'), findsOneWidget);
    });

    for (final c in [('no report', (String _, String __) async => null), ('an empty report', (String _, String __) async => <String, dynamic>{}), ('a failed read', (String _, String __) async => throw Exception('offline'))]) {
      testWidgets('${c.$1}: a friendly line, still closable', (tester) async {
        await openCalendar(tester, reader: c.$2 as Future<Map<String, dynamic>?> Function(String, String));
        await tester.tap(dayCell(today.day));
        await tester.pumpAndSettle();
        expect(find.text('There are no details for this day.'), findsOneWidget);
        expect(find.text('Sadhana Stats'), findsNothing);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(SadhanaDayDialog), findsNothing);
      });
    }

    testWidgets('a missed day opens nothing and reads nothing, as before', (tester) async {
      if (today.day < 2) return; // no earlier day on this month's page today
      await openCalendar(tester);
      await tester.tap(dayCell(1));
      await tester.pumpAndSettle();
      expect(find.byType(SadhanaDayDialog), findsNothing);
      expect(reads, isEmpty);
      expect(find.text('Sadhana Stats'), findsNothing);
      // it is selected, so the Submit button is hidden only for a submitted day: still shown here
      expect(find.byType(PrimaryButton), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        for (final reduce in [false, true]) {
          testWidgets('dialog draws without overflow — ${dark ? 'dark' : 'light'}, text $scale, reduce motion $reduce', (tester) async {
            await openCalendar(tester, dark: dark, scale: scale, reduce: reduce);
            await tester.tap(dayCell(today.day));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final dialog = tester.getRect(find.descendant(of: find.byType(SadhanaDayDialog), matching: find.byType(Material)).first);
            expect(dialog.left, greaterThanOrEqualTo(0));
            expect(dialog.right, lessThanOrEqualTo(360));
            expect(dialog.top, greaterThanOrEqualTo(0));
            expect(dialog.bottom, lessThanOrEqualTo(800));
            for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(SadhanaDayDialog), matching: find.byType(Text)))) {
              final box = tester.renderObject<RenderParagraph>(find.byWidget(t));
              expect(box.didExceedMaxLines, isFalse, reason: t.data);
            }
            // the close button is a 48 dp target
            expect(tester.getSize(find.ancestor(of: find.byIcon(Icons.close_rounded), matching: find.byType(Semantics)).first).shortestSide, greaterThanOrEqualTo(44));
          });
        }
      }
    }
  });

  // ================================================================== books
  group('Books: the commitment-date dialog can be closed, and closing writes nothing', () {
    String? result = 'untouched';
    var opened = 0;

    Future<void> open(WidgetTester tester, {bool dark = false, double scale = 1.0, bool reduce = true}) async {
      result = 'untouched';
      opened = 0;
      phone(tester, scale);
      await tester.pumpWidget(host(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  opened++;
                  result = await showCommitmentDateDialog(context, title: 'Bhagavad-gita As It Is');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        dark: dark,
        reduce: reduce,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Set your commitment date'), findsOneWidget);
    }

    testWidgets('Cancel closes it with no answer', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Set your commitment date'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('a tap outside closes it with no answer', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Set your commitment date'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('the system back button closes it with no answer', (tester) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Set your commitment date'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('even after a date was chosen, closing answers nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text('Tap to choose a date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('starting works as before: Start Reading is off until a date is chosen, then answers that date', (tester) async {
      await open(tester);
      ElevatedButton start() => tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Start Reading'));
      expect(start().onPressed, isNull);
      await tester.tap(find.text('Tap to choose a date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the picker opens on today
      await tester.pumpAndSettle();
      final iso = DateTime.now().toIso8601String().split('T')[0];
      expect(find.text(iso), findsOneWidget);
      expect(start().onPressed, isNotNull);
      await tester.tap(find.text('Start Reading'));
      await tester.pumpAndSettle();
      expect(result, iso);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('no overflow — ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
          await open(tester, dark: dark, scale: scale, reduce: scale == 1.3);
          expect(tester.takeException(), isNull);
          final dialog = tester.getRect(find.byType(AlertDialog));
          expect(dialog.left, greaterThanOrEqualTo(0));
          expect(dialog.right, lessThanOrEqualTo(360));
          expect(dialog.bottom, lessThanOrEqualTo(800));
          expect(find.text('Cancel'), findsOneWidget);
          expect(find.text('Start Reading'), findsOneWidget);
        });
      }
    }

    test('NO write happens before "Start Reading": the proof in the code', () {
      final src = File('lib/pages/BookPageList.dart').readAsStringSync();
      final start = src.indexOf('Future<bool> _ensureCommitmentDate(');
      final end = src.indexOf('Future<String?> _showCommitmentDateDialog(');
      final fn = src.substring(start, end);
      final dialogCall = fn.indexOf('_showCommitmentDateDialog(title: title)');
      final nullReturn = fn.indexOf('if (chosen == null || !mounted) return false;');
      final firstWrite = fn.indexOf('runTransaction');
      expect(dialogCall, greaterThan(0));
      expect(nullReturn, greaterThan(dialogCall), reason: 'a closed dialog returns false straight away');
      expect(firstWrite, greaterThan(nullReturn), reason: 'the only write is after that return');
      // before the dialog is even shown, the function only READS
      final beforeDialog = fn.substring(0, dialogCall);
      for (final write in ['.set(', '.update(', '.delete(', 'runTransaction', '.add(']) {
        expect(beforeDialog.contains(write), isFalse, reason: 'no $write before the dialog');
      }
      expect(fn.substring(dialogCall, nullReturn).contains('.set('), isFalse);

      // the two entries stop there: neither opens the reader / the Update sheet
      final open = src.substring(src.indexOf('Future<void> _openBook('));
      expect(open.indexOf('if (!committed || !mounted) return;'), lessThan(open.indexOf('BookReaderPage(')));
      final update = src.substring(src.indexOf('Future<void> _openUpdateSheet('));
      expect(update.indexOf('if (!committed || !mounted) return;'), lessThan(update.indexOf("'madeNotes': madeNotes")));
      // and this dialog is used by those two only
      expect('_ensureCommitmentDate('.allMatches(src).length, 3, reason: 'its definition and the two callers');
      expect(src.contains('barrierDismissible: false'), isFalse);
      expect(File('lib/widgets/CommitmentDateDialog.dart').readAsStringSync().contains('canPop: false'), isFalse);
    });
  });
}
