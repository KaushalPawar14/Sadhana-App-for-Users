// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/pages/LeaderboardPage.dart';
import 'package:folk_app/scores/TopMonthResults.dart';
import 'package:folk_app/scores/TopWeekResults.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/LeaderboardData.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/OwnScoreCard.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The Leaderboard page: the app bar with Results, the period switch and the tabs attached under it, the
// total-points ranking with its podium, and the Scores tab (own points + change, best five of each field).
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
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: home,
    );

GenderDirectory folk() => const GenderDirectory(mine: 'male', category: 'folk', femaleNames: {'Girl'}, femaleUids: {});
GenderDirectory hostel() => const GenderDirectory(mine: 'male', category: 'hostel_localite', femaleNames: {'Girl'}, femaleUids: {});

// Seven boys and one girl. The total (multipliers applied) is deliberately NOT the sum of the per-field points.
Map<String, Map<String, dynamic>> docs() => {
      'Arjun': {'weekly.total_score': 900.0, 'monthly.total_score': 3000.0, 'weekly.pts_chanting': 100.0, 'weekly.pts_reading': 50.0, 'weekly.pts_hearing': 75.0, 'weekly.pts_service': 50.0, 'monthly.pts_chanting': 400.0, 'weekly.days_count': 5},
      'Bhima': {'weekly.total_score': 700.0, 'monthly.total_score': 3500.0, 'weekly.pts_chanting': 300.0, 'weekly.pts_reading': 100.0, 'weekly.pts_hearing': 100.0, 'weekly.pts_service': 25.0, 'monthly.pts_chanting': 200.0},
      'Chaitanya': {'weekly.total_score': 500.0, 'monthly.total_score': 1000.0, 'weekly.pts_chanting': 200.0, 'weekly.pts_reading': 25.0, 'weekly.pts_hearing': 150.0, 'weekly.pts_service': 0.0},
      'Dhruva': {'weekly.total_score': 300.0, 'monthly.total_score': 900.0, 'weekly.pts_chanting': 50.0, 'weekly.pts_reading': 10.0, 'weekly.pts_hearing': 25.0},
      'Eknath': {'weekly.total_score': 200.0, 'monthly.total_score': 800.0, 'weekly.pts_chanting': 60.0, 'weekly.pts_reading': 20.0, 'weekly.pts_hearing': 50.0, 'weekly.pts_service': 50.0},
      'Gopal': {'weekly.total_score': 100.0, 'monthly.total_score': 700.0, 'weekly.pts_chanting': 70.0, 'weekly.pts_reading': 30.0, 'weekly.pts_hearing': 5.0},
      'Hari': {'weekly.total_score': 50.0, 'monthly.total_score': 600.0, 'weekly.pts_chanting': 80.0, 'weekly.pts_reading': 40.0, 'weekly.pts_hearing': 2.0},
      'Idle': {'weekly.total_score': 0.0, 'monthly.total_score': 0.0},
      'Girl': {'weekly.total_score': 9999.0, 'weekly.pts_chanting': 9999.0},
    };

