import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/ChallengeRange.dart';
import 'package:folk_app/widgets/Group2Widgets.dart';

import 'group2_text_scale_test.dart' show inside, page, phone;
import 'text_scale_test.dart' show loadAppFonts, scales;

/// Master 2 A — the Student app's half of the chanting competition range.
///
/// The server decides which days count and writes each student's rounds per
/// day (`functions/challenges.js`). This is what the student sees: the span in
/// the date line, the total ranking (unchanged — each row's `rounds` is now
/// the student's total across the span) and a day-by-day table.
///
/// The two apps carry the same `ChallengeRange.dart`; the pure-logic tests
/// here mirror the Guide app's so a drift between the copies shows up.

Map<String, dynamic> range() => {
      'startDateKey': '15-10-2026',
      'endDateKey': '20-10-2026',
      'targetDateKey': '20-10-2026',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // -------------------------------------------------------------------------
  // the span
  // -------------------------------------------------------------------------
  group('the span of a competition', () {
    test('a competition made before ranges existed is one day', () {
      final s = ChallengeSpan.of({'targetDateKey': '12-08-2026'})!;
      expect(s.isRange, isFalse);
      expect(s.label, '12 Aug 2026');
    });

    test('a range says from-to', () {
      final s = ChallengeSpan.of(range())!;
      expect(s.isRange, isTrue);
      expect(s.label, '15 Oct – 20 Oct 2026');
      expect(s.dayCount, 6);
    });

    test('start == end is one day', () {
      final s = ChallengeSpan.of({
        'startDateKey': '20-10-2026',
        'endDateKey': '20-10-2026',
      })!;
      expect(s.isRange, isFalse);
    });

    test('with only the timestamp it still finds the day', () {
      final s = ChallengeSpan.of(
          {'targetDate': Timestamp.fromDate(DateTime(2026, 8, 12))})!;
      expect(s.label, '12 Aug 2026');
    });

    test('a document an OLD build wrote reads exactly as it always did', () {
      // The shape every challenge had before this change: no start/end at all.
      final s = ChallengeSpan.of({
        'name': 'Ekadashi',
        'targetDateKey': '12-08-2026',
        'targetDate': Timestamp.fromDate(DateTime(2026, 8, 12)),
      })!;
      expect(s.isRange, isFalse);
      expect(s.dayKeys, ['12-08-2026']);
    });

    test('a document with no date has no span, and does not throw', () {
      expect(ChallengeSpan.of({}), isNull);
      expect(ChallengeSpan.of({'targetDateKey': 'garbage'}), isNull);
    });

    test('a span crossing a month end lists every day', () {
      final s = ChallengeSpan.of(
          {'startDateKey': '30-10-2026', 'endDateKey': '02-11-2026'})!;
      expect(s.dayKeys, ['30-10-2026', '31-10-2026', '01-11-2026', '02-11-2026']);
    });
  });

  group('reading a day key', () {
    test('real dates parse, impossible ones do not', () {
      expect(parseChallengeDayKey('05-03-2026'), DateTime(2026, 3, 5));
      for (final bad in ['', 'x', '2026-10-15', '31-02-2026', '10-13-2026', null]) {
        expect(parseChallengeDayKey(bad), isNull, reason: '$bad');
      }
    });
  });

  // -------------------------------------------------------------------------
  // the table
  // -------------------------------------------------------------------------
  group('the day-by-day table', () {
    final span = ChallengeSpan.of(range())!;
    Map<String, dynamic> row(String n, Map<String, int> d) =>
        {'studentName': n, 'rounds': d.values.fold(0, (a, b) => a + b), 'byDay': d};

    test('every day gets a row, including days nobody chanted', () {
      final t = buildDayTable(span, [row('Ravi', {'15-10-2026': 16, '18-10-2026': 8})]);
      expect(t.length, 6);
      final gap = t.firstWhere((d) => d.dayKey == '16-10-2026');
      expect(gap.studentCount, 0);
      expect(gap.rounds, 0);
    });

    test('who chanted how many, most first, and how many students', () {
      final t = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 16}),
        row('Om', {'15-10-2026': 4}),
      ]);
      expect(t.first.studentCount, 2);
      expect(t.first.rounds, 20);
      expect(t.first.contributors.map((c) => c.name), ['Ravi', 'Om']);
    });

    test('the days add up to the total', () {
      final t = buildDayTable(span, [
        row('Ravi', {'15-10-2026': 16, '16-10-2026': 8}),
        row('Om', {'17-10-2026': 4}),
      ]);
      expect(t.fold(0, (a, d) => a + d.rounds), 28);
    });

    test('a row from before ranges lands on the last day', () {
      final t = buildDayTable(span, [
        {'studentName': 'Old', 'rounds': 12},
      ]);
      expect(t.last.dayKey, '20-10-2026');
      expect(t.last.rounds, 12);
    });

    test('a day outside the span cannot add a column', () {
      final t = buildDayTable(span, [row('Ravi', {'15-10-2026': 16, '01-01-2030': 99})]);
      expect(t.length, 6);
      expect(t.fold(0, (a, d) => a + d.rounds), 16);
    });
  });

  // -------------------------------------------------------------------------
  // what it looks like
  // -------------------------------------------------------------------------
  final span = ChallengeSpan.of(range())!;
  final rows = [
    {
      'studentName': 'Bhaktivedanta Swami Prabhupada Das Anudas',
      'rounds': 40,
      'byDay': {'15-10-2026': 16, '16-10-2026': 16, '17-10-2026': 8},
    },
    {
      'studentName': 'Om',
      'rounds': 4,
      'byDay': {'15-10-2026': 4},
    },
  ];

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text $scale, 360 dp';

      testWidgets('the day table fits and stays inside its card ($s)', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(page(
          ChallengeDayTable(days: buildDayTable(span, rows)),
          dark: dark,
          reduce: true,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: s);
        expect(find.text('Day by day'), findsOneWidget);
        expect(find.byType(ExpansionTile), findsNWidgets(6), reason: 'one per day');
        inside(tester, find.byType(ChallengeDayTable), s);
      });

      testWidgets('a day opens and a long name still fits ($s)', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(page(
          ChallengeDayTable(days: buildDayTable(span, rows)),
          dark: dark,
          reduce: true,
        ));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('day-15-10-2026')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: s);
        expect(find.text('Om'), findsOneWidget);
        expect(find.text('2 students'), findsOneWidget);
        expect(find.textContaining('Bhaktivedanta'), findsOneWidget);
      });
    }
  }

  testWidgets('an empty day says nobody filed, and has nobody to open', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(page(
      ChallengeDayTable(days: buildDayTable(span, rows)),
      reduce: true,
    ));
    await tester.pump();
    expect(find.text('Nobody filed'), findsWidgets);
  });
}
