import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/InsightsData.dart';
import 'package:folk_app/utils/SadhanaStats.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/InsightBars.dart';
import 'package:folk_app/widgets/InsightTile.dart';
import 'package:folk_app/widgets/InsightsGraphCarousel.dart';
import 'package:folk_app/widgets/SadhanaStatTile.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Sadhana: the two tiles above the calendar. Insights: the Weekly / Monthly switch
// and the looping graph card. At 1.0 / 1.3 / 1.6, 360 dp, light and dark.
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

Widget host(Widget home, {bool dark = false, bool reduce = true}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: home,
    );

String key(DateTime d) => sadhanaDateKey(d);

// The heading of the graph on show: the slide whose title sits inside the card
// (the neighbouring slides are built just off to either side).
String currentTitle(WidgetTester tester) {
  final titles = {for (final g in kInsightGraphs) g.title};
  final shown = tester.widgetList<Text>(find.byType(Text)).where((t) => titles.contains(t.data)).where((t) {
    final r = tester.getRect(find.byWidget(t));
    return r.center.dx > 20 && r.center.dx < 340;
  }).map((t) => t.data!).toSet();
  expect(shown.length, 1, reason: 'exactly one graph on show: $shown');
  return shown.single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // =============================================================== Sadhana maths
  group('Sadhana tiles — the numbers', () {
    // Wednesday 14 October 2026.
    final today = DateTime(2026, 10, 14);

    test('date keys are the report ids as they are: dd-MM-yyyy', () {
      expect(sadhanaDateKey(DateTime(2026, 3, 5)), '05-03-2026');
      expect(sadhanaDateKey(DateTime(2026, 12, 31)), '31-12-2026');
    });

    test('N of M, current month: M = days before today, plus today if submitted', () {
      final dates = {for (final d in [1, 2, 3, 4]) key(DateTime(2026, 10, d))};
      final without = monthTally(dates: dates, month: today, today: today);
      expect((without.submitted, without.counted), (4, 13));
      final withToday = monthTally(dates: {...dates, key(today)}, month: today, today: today);
      expect((withToday.submitted, withToday.counted), (5, 14));
    });

    test('a past month counts the whole month', () {
      final dates = {key(DateTime(2026, 9, 1)), key(DateTime(2026, 9, 30)), key(DateTime(2026, 10, 2))};
      final sep = monthTally(dates: dates, month: DateTime(2026, 9, 1), today: today);
      expect((sep.submitted, sep.counted), (2, 30));
      final feb = monthTally(dates: {}, month: DateTime(2028, 2, 1), today: DateTime(2028, 3, 3));
      expect(feb.counted, 29, reason: 'leap year');
    });

    test('nothing to count yet: the first of the month, today not submitted (and today submitted counts 1 of 1)', () {
      final first = DateTime(2026, 11, 1);
      expect(monthTally(dates: {}, month: first, today: first).isEmpty, isTrue);
      final done = monthTally(dates: {key(first)}, month: first, today: first);
      expect((done.submitted, done.counted), (1, 1));
    });

    test('streak: ending today, or yesterday when today is not submitted yet', () {
      expect(currentStreak(dates: {key(today), key(DateTime(2026, 10, 13))}, today: today), 2);
      expect(currentStreak(dates: {key(DateTime(2026, 10, 13)), key(DateTime(2026, 10, 12))}, today: today), 2);
      expect(currentStreak(dates: {key(DateTime(2026, 10, 12))}, today: today), 0, reason: 'yesterday missed too: the streak is over');
      expect(currentStreak(dates: {}, today: today), 0);
      expect(currentStreak(dates: {key(today), key(DateTime(2026, 10, 12))}, today: today), 1, reason: 'a gap ends it');
    });

    test('streak runs across month and year boundaries, through the retained reports', () {
      final dates = {key(DateTime(2027, 1, 1)), key(DateTime(2026, 12, 31)), key(DateTime(2026, 12, 30)), key(DateTime(2026, 12, 28))};
      expect(currentStreak(dates: dates, today: DateTime(2027, 1, 1)), 3);
    });

    test('the merge code is byte-identical: SadhanaReportSource.dart is unchanged', () {
      final before = File('D:/tmp-fl/g9before/SadhanaReportSource.dart.before');
      if (before.existsSync()) {
        // line endings differ between the working copy and the saved copy; the code must not
        String norm(List<int> b) => String.fromCharCodes(b).replaceAll('\r\n', '\n');
        expect(norm(File('lib/utils/SadhanaReportSource.dart').readAsBytesSync()), norm(before.readAsBytesSync()));
      }
    });
  });

  // ============================================================ Sadhana tiles UI
  group('Sadhana tiles — on the page', () {
    Future<void> pumpCalendar(WidgetTester tester, Stream<Set<String>> stream, {double scale = 1.0, bool dark = false, bool reduce = true}) async {
      phone(tester, scale);
      await tester.pumpWidget(host(CalendarPage(username: 'Asha', role: 'Stay at FOLK', datesStream: stream), dark: dark, reduce: reduce));
    }

    testWidgets('ghosts while loading, then the two tiles with the real numbers', (tester) async {
      final c = StreamController<Set<String>>();
      addTearDown(c.close);
      await pumpCalendar(tester, c.stream, reduce: false);
      await tester.pump();
      expect(find.byType(SadhanaStatTile), findsNothing);
      expect(find.byType(GhostPlaceholder), findsWidgets);

      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      c.add({key(now), key(yesterday)});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      final tally = monthTally(dates: {key(now), key(yesterday)}, month: now, today: now);
      final streak = currentStreak(dates: {key(now), key(yesterday)}, today: now);
      expect(find.byType(SadhanaStatTile), findsNWidgets(2));
      expect(find.text('days submitted'), findsOneWidget);
      expect(find.text('current streak'), findsOneWidget);
      expect(find.text('${tally.submitted}'), findsWidgets);
      expect(find.text('of ${tally.counted}'), findsOneWidget);
      expect(find.text(streak == 1 ? 'day' : 'days'), findsOneWidget);
      expect(streak, greaterThanOrEqualTo(1));
    });

    testWidgets('the number counts up once and then just stays', (tester) async {
      final c = StreamController<Set<String>>.broadcast();
      addTearDown(c.close);
      final now = DateTime.now();
      await pumpCalendar(tester, c.stream, reduce: false);
      c.add({key(now)});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // mid count-up the streak number is below its final value or already there; after it settles it is exact
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets);
      final before = tester.binding.transientCallbackCount;
      c.add({key(now)}); // the same data again: no second count-up
      await tester.pump();
      expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(before));
    });

    testWidgets('the month arrows change "N of M" to that month', (tester) async {
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1, 1);
      final prevDays = DateTime(prev.year, prev.month + 1, 0).day;
      final dates = {key(DateTime(prev.year, prev.month, 3)), key(DateTime(prev.year, prev.month, 4)), key(DateTime(prev.year, prev.month, 5))};
      await pumpCalendar(tester, Stream.value(dates));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('of $prevDays'), findsOneWidget, reason: 'a past month counts the whole month');
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('a fresh month: a friendly line instead of "0 of 0"', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(20),
          child: SadhanaStatTile(style: FolkGradientStyle.saffron, value: 0, suffix: 'of 0', caption: 'a fresh month begins', friendly: 'Fresh start'),
        ),
      )));
      expect(find.text('Fresh start'), findsOneWidget);
      expect(find.textContaining('of 0'), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: tiles fit 360 dp, equal height, no overflow', (tester) async {
          final now = DateTime.now();
          final dates = {for (var i = 0; i < 12; i++) key(DateTime(now.year, now.month, now.day - i))};
          await pumpCalendar(tester, Stream.value(dates), scale: scale, dark: dark);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'dark=$dark scale=$scale');
          final tiles = tester.widgetList<SadhanaStatTile>(find.byType(SadhanaStatTile)).toList();
          expect(tiles.length, 2);
          final a = tester.getRect(find.byWidget(tiles[0]));
          final b = tester.getRect(find.byWidget(tiles[1]));
          expect(a.height, closeTo(b.height, .5));
          expect(a.left, 20);
          expect(b.right, 340);
          expect(b.left - a.right, closeTo(12, .5));
          // the number line never leaves its tile
          for (final t in tiles) {
            final tile = tester.getRect(find.byWidget(t));
            for (final txt in find.descendant(of: find.byWidget(t), matching: find.byType(Text)).evaluate()) {
              final r = tester.getRect(find.byWidget(txt.widget));
              expect(r.right, lessThanOrEqualTo(tile.right + .5));
              expect(r.bottom, lessThanOrEqualTo(tile.bottom + .5));
            }
          }
        });
      }
    }

    testWidgets('no new reads: the calendar still takes the one dates stream, and nothing else is read for the tiles (source check)', (tester) async {
      final src = File('lib/pages/Calendar.dart').readAsStringSync();
      expect(src, contains('mergedAvailableDatesStream(widget.username)'));
      final tiles = File('lib/widgets/SadhanaStatTile.dart').readAsStringSync() + File('lib/utils/SadhanaStats.dart').readAsStringSync();
      expect(tiles.contains('Firestore'), isFalse);
      expect(tiles.contains('SharedPreferences'), isFalse);
    });
  });

  // =============================================================== Insights data
  group('Insights data — reused computations', () {
    final wed = DateTime(2026, 10, 14);

    test('weekly = Monday to Sunday of this week; monthly = every day of this month', () {
      final w = daysOf(InsightPeriod.weekly, wed);
      expect(w.length, 7);
      expect(w.first, DateTime(2026, 10, 12));
      expect(w.last, DateTime(2026, 10, 18));
      expect(w.first.weekday, DateTime.monday);
      expect(daysOf(InsightPeriod.monthly, wed).length, 31);
      expect(daysOf(InsightPeriod.monthly, DateTime(2028, 2, 10)).length, 29);
      // a Sunday belongs to the week that began the Monday before
      expect(daysOf(InsightPeriod.weekly, DateTime(2026, 10, 18)).first, DateTime(2026, 10, 12));
    });

    Reports reports() => {
          key(DateTime(2026, 10, 12)): {'chantRounds': 16, 'bookReading': 30, 'classHearing': 2, 'dailyServices': 1, 'templeEntry': '05:30', 'finishTiming': '11:15'},
          key(DateTime(2026, 10, 13)): {'chantRounds': 8, 'bookReading': 0, 'classHearing': 0, 'dailyServices': 2, 'templeEntry': '23:00', 'finishTiming': '23:45'},
          key(DateTime(2026, 10, 14)): {'chantRounds': 20, 'classHearing': 1},
        };

    test('each graph reads the same report field the old screen read, one bar per day', () {
      final spec = {for (final g in kInsightGraphs) g.id: g};
      List<double?> values(String id) => barsFor(graph: spec[id]!, period: InsightPeriod.weekly, reports: reports(), today: wed).map((b) => b.value).toList();
      expect(values('chanting').take(3), [16, 8, 20]);
      expect(values('reading').take(3), [30, 0, null], reason: 'no bookReading on the third day: no bar');
      expect(values('hearing').take(3), [2, 0, 1]);
      expect(values('services').take(3), [1, 2, null]);
      expect(values('temple').take(2), [330, 600], reason: '05:30 -> 330 min; 23:00 is cut at the old 600-min ceiling');
      expect(values('finish').take(2), [675, 1320], reason: '11:15 -> 675; 23:45 is cut at the old 1320-min ceiling');
      expect(values('chanting').skip(3), everyElement(isNull), reason: 'days with no report have no bar');
    });

    test('time parsing is the old parsing: two parts or the day is skipped; an unreadable part is 0', () {
      expect(parseMinutes('05:30'), 330);
      expect(parseMinutes('5:3'), 303);
      expect(parseMinutes('05'), isNull);
      expect(parseMinutes('05:30:10'), isNull);
      expect(parseMinutes('xx:15'), 15);
      expect(parseMinutes(null), isNull);
    });

    test('today and future days are marked; weekly labels M..S; monthly labels only on a few days', () {
      final w = barsFor(graph: kInsightGraphs.first, period: InsightPeriod.weekly, reports: reports(), today: wed);
      expect(w.map((b) => b.label).join(), 'MTWTFSS');
      expect(w.where((b) => b.isToday).single.day, wed);
      expect(w.where((b) => b.isFuture).length, 4);
      final m = barsFor(graph: kInsightGraphs.first, period: InsightPeriod.monthly, reports: reports(), today: wed);
      expect(m.where((b) => b.label.isNotEmpty).map((b) => b.label), ['1', '5', '10', '15', '20', '25', '30']);
    });

    test('the pies count exactly as the old Graphical Analysis did', () {
      final r = {
        '01-10-2026': {'classHearing': 2, 'dailyServices': 2},
        '02-10-2026': {'classHearing': 1, 'dailyServices': 0},
        '03-10-2026': {'classHearing': 0},
        '04-10-2026': {'chantRounds': 1}, // no hearing field: not counted
        '05-10-2026': {'classHearing': 2, 'dailyServices': 1},
      };
      expect(pieCounts(r, 'classHearing'), {'Fully': 2, 'Partial': 1, 'Missed': 1});
      expect(pieCounts(r, 'dailyServices'), {'Fully': 1, 'Partial': 1, 'Missed': 1});
    });

    test('FINAL LIST AND ORDER: Chanting, Reading, Hearing, Services, Finish time, Temple entry, then the two pies', () {
      expect(kInsightGraphs.map((g) => g.name).toList(),
          ['Chanting', 'Reading', 'Hearing', 'Services', 'Finish time', 'Temple entry', 'Hearing split', 'Services split']);
      expect(kInsightGraphs.map((g) => g.field).toList(),
          ['chantRounds', 'bookReading', 'classHearing', 'dailyServices', 'finishTiming', 'templeEntry', 'classHearing', 'dailyServices']);
    });

    test('graphs whose fields do not exist for the student are skipped', () {
      final folk = {'01-10-2026': {'chantRounds': 1, 'bookReading': 1, 'classHearing': 1, 'dailyServices': 1, 'templeEntry': '05:00', 'finishTiming': '10:00'}};
      final hostel = {'01-10-2026': {'wakeUpTime': '05:00', 'chantRounds': 1, 'bookReading': 1, 'classHearing': 1, 'finishTiming': '10:00'}};
      expect(applicableGraphs(folk, 'Stay at FOLK').length, 8);
      expect(applicableGraphs(hostel, 'Stay at Hostel').map((g) => g.id), ['chanting', 'reading', 'hearing', 'finish', 'hearingPie']);
      // no reports yet: the graphs of the student's own form
      expect(applicableGraphs({}, 'Stay at FOLK').length, 8);
      expect(applicableGraphs({}, 'Stay at Localite').map((g) => g.id), ['chanting', 'reading', 'hearing', 'finish', 'hearingPie']);
      // history across a residence change keeps the FOLK-only graphs
      expect(applicableGraphs({...folk, '02-10-2026': hostel.values.first}, 'Stay at Hostel').length, 8);
    });
  });

  // ============================================================ Insights widgets
  group('Insights card', () {
    final wed = DateTime(2026, 10, 14);
    Reports reports() => {
          '12-10-2026': {'chantRounds': 16, 'bookReading': 30, 'classHearing': 2, 'dailyServices': 1, 'templeEntry': '05:30', 'finishTiming': '11:15'},
          '13-10-2026': {'chantRounds': 8, 'bookReading': 10, 'classHearing': 0, 'dailyServices': 2, 'templeEntry': '06:00', 'finishTiming': '12:00'},
          '14-10-2026': {'chantRounds': 20, 'bookReading': 20, 'classHearing': 1, 'dailyServices': 0, 'templeEntry': '05:45', 'finishTiming': '11:00'},
        };

    Widget carousel(InsightPeriod period, Reports? r, {Stream<void>? unused}) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: InsightsGraphCarousel(graphs: kInsightGraphs.toList(), period: period, reports: r, today: wed),
            ),
          ),
        );

    Finder title(String t) => find.text(t);

    testWidgets('swipe loops endlessly in both directions: ... Services split -> Chanting -> Reading ...', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, reports())));
      await tester.pump();
      expect(title('Chanting rounds'), findsOneWidget);
      final order = <String>[];
      for (var i = 0; i < 9; i++) {
        order.add(currentTitle(tester));
        await tester.drag(find.byType(PageView), const Offset(-320, 0));
        await tester.pumpAndSettle();
      }
      expect(order, ['Chanting rounds', 'Reading (minutes)', 'Class hearing', 'Daily services', 'Chanting finish time', 'Temple entry time', 'Class hearing', 'Daily services', 'Chanting rounds'],
          reason: 'after the last pie it is Chanting again');
      // after nine swipes it is on Reading; two steps back wraps past Chanting to the last graph
      await tester.drag(find.byType(PageView), const Offset(320, 0));
      await tester.pumpAndSettle();
      expect(currentTitle(tester), 'Chanting rounds');
      await tester.drag(find.byType(PageView), const Offset(320, 0));
      await tester.pumpAndSettle();
      expect(currentTitle(tester), 'Daily services', reason: 'one step back from Chanting is the last graph (the services pie)');
    });

    testWidgets('the current name is centred; previous and next are faint on either side; tapping them switches', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, reports())));
      await tester.pump();
      final cur = tester.getRect(find.text('Chanting').last);
      expect(cur.center.dx, closeTo(180, 2));
      expect(find.text('Reading'), findsOneWidget, reason: 'next, on the right');
      expect(find.text('Services split'), findsOneWidget, reason: 'previous (the loop), on the left');
      expect(tester.getRect(find.text('Services split')).center.dx, lessThan(cur.center.dx));
      expect(tester.getRect(find.text('Reading')).center.dx, greaterThan(cur.center.dx));
      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();
      expect(title('Reading (minutes)'), findsOneWidget);
      expect(tester.getRect(find.text('Reading').last).center.dx, closeTo(180, 2));
      await tester.tap(find.text('Chanting'));
      await tester.pumpAndSettle();
      expect(title('Chanting rounds'), findsOneWidget);
    });

    testWidgets('weekly: seven bars M-S; monthly: one thin bar per day with a few day numbers; today saffron, others soft violet', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, reports())));
      await tester.pump();
      var bars = tester.widget<InsightBars>(find.byType(InsightBars));
      expect(bars.bars.length, 7);
      expect(bars.monthly, isFalse);
      for (final l in ['M', 'T', 'W', 'F', 'S']) {
        expect(find.text(l), findsWidgets);
      }
      final colors = FolkTheme.light.extension<FolkColors>() ?? (throw 'no colours');
      final boxes = tester.widgetList<Container>(find.descendant(of: find.byType(InsightBars), matching: find.byType(Container))).where((c) => c.decoration is BoxDecoration && ((c.decoration as BoxDecoration).color != null || (c.decoration as BoxDecoration).gradient != null)).toList();
      final today = boxes.where((c) => (c.decoration as BoxDecoration).gradient == FolkGradients.insightToday);
      expect(today.length, 1, reason: 'one saffron bar: today');
      final others = boxes.where((c) => (c.decoration as BoxDecoration).color == colors.chartBarInactive);
      expect(others.length, 2, reason: 'the two earlier days with reports are soft violet');
      expect((boxes.first.decoration as BoxDecoration).borderRadius, BorderRadius.circular(12));

      await tester.pumpWidget(host(carousel(InsightPeriod.monthly, reports())));
      await tester.pump();
      bars = tester.widget<InsightBars>(find.byType(InsightBars));
      expect(bars.bars.length, 31);
      expect(bars.monthly, isTrue);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('14'), findsNothing, reason: 'sparse day labels');
      expect(find.text('1'), findsOneWidget);
      final thin = tester.getSize(find.descendant(of: find.byType(InsightBars), matching: find.byType(Container)).first);
      expect(thin.width, lessThan(10), reason: 'thin bars at 360 dp');
    });

    testWidgets('empty data: a friendly line, and the card is the same size as with data', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, reports())));
      await tester.pump();
      final withData = tester.getSize(find.byType(PageView)).height;
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, const {})));
      await tester.pump();
      expect(find.textContaining('reported this week yet'), findsOneWidget);
      expect(tester.getSize(find.byType(PageView)).height, withData);
      await tester.pumpWidget(host(carousel(InsightPeriod.monthly, const {})));
      await tester.pump();
      expect(find.textContaining('reported this month yet'), findsOneWidget);
    });

    testWidgets('loading: a ghost of the same size', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, reports())));
      await tester.pump();
      final h = tester.getSize(find.byType(PageView)).height;
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, null), reduce: false));
      await tester.pump();
      expect(find.byType(GhostPlaceholder), findsOneWidget);
      expect(tester.getSize(find.byType(PageView)).height, h);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    });

    testWidgets('the pie slides count the old way and show Fully / Partial / Missed', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(carousel(InsightPeriod.weekly, reports())));
      await tester.pump();
      await tester.tap(find.text('Services split'));
      await tester.pumpAndSettle();
      expect(currentTitle(tester), 'Daily services');
      for (final k in ['Fully', 'Partial', 'Missed']) {
        expect(find.text(k), findsWidgets);
      }
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        for (final period in InsightPeriod.values) {
          testWidgets('${dark ? 'dark' : 'light'}, text scale $scale, ${period.name}: every graph fits the card at 360 dp, no overflow', (tester) async {
            phone(tester, scale);
            await tester.pumpWidget(host(carousel(period, reports()), dark: dark));
            await tester.pump();
            for (var i = 0; i < kInsightGraphs.length; i++) {
              expect(tester.takeException(), isNull, reason: 'graph $i, dark=$dark scale=$scale ${period.name}');
              await tester.drag(find.byType(PageView), const Offset(-320, 0));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  // ============================================================ Insights page
  group('Insights page', () {
    final wed = DateTime(2026, 10, 14);
    Future<List<String>> pumpPage(WidgetTester tester, {String role = 'Stay at FOLK', double scale = 1.0, bool dark = false, Future<Reports> Function(String)? load}) async {
      phone(tester, scale);
      final asked = <String>[];
      await tester.pumpWidget(host(
        CompetitionPage(
          role: role,
          username: 'Asha',
          clock: () => wed,
          loadReports: load ??
              (name) async {
                asked.add(name);
                return {'14-10-2026': {'chantRounds': 20, 'classHearing': 2}};
              },
        ),
        dark: dark,
      ));
      await tester.pumpAndSettle();
      return asked;
    }

    testWidgets("the student's OWN data only: one read, with their own name", (tester) async {
      final asked = await pumpPage(tester);
      expect(asked, ['Asha']);
    });

    testWidgets('the Weekly / Monthly switch changes the bars; Weekly is first', (tester) async {
      await pumpPage(tester);
      expect(tester.widget<InsightBars>(find.byType(InsightBars)).bars.length, 7);
      expect(find.text('WEEKLY PERFORMANCE'), findsOneWidget);
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(tester.widget<InsightBars>(find.byType(InsightBars)).bars.length, 31);
      expect(find.text('MONTHLY PERFORMANCE'), findsOneWidget);
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      expect(tester.widget<InsightBars>(find.byType(InsightBars)).bars.length, 7);
    });

    testWidgets('only graphs the student has data for: a Hostel student has no Services or Temple entry', (tester) async {
      await pumpPage(tester, role: 'Stay at Hostel');
      // walk the whole loop and collect the names
      final names = <String>[];
      for (var i = 0; i < 6; i++) {
        names.add(currentTitle(tester));
        await tester.drag(find.byType(PageView), const Offset(-320, 0));
        await tester.pumpAndSettle();
      }
      expect(names.take(4), ['Chanting rounds', 'Class hearing', 'Class hearing', 'Chanting rounds'], reason: 'only the graphs with data, then it loops');
    });

    testWidgets('a failed read shows a message and Try again (never a loader forever)', (tester) async {
      var calls = 0;
      await pumpPage(tester, load: (_) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return {};
      });
      expect(find.text("Couldn't load your reports just now."), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your reports just now."), findsNothing);
      expect(calls, 2);
    });

    testWidgets('four tiles: Leaderboard full width, two equal squares, then Best Performer full width; tile heights are minimums', (tester) async {
      await pumpPage(tester);
      Rect rect(String title) => tester.getRect(find.ancestor(of: find.text(title), matching: find.byType(ConstrainedBox)).first);
      await tester.scrollUntilVisible(find.text('Best Performer'), 200, scrollable: find.byType(Scrollable).first);
      final lb = tester.getRect(find.byWidgetPredicate((w) => w is InsightTile && w.title == 'Leaderboard'));
      final wk = tester.getRect(find.byWidgetPredicate((w) => w is InsightTile && w.title == 'Weekly Performance'));
      final mo = tester.getRect(find.byWidgetPredicate((w) => w is InsightTile && w.title == 'Monthly Performance'));
      final best = tester.getRect(find.byWidgetPredicate((w) => w is InsightTile && w.title == 'Best Performer'));
      expect(rect, isNotNull);
      expect(lb.width, 320, reason: 'full width');
      for (final r in [wk, mo]) {
        expect(r.width, closeTo(154, .5));
        expect(r.height, greaterThanOrEqualTo(r.width - .5), reason: 'squares (grow only when text needs it)');
      }
      expect(best.width, 320, reason: 'Best Performer is full width, like the Leaderboard');
      expect(best.height, greaterThanOrEqualTo(154 - .5), reason: 'as tall as the squares');
      expect(lb.height, greaterThanOrEqualTo(154 - .5), reason: 'as tall as the squares');
      expect(wk.height, closeTo(mo.height, .5));
      expect(wk.top, greaterThan(lb.bottom));
      expect(best.top, greaterThan(wk.bottom));
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: the whole page at 360 dp, no overflow', (tester) async {
          await pumpPage(tester, scale: scale, dark: dark);
          await tester.tap(find.text('Monthly'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(find.text('Best Performer'), 200, scrollable: find.byType(Scrollable).first);
          expect(tester.takeException(), isNull, reason: 'dark=$dark scale=$scale');
        });
      }
    }

    test('Graphical Analysis is gone from the Student app: its files are deleted and Competition has no such tile', () {
      expect(File('lib/pages/GraphPage.dart').existsSync(), isFalse);
      expect(File('lib/scores/AllGraphs.dart').existsSync(), isFalse);
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        expect(src.contains('Graphpagedashboard'), isFalse, reason: f.path);
        expect(RegExp(r'AllGraph\(').hasMatch(src), isFalse, reason: f.path);
      }
      expect(File('lib/pages/Competition.dart').readAsStringSync().contains('Graphical Analysis'), isFalse);
    });
  });

  // ============================================================== header kickers
  group('Tab header: a small muted line above the title', () {
    Widget nav() => CurvedNavBar(
          'Stay at FOLK',
          loadUser: () async => (name: 'Asha', role: 'Stay at FOLK'),
          buildScreens: (n, r) => [for (var i = 0; i < 4; i++) Text('tab $i')],
          journeyUnseen: Stream<bool>.value(false),
        );

    Future<void> tapTab(WidgetTester tester, int index) async {
      final icons = [
        [Icons.bar_chart_rounded],
        [Icons.spa, Icons.spa_outlined],
        [Icons.event_available_outlined],
        [Icons.person_rounded, Icons.person_outline_rounded],
      ][index];
      for (final icon in icons) {
        final f = find.descendant(of: find.byType(FloatingPillNavBar), matching: find.byIcon(icon));
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          return;
        }
      }
    }

    testWidgets('Sadhana: "Your daily practice" above "Sadhana"; Insights: "How you\'re doing" above "Insights"; none on Profile or Journey', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(nav()));
      await tester.pump();
      await tester.pump();
      expect(find.text('Your daily practice'), findsOneWidget);
      final kicker = tester.getRect(find.text('Your daily practice'));
      final title = tester.getRect(find.text('Sadhana').first);
      expect(kicker.bottom, lessThanOrEqualTo(title.top + 1), reason: 'above the title');
      expect(kicker.left, title.left);
      await tapTab(tester, 0);
      expect(find.text("How you're doing"), findsOneWidget);
      expect(find.text('Your daily practice'), findsNothing);
      await tapTab(tester, 3);
      expect(find.text("How you're doing"), findsNothing);
      expect(find.text('Your daily practice'), findsNothing);
      await tapTab(tester, 1);
      expect(find.text("How you're doing"), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: the header fits with its kicker', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host(nav(), dark: dark));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tapTab(tester, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