Future<void> open(
  WidgetTester tester, {
  String me = 'Chaitanya',
  GenderDirectory? directory,
  Stream<Map<String, Map<String, dynamic>>>? stream,
  LeaderboardTab tab = LeaderboardTab.leaderboard,
  BoardPeriod period = BoardPeriod.weekly,
  double scale = 1.0,
  bool dark = false,
  Future<Map<String, double>> Function(BoardPeriod)? changes,
}) async {
  phone(tester, scale);
  GenderDirectory.useForTests(() async => directory ?? folk());
  await tester.pumpWidget(host(
    LeaderboardPage(
      username: me,
      docsStream: stream ?? Stream.value(docs()),
      changesLoader: changes ?? (_) async => {'weekly.total_score': 12.5, 'monthly.total_score': -4.0},
      initialTab: tab,
      initialPeriod: period,
    ),
    dark: dark,
  ));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label, {int nth = 0}) async {
  // the segmented labels (the title "Leaderboard" appears in the bar and in the tab row)
  final f = find.text(label);
  await tester.tap(f.at(nth));
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f.first).dy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  tearDown(() => GenderDirectory.useForTests(null));

  group('the data', () {
    test('the total ranking: multipliers applied (the total, not the field points), own gender only', () {
      final r = totalRanking(docs(), BoardPeriod.weekly, include: folk().sameByName);
      expect(r.map((e) => e.name).take(4), ['Arjun', 'Bhima', 'Chaitanya', 'Dhruva']);
      expect(r.any((e) => e.name == 'Girl'), isFalse);
      final m = totalRanking(docs(), BoardPeriod.monthly, include: folk().sameByName);
      expect(m.first.name, 'Bhima', reason: 'the month has its own order');
    });

    test('the best of a field: per-item points, NO multipliers, at most five, only those with points', () {
      final chanting = bestOf(docs(), BoardPeriod.weekly, BestField.chanting, include: folk().sameByName);
      expect(chanting.map((e) => e.name), ['Bhima', 'Chaitanya', 'Arjun', 'Hari', 'Gopal'], reason: 'five, by chanting points, not by total');
      expect(chanting.first.points, 300);
      final service = bestOf(docs(), BoardPeriod.weekly, BestField.service, include: folk().sameByName);
      expect(service.map((e) => e.name), ['Arjun', 'Eknath', 'Bhima'], reason: 'a zero is not listed; ties by name');
      expect(bestOf(docs(), BoardPeriod.monthly, BestField.reading, include: folk().sameByName), isEmpty, reason: 'nobody has monthly reading points');
    });

    test('a document held as nested maps reads the same as the flat dotted one', () {
      expect(figure({'weekly.total_score': 5}, BoardPeriod.weekly, 'total_score'), 5);
      expect(figure({'weekly': {'total_score': 7}}, BoardPeriod.weekly, 'total_score'), 7);
      expect(figure({}, BoardPeriod.monthly, 'pts_chanting'), 0);
    });

    test('my name matches trimmed and case-insensitively', () {
      expect(isMe(' Asha ', 'asha'), isTrue);
      expect(isMe('Asha', ''), isFalse);
      expect(isMe('Asha', null), isFalse);
    });
  });

  group('the bar: title, Results, and the two rows attached under it', () {
    testWidgets('title "Leaderboard", a Results button, Weekly | Monthly, then Leaderboard | Scores', (tester) async {
      await open(tester);
      expect(find.text('Leaderboard'), findsNWidgets(2), reason: 'the title and the tab');
      expect(find.byKey(const ValueKey('results-button')), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Scores'), findsOneWidget);
      final title = _y(tester, find.descendant(of: find.byType(FolkScaffold), matching: find.text('Leaderboard')));
      final results = tester.getRect(find.byKey(const ValueKey('results-button')));
      expect(results.right, greaterThan(300), reason: 'top right');
      expect((results.center.dy - tester.getCenter(find.text('Leaderboard').first).dy).abs(), lessThan(14), reason: 'in the title row');
      expect(title, lessThan(_y(tester, find.text('Weekly'))));
      expect(_y(tester, find.text('Weekly')), lessThan(_y(tester, find.text('Scores'))), reason: 'row 1 the period, row 2 the tabs');
      // attached: the period row starts right under the title row, the tabs right under the period row
      final weekly = tester.getRect(find.ancestor(of: find.text('Weekly'), matching: find.byType(Stack)).first);
      final scores = tester.getRect(find.ancestor(of: find.text('Scores'), matching: find.byType(Stack)).first);
      expect(scores.top - weekly.bottom, lessThan(16), reason: 'the rows sit together');
    });

    testWidgets('the Results button opens the finished results of the selected period', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(WeeklyLeaderboardPage), findsOneWidget, reason: 'Weekly selected');
      expect(find.byType(MonthlyLeaderboardPage), findsNothing);
      Navigator.of(tester.element(find.byType(WeeklyLeaderboardPage))).pop();
      await tester.pumpAndSettle();
      await choose(tester, 'Monthly');
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MonthlyLeaderboardPage), findsOneWidget, reason: 'Monthly selected');
    });
  });

  group('Leaderboard tab', () {
    testWidgets('the podium: 2nd left, 1st in the middle and tallest, 3rd right; then the rest as a list that goes on from 4', (tester) async {
      await open(tester);
      final b1 = tester.getRect(find.byKey(const ValueKey('podium-block-1')));
      final b2 = tester.getRect(find.byKey(const ValueKey('podium-block-2')));
      final b3 = tester.getRect(find.byKey(const ValueKey('podium-block-3')));
      expect(b2.left, lessThan(b1.left));
      expect(b1.left, lessThan(b3.left));
      expect(b1.height, greaterThan(b2.height));
      expect(b2.height, greaterThan(b3.height));
      expect((b1.bottom - b2.bottom).abs(), lessThan(1), reason: 'they stand on one floor');
      expect(find.text('Arjun'), findsOneWidget);
      expect(find.text('900 pts'), findsOneWidget);
      // the list: ranks 4, 5, 6, ... (Dhruva, Eknath, Gopal, Hari, Idle); the girl is not here
      expect(find.text('Dhruva'), findsOneWidget);
      expect(find.text('Girl'), findsNothing);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('my own row is highlighted: on the podium (outlined) or in the list', (tester) async {
      await open(tester, me: 'Gopal');
      expect(find.byKey(const ValueKey('my-row')), findsOneWidget, reason: 'one highlighted list row');
      expect(find.text('Your place: #6 of 8'), findsOneWidget);
      await open(tester, me: 'Arjun');
      expect(find.byKey(const ValueKey('my-row')), findsNothing, reason: 'on the podium instead');
      final block = tester.widget<Container>(find.byKey(const ValueKey('podium-block-1')));
      expect((block.decoration! as BoxDecoration).border, isNotNull, reason: 'the podium block is outlined');
      expect(find.text('Your place: #1 of 8'), findsOneWidget);
    });

    testWidgets('Monthly is its own ranking', (tester) async {
      await open(tester, period: BoardPeriod.monthly);
      expect(find.text('3500 pts'), findsOneWidget);
      expect(find.text('3000 pts'), findsOneWidget);
    });

    testWidgets('nobody has points yet: a friendly empty state', (tester) async {
      await open(tester, stream: Stream.value({'Idle': {'weekly.total_score': 0.0}}));
      expect(find.byKey(const ValueKey('leaderboard-empty')), findsOneWidget);
      expect(find.text('No points this week yet'), findsOneWidget);
    });

    testWidgets('while loading: ghost rows; no spinner', (tester) async {
      final c = StreamController<Map<String, Map<String, dynamic>>>();
      addTearDown(c.close);
      phone(tester);
      GenderDirectory.useForTests(() async => folk());
      await tester.pumpWidget(host(LeaderboardPage(username: 'x', docsStream: c.stream, changesLoader: (_) async => {})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LeaderboardGhost), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      c.add(docs());
      await tester.pumpAndSettle();
      expect(find.byType(LeaderboardGhost), findsNothing);
    });
  });

  group('Scores tab', () {
    testWidgets('my points and the change against the previous period, on top', (tester) async {
      await open(tester, me: 'Arjun', tab: LeaderboardTab.scores);
      expect(find.byKey(const ValueKey('own-score-card')), findsOneWidget);
      expect(find.text('Your points this week'), findsOneWidget);
      expect(find.text('900.00'), findsOneWidget);
      expect(find.text('+12.5%'), findsOneWidget, reason: 'the change vs last week');
      expect(find.text('vs last week'), findsOneWidget);
      await choose(tester, 'Monthly');
      expect(find.text('Your points this month'), findsOneWidget);
      expect(find.text('3000.00'), findsOneWidget);
      expect(find.text('-4.0%'), findsOneWidget);
      expect(find.text('vs last month'), findsOneWidget);
    });

    testWidgets('best performers: top five per field with points, no multipliers; the card of each field', (tester) async {
      await open(tester, me: 'Arjun', tab: LeaderboardTab.scores);
      final list = find.byType(Scrollable).first;
      Finder inCard(String f, String text) => find.descendant(of: find.byKey(ValueKey('best-$f')), matching: find.text(text));
      Future<void> see(String f) => tester.scrollUntilVisible(find.byKey(ValueKey('best-$f')), 250, scrollable: list);

      await see('chanting');
      // Bhima 300, Chaitanya 200, Arjun 100, Hari 80, Gopal 70 (Eknath 60 is the sixth: not shown)
      expect(inCard('chanting', '300 pts'), findsOneWidget);
      expect(inCard('chanting', 'Gopal'), findsOneWidget);
      expect(inCard('chanting', 'Eknath'), findsNothing, reason: 'only five');
      // my own name is bold, in whichever card I am
      expect(tester.widget<Text>(inCard('chanting', 'Arjun')).style?.fontWeight, FontWeight.w800);

      await see('reading');
      expect(inCard('reading', '100 pts'), findsOneWidget);
      await see('hearing');
      // hearing is its own field (class + extra lecture)
      expect(inCard('hearing', '150 pts'), findsOneWidget);
      expect(find.text('Best Hearing'), findsOneWidget);
      await see('service');
      expect(inCard('service', '50 pts'), findsNWidgets(2), reason: 'Arjun and Eknath');
      expect(inCard('service', 'Chaitanya'), findsNothing, reason: 'a zero is not listed');
    });

    testWidgets('a field nobody has points in yet says so', (tester) async {
      await open(tester, me: 'Arjun', tab: LeaderboardTab.scores, period: BoardPeriod.monthly);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('best-reading')), 250, scrollable: list);
      expect(find.byKey(const ValueKey('best-reading-empty')), findsOneWidget);
    });

    testWidgets('Hostel & Localite: no Best Service, no Service or Lecture chips', (tester) async {
      await open(tester, me: 'Arjun', directory: hostel(), tab: LeaderboardTab.scores);
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('best-service')), findsNothing);
      expect(find.byKey(const ValueKey('best-hearing')), findsOneWidget);
      await tester.drag(list, const Offset(0, 4000));
      await tester.pumpAndSettle();
      expect(find.textContaining('Service'), findsNothing);
      expect(find.textContaining('Lecture'), findsNothing);
    });

    testWidgets('a student with no document yet: zeros, never a crash', (tester) async {
      await open(tester, me: 'Nobody', tab: LeaderboardTab.scores);
      expect(find.text('0.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('switching is smooth', () {
    testWidgets('period and tab switches do not read again and never show the ghost', (tester) async {
      var listens = 0;
      final stream = Stream<Map<String, Map<String, dynamic>>>.multi((c) {
        listens++;
        c.add(docs());
      }, isBroadcast: true);
      await open(tester, stream: stream);
      expect(listens, 1);
      var ghosts = 0;
      Future<void> watch(Future<void> Function() act) async {
        await act();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          ghosts += find.byType(LeaderboardGhost).evaluate().length;
        }
      }

      await watch(() => tester.tap(find.text('Monthly')));
      await watch(() => tester.tap(find.text('Scores')));
      await watch(() => tester.tap(find.text('Weekly')));
      await watch(() => tester.tap(find.text('Leaderboard').last));
      expect(ghosts, 0, reason: 'no reload blink');
      expect(listens, 1, reason: 'one live read feeds both tabs and both periods');
    });

    testWidgets('Monthly + Scores together: the month\'s scores', (tester) async {
      await open(tester, me: 'Arjun');
      await choose(tester, 'Monthly');
      await choose(tester, 'Scores');
      expect(find.text('Your points this month'), findsOneWidget);
      expect(find.text('Best performers this month'), findsOneWidget);
    });
  });

  group('every size, light and dark', () {
    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale: both tabs, both periods draw without overflow (a long name, results button)', (tester) async {
          final d = docs();
          d['A Very Long Name Prabhu Das Of Surat City Here'] = {'weekly.total_score': 950.0, 'monthly.total_score': 3900.0, 'weekly.pts_chanting': 400.0, 'weekly.pts_hearing': 90.0};
          await open(tester, me: 'Gopal', stream: Stream.value(d), scale: scale, dark: dark);
          for (final period in ['Weekly', 'Monthly']) {
            await choose(tester, period);
            for (final tab in [0, 1]) {
              if (tab == 1) {
                await choose(tester, 'Scores');
              } else {
                await choose(tester, 'Leaderboard', nth: 1);
              }
              expect(tester.takeException(), isNull, reason: '$period tab $tab');
              final results = tester.getRect(find.byKey(const ValueKey('results-button')));
              expect(results.right, lessThanOrEqualTo(360));
              expect(results.height, greaterThanOrEqualTo(48));
              final title = find.descendant(of: find.byType(FolkScaffold), matching: find.text('Leaderboard')).first;
              expect(tester.getRect(title).right, lessThanOrEqualTo(results.left + 1), reason: 'the title does not run under Results');
            }
          }
          if (scale == 1.0 && !dark) {
            // sanity that the title is complete at the normal size
            expect(find.text('Leaderboard'), findsNWidgets(2));
          }
        });
      }
    }
  });

  group('Insights: the old tiles are gone', () {
    testWidgets('only Leaderboard and Best Performer are left (both wide); no Weekly / Monthly Performance', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(CompetitionPage(role: 'Stay at FOLK', username: 'Asha', loadReports: (_) async => {})));
      await tester.pumpAndSettle();
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('Best Performer'), findsOneWidget);
      expect(find.text('Weekly Performance'), findsNothing);
      expect(find.text('Monthly Performance'), findsNothing);
      final l = tester.getRect(find.ancestor(of: find.text('Leaderboard'), matching: find.byType(ConstrainedBox)).first);
      final b = tester.getRect(find.ancestor(of: find.text('Best Performer'), matching: find.byType(ConstrainedBox)).first);
      expect(l.width, closeTo(b.width, 1), reason: 'both wide');
      expect(l.width, greaterThan(300));
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      expect(find.byType(LeaderboardPage), findsOneWidget);
    });
  });

  test('the old category boards, Scorecard page and results pages are gone from the source', () {
    for (final f in [
      'lib/pages/Scorecard.dart',
      'lib/scores/Chanting.dart',
      'lib/scores/BookReading.dart',
      'lib/scores/BhagavatamClass.dart',
      'lib/scores/DailyServices.dart',
      'lib/scores/CategoryBoard.dart',
      'lib/scores/WeeklyResults.dart',
      'lib/scores/MonthlyResults.dart',
      'lib/models/Scorecard.dart',
      'lib/services/ScorecardUpdate.dart',
    ]) {
      expect(File(f).existsSync(), isFalse, reason: '$f should be deleted');
    }
  });
}
