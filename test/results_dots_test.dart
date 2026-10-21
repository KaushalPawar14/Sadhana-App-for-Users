// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/pages/LeaderboardPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BottomNavBar.dart' show hostNavItems;
import 'package:folk_app/utils/LeaderboardData.dart';
import 'package:folk_app/utils/ResultsDots.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/utils/UnseenDot.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The dot trail of the published results: Insights tab -> Leaderboard tile -> "Results" (weekly) / "Monthly" tab then
// "Results" (monthly). A dot clears only when THAT period's Results are opened, tracked per student per period id.
const uid = 'u1';

Future<FakeFirebaseFirestore> world({String? week, String? month}) async {
  final db = FakeFirebaseFirestore();
  if (week != null) await db.doc('competition-results/weekly_meta').set({'last_week_finalized': week});
  if (month != null) await db.doc('competition-results/monthly_meta').set({'last_month_finalized': month});
  return db;
}

Future<bool> first(Stream<bool> s) async {
  final c = Completer<bool>();
  final sub = s.listen(c.complete);
  final v = await c.future.timeout(const Duration(seconds: 5));
  await sub.cancel();
  return v;
}

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

Widget host(Widget home) => MaterialApp(
      theme: FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  tearDown(() {
    ResultsDots.override = null;
    GenderDirectory.useForTests(null);
  });

  group('ResultsDots: what is new, per period and per period id', () {
    test('nothing published: no dot', () async {
      final d = ResultsDots(await world(), uid);
      expect(await first(d.unseen(BoardPeriod.weekly)), false);
      expect(await first(d.unseen(BoardPeriod.monthly)), false);
      expect(await first(d.anyUnseen), false);
    });

    test('weekly results published: the weekly period (and "any") is new, the monthly is not', () async {
      final d = ResultsDots(await world(week: '2026-W42'), uid);
      expect(await first(d.unseen(BoardPeriod.weekly)), true);
      expect(await first(d.unseen(BoardPeriod.monthly)), false);
      expect(await first(d.anyUnseen), true);
    });

    test('nothing clears the dot but opening that period\'s Results; then only that period id is seen', () async {
      final db = await world(week: '2026-W42');
      final d = ResultsDots(db, uid);
      expect(await first(d.unseen(BoardPeriod.weekly)), true);
      expect(await first(d.unseen(BoardPeriod.weekly)), true, reason: 'looking again clears nothing');
      await d.markSeen(BoardPeriod.weekly);
      expect(await first(d.unseen(BoardPeriod.weekly)), false);
      expect(await first(d.anyUnseen), false);
      final seen = (await db.doc('seenMarkers/$uid').get()).data()!;
      expect((seen['resultsSeen'] as Map).keys, ['weekly_2026-W42'], reason: 'tracked per period id');
      // next Monday: a NEW id is published -> new again
      await db.doc('competition-results/weekly_meta').set({'last_week_finalized': '2026-W43'});
      expect(await first(d.unseen(BoardPeriod.weekly)), true);
      // another student has their own marker
      expect(await first(ResultsDots(db, 'u2').unseen(BoardPeriod.weekly)), true);
    });

    test('both new (the 1st is a Monday): period by period', () async {
      final db = await world(week: '2026-W44', month: '2026-10');
      final d = ResultsDots(db, uid);
      expect(await first(d.unseen(BoardPeriod.weekly)), true);
      expect(await first(d.unseen(BoardPeriod.monthly)), true);
      await d.markSeen(BoardPeriod.weekly);
      expect(await first(d.unseen(BoardPeriod.weekly)), false);
      expect(await first(d.unseen(BoardPeriod.monthly)), true, reason: 'the monthly dot stays until the monthly results are opened');
      expect(await first(d.anyUnseen), true);
      await d.markSeen(BoardPeriod.monthly);
      expect(await first(d.unseen(BoardPeriod.monthly)), false);
      expect(await first(d.anyUnseen), false);
    });

    test('marking when nothing is published writes nothing; a failing source is no dot, never an error', () async {
      final db = await world();
      final d = ResultsDots(db, uid);
      await d.markSeen(BoardPeriod.weekly);
      expect((await db.doc('seenMarkers/$uid').get()).exists, isFalse);
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final bad = _FailingDots();
        expect(await first(bad.unseen(BoardPeriod.weekly)), false);
        expect(await first(bad.anyUnseen), false);
      }, (e, s) => errors.add(e));
      expect(errors, isEmpty);
    });
  });

  group('the Leaderboard page: dots on "Results" and on "Monthly"', () {
    Future<ResultsDots> open(WidgetTester tester, {String? week, String? month, double scale = 1.0}) async {
      phone(tester, scale);
      GenderDirectory.useForTests(() async => const GenderDirectory(mine: 'male', category: 'folk', femaleNames: {}, femaleUids: {}));
      final dots = ResultsDots(await world(week: week, month: month), uid);
      await tester.pumpWidget(host(LeaderboardPage(
        username: 'Arjun',
        docsStream: Stream.value({'Arjun': {'Name': 'Arjun', 'weekly.total_score': 10.0, 'monthly.total_score': 10.0}}),
        changesLoader: (_) async => {},
        resultsDots: dots,
      )));
      await tester.pumpAndSettle();
      return dots;
    }

    Finder resultsDot() => find.descendant(of: find.byKey(const ValueKey('results-dot')), matching: find.byType(UnseenDot));
    // the dot inside the Monthly segment: an UnseenDot that is not the Results one
    int dotsOnPage(WidgetTester tester) => find.byType(UnseenDot).evaluate().length;

    testWidgets('nothing new: no dot anywhere', (tester) async {
      await open(tester);
      expect(find.byType(UnseenDot), findsNothing);
    });

    testWidgets('the dots of the trail (Results button, Weekly and Monthly tabs) are the app dot: green with the thin dark border', (tester) async {
      await open(tester, week: '2026-W42', month: '2026-10');
      expect(find.byType(UnseenDot), findsNWidgets(3), reason: 'Results + the Weekly tab + the Monthly tab');
      for (final dot in find.byType(UnseenDot).evaluate()) {
        final d = tester.widget<Container>(find.descendant(of: find.byWidget(dot.widget), matching: find.byType(Container)).first).decoration! as BoxDecoration;
        expect(d.color, kUnseenDotFill);
        expect((d.border! as Border).top.color, kUnseenDotBorder);
        expect((d.border! as Border).top.width, 1.2);
      }
    });

    // is the "new" dot shown on the tab with this label?
    bool tabDot(WidgetTester tester, String label) => tester.widget<UnseenBadge>(find.ancestor(of: find.text(label).first, matching: find.byType(UnseenBadge)).first).show;

    testWidgets('weekly new, Weekly selected: a dot on the "Weekly" tab AND on "Results"; opening Results clears both', (tester) async {
      await open(tester, week: '2026-W42');
      expect(resultsDot(), findsOneWidget);
      expect(tabDot(tester, 'Weekly'), isTrue, reason: 'the Weekly tab shows it even though Weekly is already selected');
      expect(tabDot(tester, 'Monthly'), isFalse, reason: 'the monthly results are not new');
      expect(dotsOnPage(tester), 2, reason: 'the Weekly tab + Results');
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
      expect(resultsDot(), findsNothing);
      expect(tabDot(tester, 'Weekly'), isFalse, reason: 'opening the weekly Results cleared the Weekly tab dot too');
      expect(find.byType(UnseenDot), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Weekly tab dot clears ONLY when the weekly Results are opened (switching tabs or looking again changes nothing)', (tester) async {
      await open(tester, week: '2026-W42');
      expect(tabDot(tester, 'Weekly'), isTrue);
      await tester.tap(find.text('Monthly').first);
      await tester.pumpAndSettle();
      expect(tabDot(tester, 'Weekly'), isTrue, reason: 'still new: only opening the weekly Results clears it');
      expect(tabDot(tester, 'Monthly'), isFalse);
      expect(resultsDot(), findsNothing, reason: 'Monthly is selected and its results are not new');
      await tester.tap(find.text('Weekly').first);
      await tester.pumpAndSettle();
      expect(tabDot(tester, 'Weekly'), isTrue);
      expect(resultsDot(), findsOneWidget);
    });

    testWidgets('a NEW week after the weekly results were opened shows the Weekly dot again', (tester) async {
      final dots = await open(tester, week: '2026-W42');
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
      expect(tabDot(tester, 'Weekly'), isFalse);
      await dots.db.doc('competition-results/weekly_meta').set({'last_week_finalized': '2026-W43'});
      await tester.pumpAndSettle();
      expect(tabDot(tester, 'Weekly'), isTrue, reason: 'a new weekly result id is new again');
      expect(resultsDot(), findsOneWidget);
    });

    testWidgets('monthly new only: a dot on the "Monthly" tab; Weekly selected has none on Results; select Monthly -> a dot on Results; open it -> all gone', (tester) async {
      await open(tester, month: '2026-09');
      expect(resultsDot(), findsNothing, reason: 'the weekly results are not new');
      expect(tabDot(tester, 'Weekly'), isFalse, reason: 'monthly behaviour unchanged: no Weekly dot');
      expect(tabDot(tester, 'Monthly'), isTrue);
      expect(dotsOnPage(tester), 1, reason: 'the Monthly tab');
      await tester.tap(find.text('Monthly').first);
      await tester.pumpAndSettle();
      expect(resultsDot(), findsOneWidget, reason: 'Monthly selected: the dot moves to Results too');
      expect(dotsOnPage(tester), 2, reason: 'Results + the Monthly tab (it stays until the monthly results are opened)');
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(UnseenDot), findsNothing, reason: 'opening the monthly results cleared every dot of that period');
    });

    testWidgets('both new: weekly first, then monthly, each period on its own', (tester) async {
      await open(tester, week: '2026-W44', month: '2026-10');
      expect(resultsDot(), findsOneWidget, reason: 'Weekly selected: the weekly results are new');
      expect(tabDot(tester, 'Weekly'), isTrue);
      expect(tabDot(tester, 'Monthly'), isTrue, reason: 'both can show at once');
      expect(dotsOnPage(tester), 3, reason: 'Results + the Weekly tab + the Monthly tab');
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
      expect(resultsDot(), findsNothing, reason: 'the weekly dot on Results is gone');
      expect(tabDot(tester, 'Weekly'), isFalse, reason: 'and the Weekly tab dot with it');
      expect(dotsOnPage(tester), 1, reason: 'the monthly dot on the Monthly tab stays');
      await tester.tap(find.text('Monthly').first);
      await tester.pumpAndSettle();
      expect(resultsDot(), findsOneWidget, reason: 'now the monthly results');
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(UnseenDot), findsNothing);
    });

    for (final scale in scales) {
      testWidgets('text scale $scale: the dots fit, no overflow', (tester) async {
        await open(tester, week: '2026-W44', month: '2026-10', scale: scale);
        expect(tester.takeException(), isNull);
        for (final r in tester.widgetList<UnseenDot>(find.byType(UnseenDot)).map((d) => tester.getRect(find.byWidget(d)))) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          expect(r.top, greaterThanOrEqualTo(0));
        }
      });
    }
  });

  group('the Insights tab and the Leaderboard tile', () {
    testWidgets('the Leaderboard tile shows the dot (in its corner, clear of the arrow) while results are new, and loses it when they are not', (tester) async {
      phone(tester, 1.0);
      final c = StreamController<bool>.broadcast();
      addTearDown(c.close);
      await tester.pumpWidget(host(CompetitionPage(role: 'Stay at FOLK', username: 'Asha', loadReports: (_) async => {}, resultsUnseen: c.stream)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Best Performer'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: find.byKey(const ValueKey('leaderboard-dot')), matching: find.byType(UnseenDot)), findsNothing);
      c.add(true);
      await tester.pumpAndSettle();
      final dot = find.descendant(of: find.byKey(const ValueKey('leaderboard-dot')), matching: find.byType(UnseenDot));
      expect(dot, findsOneWidget);
      final tileRect = tester.getRect(find.byKey(const ValueKey('leaderboard-dot')));
      final dotRect = tester.getRect(dot);
      expect(dotRect.right, lessThanOrEqualTo(tileRect.right));
      expect(dotRect.top, greaterThanOrEqualTo(tileRect.top));
      // the arrow circle (32 dp, 16 dp in from the corner) is not covered
      expect(dotRect.left, greaterThan(tileRect.right - 16 - 32 + 20), reason: 'right of / above the arrow circle');
      c.add(false);
      await tester.pumpAndSettle();
      expect(dot, findsNothing);
    });

    testWidgets('the Insights tab of the nav pill has the dot, the others do not (Journey keeps its own)', (tester) async {
      phone(tester, 1.0);
      final insights = StreamController<bool>.broadcast();
      final journey = StreamController<bool>.broadcast();
      addTearDown(insights.close);
      addTearDown(journey.close);
      await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
          body: const SizedBox(),
          bottomNavigationBar: FloatingPillNavBar(
            items: hostNavItems(context, journeyUnseen: journey.stream, insightsUnseen: insights.stream),
            currentIndex: 2,
            onTap: (_) {},
          ),
        ),
      )));
      await tester.pump();
      expect(find.byType(UnseenDot), findsNothing);
      insights.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(UnseenDot), findsOneWidget);
      final nav = tester.getRect(find.byType(FloatingPillNavBar));
      final dot = tester.getRect(find.byType(UnseenDot));
      expect(dot.center.dx, lessThan(nav.left + nav.width / 4 + 12), reason: 'on the first tab (Insights)');
      journey.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(UnseenDot), findsNWidgets(2), reason: 'Journey has its own dot, independent');
      insights.add(false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(UnseenDot), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FailingDots extends ResultsDots {
  _FailingDots() : super(FakeFirebaseFirestore(), uid);

  @override
  Stream<String?> latestId(BoardPeriod period) => Stream<String?>.error(StateError('permission-denied'));

  @override
  Stream<Set<String>> seenKeys() => Stream<Set<String>>.error(StateError('permission-denied'));
}
