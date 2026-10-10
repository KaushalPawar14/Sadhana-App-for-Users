import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/InsightsData.dart';
import 'package:folk_app/utils/SadhanaStats.dart';
import 'package:folk_app/widgets/FolkCard.dart';
import 'package:folk_app/widgets/InsightsGraphCarousel.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The one small stat on each Insights graph's title line. Real app fonts loaded.
//
// "Today" is Wednesday 14 Oct 2026: the week is Mon 12 - Sun 18 Oct, the month is
// October.
final today = DateTime(2026, 10, 14);

InsightGraphSpec graph(String id) => kInsightGraphs.firstWhere((g) => g.id == id);

// One report per day: [day] -> its fields.
Reports reports(Map<int, Map<String, dynamic>> byDay, {int month = 10}) => {
      for (final e in byDay.entries) sadhanaDateKey(DateTime(2026, month, e.key)): e.value,
    };

String? stat(String id, Reports r, [InsightPeriod p = InsightPeriod.weekly]) =>
    statFor(graph: graph(id), period: p, reports: r, today: today);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('the numbers', () {
    test('Chanting: highest daily value', () {
      expect(stat('chanting', reports({12: {'chantRounds': 16}, 13: {'chantRounds': 12}, 14: {'chantRounds': 0}})), 'Highest 16');
      expect(stat('chanting', reports({12: {'chantRounds': 0}})), 'Highest 0');
    });

    test('Reading: average minutes per reported day (days without a report are not counted)', () {
      expect(stat('reading', reports({12: {'bookReading': 30}, 14: {'bookReading': 40}})), 'Avg 35 min');
      // 13 has no report at all, 15 has a report without the field: both left out
      expect(stat('reading', reports({12: {'bookReading': 20}, 13: {'chantRounds': 16}, 14: {'bookReading': 31}})), 'Avg 26 min');
    });

    test('Hearing: average score of the reported days — each day scores value / 2 (Fully 100%, Partial 50%, Missed 0%)', () {
      // the worked example: values 2, 1, 0 -> (2+1+0) / (2 x 3) = 3 / 6 = 50%
      expect(stat('hearing', reports({12: {'classHearing': 2}, 13: {'classHearing': 1}, 14: {'classHearing': 0}})), 'Heard 50%');
      // all Fully -> 100%; all Missed -> 0%; one Partial -> 50%
      expect(stat('hearing', reports({12: {'classHearing': 2}, 13: {'classHearing': 2}, 14: {'classHearing': 2}})), 'Heard 100%');
      expect(stat('hearing', reports({12: {'classHearing': 0}, 13: {'classHearing': 0}})), 'Heard 0%');
      expect(stat('hearing', reports({12: {'classHearing': 1}})), 'Heard 50%');
      // 2, 2, 1 -> 5 / 6 = 83.3 -> 83%;   1, 0, 0 -> 1 / 6 = 16.7 -> 17%
      expect(stat('hearing', reports({12: {'classHearing': 2}, 13: {'classHearing': 2}, 14: {'classHearing': 1}})), 'Heard 83%');
      expect(stat('hearing', reports({12: {'classHearing': 1}, 13: {'classHearing': 0}, 14: {'classHearing': 0}})), 'Heard 17%');
      // days after today are not counted, nor days with no report
      expect(stat('hearing', reports({12: {'classHearing': 2}, 16: {'classHearing': 0}})), 'Heard 100%');
      // the month: 7-11 Fully (5 x 2 = 10), 12 Partial (1), 13 Missed (0): 11 / 14 = 78.6 -> 79%
      final past = reports({
        7: {'classHearing': 2}, 8: {'classHearing': 2}, 9: {'classHearing': 2}, 10: {'classHearing': 2},
        11: {'classHearing': 2}, 12: {'classHearing': 1}, 13: {'classHearing': 0},
      });
      expect(stat('hearing', past, InsightPeriod.monthly), 'Heard 79%');
      // this week only (12 Partial, 13 Missed): 1 / 4 = 25%
      expect(stat('hearing', past), 'Heard 25%');
    });

    test('Services: the same score for dailyServices (Done fully 100%, Done partially 50%, Not done 0%)', () {
      expect(stat('services', reports({12: {'dailyServices': 2}, 13: {'dailyServices': 1}, 14: {'dailyServices': 0}})), 'Done 50%');
      // 6 x Fully (12) + 1 Partial (1) = 13 / 14 = 92.9 -> 93%
      final r = reports({
        6: {'dailyServices': 2}, 7: {'dailyServices': 2}, 8: {'dailyServices': 2}, 9: {'dailyServices': 2},
        10: {'dailyServices': 2}, 11: {'dailyServices': 2}, 12: {'dailyServices': 1},
      });
      expect(stat('services', r, InsightPeriod.monthly), 'Done 93%');
      expect(stat('services', reports({12: {'dailyServices': 0}})), 'Done 0%');
      // a report that has no dailyServices field is not a reported services day
      expect(stat('services', reports({12: {'dailyServices': 2}, 13: {'chantRounds': 4}})), 'Done 100%');
    });

    test('Temple entry: average time', () {
      expect(stat('temple', reports({12: {'templeEntry': '05:00'}, 13: {'templeEntry': '05:10'}})), 'Avg 5:05 AM');
      // the stat uses the stored times, not the bars' 10:00 AM ceiling
      expect(stat('temple', reports({12: {'templeEntry': '11:00'}})), 'Avg 11:00 AM');
    });

    test('Finish time: average, with after-midnight counted as LATE NIGHT', () {
      expect(stat('finish', reports({12: {'finishTiming': '22:00'}, 13: {'finishTiming': '23:00'}})), 'Avg 10:30 PM');
      expect(stat('finish', reports({12: {'finishTiming': '22:41'}, 13: {'finishTiming': '22:43'}})), 'Avg 10:42 PM');
      // 23:30 and 00:30: 23:30 + 24:30 = 48:00 -> 24:00 -> midnight, not noon
      expect(stat('finish', reports({12: {'finishTiming': '23:30'}, 13: {'finishTiming': '00:30'}})), 'Avg 12:00 AM');
      // 23:00, 00:30 (24:30), 01:00 (25:00): mean 24:10 -> 12:10 AM
      expect(stat('finish', reports({12: {'finishTiming': '23:00'}, 13: {'finishTiming': '00:30'}, 14: {'finishTiming': '01:00'}})), 'Avg 12:10 AM');
      // a single late finish shows as itself
      expect(stat('finish', reports({12: {'finishTiming': '00:30'}})), 'Avg 12:30 AM');
      // 04:00 and later is the same day, not "after midnight"
      expect(stat('finish', reports({12: {'finishTiming': '04:00'}})), 'Avg 4:00 AM');
    });

    test('clock formatting', () {
      expect(formatClock(0), '12:00 AM');
      expect(formatClock(30), '12:30 AM');
      expect(formatClock(5 * 60 + 5), '5:05 AM');
      expect(formatClock(12 * 60), '12:00 PM');
      expect(formatClock(22 * 60 + 42), '10:42 PM');
      expect(formatClock(24 * 60 + 42), '12:42 AM');
    });

    test('the period decides which days count; other days, future days and unreadable values are left out', () {
      final r = reports({
        3: {'chantRounds': 40}, // earlier this month, not this week
        12: {'chantRounds': 10},
        20: {'chantRounds': 99}, // a future day
      });
      expect(stat('chanting', r), 'Highest 10');
      expect(stat('chanting', r, InsightPeriod.monthly), 'Highest 40');
      expect(stat('finish', reports({12: {'finishTiming': 'late'}, 13: {'finishTiming': '25:00'}})), isNull);
      expect(stat('chanting', reports({12: {'chantRounds': 'x'}})), isNull);
    });

    test('no data in the period -> no stat; the pies never have one', () {
      expect(stat('chanting', {}), isNull);
      expect(stat('chanting', reports({3: {'chantRounds': 5}})), isNull); // only an earlier week
      expect(stat('hearing', reports({12: {'chantRounds': 5}})), isNull); // a report without the field
      expect(stat('hearingPie', reports({12: {'classHearing': 2}})), isNull);
      expect(stat('servicesPie', reports({12: {'dailyServices': 2}})), isNull);
    });

    test('each stat reads only its own graph\'s field (never combined)', () {
      final r = reports({12: {'chantRounds': 16, 'bookReading': 90, 'classHearing': 2, 'dailyServices': 0}});
      expect(stat('chanting', r), 'Highest 16');
      expect(stat('reading', r), 'Avg 90 min');
      expect(stat('hearing', r), 'Heard 100%');
      expect(stat('services', r), 'Done 0%');
    });
  });

  // ------------------------------------------------------------------ on screen
  void phone(WidgetTester tester, double scale) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  Widget host(InsightGraphSpec g, Reports r, InsightPeriod p, bool dark) => MaterialApp(
        theme: dark ? FolkTheme.dark : FolkTheme.light,
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: InsightsGraphCarousel(graphs: [g], period: p, reports: r, today: today),
          ),
        ),
      );

  // The data each graph shows, and the stat it must give, weekly and monthly.
  final week = reports({
    12: {'chantRounds': 16, 'bookReading': 30, 'classHearing': 2, 'dailyServices': 2, 'finishTiming': '23:30', 'templeEntry': '05:00'},
    13: {'chantRounds': 12, 'bookReading': 40, 'classHearing': 1, 'dailyServices': 2, 'finishTiming': '00:30', 'templeEntry': '05:10'},
    14: {'chantRounds': 8, 'bookReading': 35, 'classHearing': 2, 'dailyServices': 1, 'finishTiming': '22:41', 'templeEntry': '05:05'},
  });
  final month = reports({
    2: {'chantRounds': 20, 'bookReading': 50, 'classHearing': 2, 'dailyServices': 2, 'finishTiming': '22:00', 'templeEntry': '04:50'},
    ...{
      for (final e in week.entries) int.parse(e.key.substring(0, 2)): e.value,
    },
  });
  // Worked by hand: week = days 12-14; month = those plus day 2.
  //  hearing / services week: values 2, 1, 2 (services 2, 2, 1) -> 5 / 6 = 83%
  //  hearing / services month: day 2 is Fully, so 7 / 8 = 87.5 -> 88%
  //  finish week: 23:30 (1410) + 00:30 (1470) + 22:41 (1361) = 4241 / 3 = 1414 -> 11:34 PM
  //  finish month: (4241 + 1320) / 4 = 1390 -> 11:10 PM
  const expectedWeek = {
    'chanting': 'Highest 16', 'reading': 'Avg 35 min', 'hearing': 'Heard 83%', 'services': 'Done 83%',
    'finish': 'Avg 11:34 PM', 'temple': 'Avg 5:05 AM',
  };
  const expectedMonth = {
    'chanting': 'Highest 20', 'reading': 'Avg 39 min', 'hearing': 'Heard 88%', 'services': 'Done 88%',
    'finish': 'Avg 11:10 PM', 'temple': 'Avg 5:01 AM',
  };

  for (final dark in [false, true]) {
    for (final scale in scales) {
      for (final period in InsightPeriod.values) {
        for (final g in kInsightGraphs.where((g) => g.kind != InsightKind.pie)) {
          final r = period == InsightPeriod.weekly ? week : month;
          testWidgets('${g.id} ${period.name}, ${dark ? 'dark' : 'light'}, text $scale: stat beside the title, no overflow, same card height', (tester) async {
            phone(tester, scale);
            await tester.pumpWidget(host(g, r, period, dark));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final expected = (period == InsightPeriod.weekly ? expectedWeek : expectedMonth)[g.id];
            expect(statFor(graph: g, period: period, reports: r, today: today), expected);
            final statFinder = find.byKey(const ValueKey('graph-stat'));
            final shown = statFinder.evaluate().map((e) => e.widget as Text).where((t) {
              final c = tester.getRect(find.byWidget(t)).center.dx;
              return c > 0 && c < 360;
            }).toList();
            expect(shown.length, 1);
            expect(shown.single.data, expected);

            // same line as the title, to its right, inside the card, muted caption style
            final statRect = tester.getRect(find.byWidget(shown.single));
            final titleRect = tester.getRect(find.text(g.title).first);
            expect(statRect.left, greaterThanOrEqualTo(titleRect.right - .01), reason: 'stat never overlaps the title');
            expect((statRect.center.dy - titleRect.center.dy).abs(), lessThan(titleRect.height / 2));
            final card = tester.getRect(find.byType(FolkCard).first);
            expect(statRect.right, lessThanOrEqualTo(card.right - 18 + .01));
            final ro = tester.renderObject<RenderParagraph>(find.byWidget(shown.single));
            expect(ro.didExceedMaxLines, isFalse, reason: 'the stat is never cut');
            expect(tester.widget<Text>(find.byWidget(shown.single)).style!.fontSize, 12);

            // the card is exactly as tall as one with no stat (same graph, no data)
            final withStat = card.height;
            await tester.pumpWidget(host(g, <String, Map<String, dynamic>>{}, period, dark));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('graph-stat')), findsNothing);
            expect(tester.getRect(find.byType(FolkCard).first).height, withStat);
          });
        }
      }
    }
  }

  testWidgets('the pie charts show no stat', (tester) async {
    phone(tester, 1.0);
    for (final id in ['hearingPie', 'servicesPie']) {
      await tester.pumpWidget(host(graph(id), week, InsightPeriod.weekly, false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('graph-stat')), findsNothing);
    }
  });

  testWidgets('the title ellipsizes before anything overflows (very long stat room at 1.6)', (tester) async {
    phone(tester, 1.6);
    await tester.pumpWidget(host(graph('finish'), reports({12: {'finishTiming': '22:42'}}), InsightPeriod.weekly, false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final title = tester.renderObject<RenderParagraph>(find.text('Chanting finish time').first);
    expect(title.didExceedMaxLines, isTrue, reason: 'at 1.6x the title gives way (ellipsis), the stat stays whole');
    final stat = tester.widget<Text>(find.byKey(const ValueKey('graph-stat')).first);
    expect(stat.data, 'Avg 10:42 PM');
  });
}
