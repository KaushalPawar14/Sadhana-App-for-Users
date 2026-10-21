// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/LeaderboardPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/LeaderboardData.dart';
import 'package:folk_app/utils/ResultsDots.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/widgets/LeaderboardPodium.dart';
import 'package:folk_app/widgets/RiseIn.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The Leaderboard, cinematic and smooth: the podium bars RISE from the bottom slowly (3rd, 2nd, then 1st), each place's
// name / points fade in after its bar, then the rest of the list rises in row by row; the Scores cards and the Results
// pages get the same gentle rise. Calm, never replayed by coming back, static with "reduce animations", no layout jumps.
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

/// [reduce] = the "reduce animations" setting.
Widget host(Widget home, {bool reduce = false, bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduce), child: w!),
      home: home,
    );

RankedStudent student(String name, double points) => RankedStudent(name, points);

Map<String, Map<String, dynamic>> docs(int n) => {
      for (var i = 0; i < n; i++)
        'Student${i + 1}': {'Name': 'Student${i + 1}', 'weekly.total_score': 1000.0 - i * 40, 'monthly.total_score': 2000.0 - i * 60},
    };

double opacityOf(WidgetTester tester, Finder f) => tester.widget<FadeTransition>(f).opacity.value;

/// How far the bar is still down, as a fraction of its own height (1 = fully hidden below its slot, 0 = risen).
double hiddenFraction(WidgetTester tester, int place, double finalTop, double height) =>
    (tester.getTopLeft(find.byKey(ValueKey('podium-block-$place'))).dy - finalTop) / height;

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

  final top = [student('Arjun', 900), student('Bhima', 800), student('Chaitanya', 700)];

  // ------------------------------------------------------------------------------------------------ RiseIn
  group('RiseIn: one gentle, one-time rise', () {
    Widget box(Key k) => SizedBox(key: k, width: 100, height: 50);

    testWidgets('waits for its delay, then fades in and settles upward; done = exactly in place', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: Align(alignment: Alignment.topLeft, child: RiseIn(delay: const Duration(milliseconds: 300), duration: const Duration(milliseconds: 500), offset: 20, child: box(const ValueKey('b')))))));
      final start = tester.getTopLeft(find.byKey(const ValueKey('b'))).dy; // the final place + the 20 dp it rises from
      final fade = find.descendant(of: find.byType(RiseIn), matching: find.byType(FadeTransition)).first;
      expect(opacityOf(tester, fade), 0);
      await tester.pump(const Duration(milliseconds: 250));
      expect(opacityOf(tester, fade), 0, reason: 'before its delay: nothing yet');
      await tester.pump(const Duration(milliseconds: 250)); // 500: 200 ms into the rise
      final mid = opacityOf(tester, fade);
      expect(mid, inExclusiveRange(0.05, 0.99));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, fade), 1);
      expect(tester.getTopLeft(find.byKey(const ValueKey('b'))).dy, closeTo(start - 20, .01), reason: 'done: exactly in place');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the child keeps its place in the layout all the time (a transform moves it, nothing around it jumps)', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: Column(children: [RiseIn(child: box(const ValueKey('a'))), box(const ValueKey('below'))]))));
      final below0 = tester.getTopLeft(find.byKey(const ValueKey('below'))).dy;
      final size0 = tester.getSize(find.byType(RiseIn));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.byKey(const ValueKey('below'))).dy, below0);
      expect(tester.getSize(find.byType(RiseIn)), size0);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('below'))).dy, below0);
    });

    testWidgets('"reduce animations": simply there, from the first frame', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: RiseIn(delay: const Duration(seconds: 2), child: box(const ValueKey('a')))), reduce: true));
      final fade = find.descendant(of: find.byType(RiseIn), matching: find.byType(FadeTransition)).first;
      expect(opacityOf(tester, fade), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('never replayed: a rebuild keeps it risen; scrolled out of a list and back it is still risen', (tester) async {
      phone(tester, 1.0);
      Widget list(int tick) => host(Scaffold(
            body: ListView(children: [
              RiseIn(child: Text('first $tick', key: const ValueKey('first'))),
              for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i')),
            ]),
          ));
      await tester.pumpWidget(list(0));
      await tester.pumpAndSettle();
      final fade = find.descendant(of: find.byType(RiseIn), matching: find.byType(FadeTransition)).first;
      expect(opacityOf(tester, fade), 1);
      await tester.pumpWidget(list(1)); // a rebuild
      expect(opacityOf(tester, fade), 1, reason: 'a rebuild does not restart it');
      await tester.drag(find.byType(ListView), const Offset(0, -2500));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 5000));
      await tester.pump();
      expect(find.byKey(const ValueKey('first')), findsOneWidget);
      expect(opacityOf(tester, find.descendant(of: find.byType(RiseIn), matching: find.byType(FadeTransition)).first), 1, reason: 'back in view: not replayed');
    });
  });

  // ------------------------------------------------------------------------------------------------ the podium
  group('the podium: bars rise 3rd, 2nd, 1st; names and points fade in after their bar', () {
    Future<void> pumpPodium(WidgetTester tester, {bool reduce = false, double scale = 1.0, bool dark = false}) async {
      phone(tester, scale);
      await tester.pumpWidget(host(Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: LeaderboardPodium(top: top, myName: 'Arjun'))), reduce: reduce, dark: dark));
    }

    testWidgets('the timeline: the bars start 3rd, then 2nd, then 1st (slow, smooth); each info fades in once ITS bar is up; all done at the end', (tester) async {
      await pumpPodium(tester);
      // the finished positions (from the reduced-motion layout of the same widget)
      final heights = {1: 96.0, 2: 72.0, 3: 52.0};
      // t = 0: every bar is down, every info invisible
      final finalTops = <int, double>{};
      for (final p in [1, 2, 3]) {
        // the bar's slot is its Container's layout box: the box is as tall as the bar, the translate hides it
        finalTops[p] = tester.getTopLeft(find.byKey(ValueKey('podium-block-$p'))).dy - heights[p]!; // t=0 top = final + height
      }
      for (final p in [1, 2, 3]) {
        expect(hiddenFraction(tester, p, finalTops[p]!, heights[p]!), closeTo(1, .001), reason: 'bar $p starts fully down');
        expect(opacityOf(tester, find.byKey(ValueKey('podium-info-$p'))), 0, reason: 'info $p hidden');
      }
      await tester.pump(const Duration(milliseconds: 400));
      final f3 = hiddenFraction(tester, 3, finalTops[3]!, heights[3]!);
      final f2 = hiddenFraction(tester, 2, finalTops[2]!, heights[2]!);
      final f1 = hiddenFraction(tester, 1, finalTops[1]!, heights[1]!);
      expect(f3, lessThan(f2), reason: '3rd is further up than 2nd');
      expect(f2, lessThan(f1), reason: '2nd is further up than 1st');
      expect(f1, closeTo(1, .001), reason: '1st has not started (it starts 480 ms in)');
      expect(f3, greaterThan(0), reason: 'slow: the 3rd bar is not up after 400 ms');
      for (final p in [1, 2, 3]) {
        expect(opacityOf(tester, find.byKey(ValueKey('podium-info-$p'))), 0, reason: 'no info before its bar is up');
      }
      await tester.pump(const Duration(milliseconds: 500)); // 900: the 3rd bar (760) is up, the others are not
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-3'))), greaterThan(0), reason: '3rd info starts once its bar is up');
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-2'))), 0, reason: '2nd bar (up at 1000) is not up yet');
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 0);
      await tester.pump(const Duration(milliseconds: 400)); // 1300: 2nd info is in, 1st just started
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-2'))), greaterThan(0.5));
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), inExclusiveRange(0, 0.5), reason: 'the 1st place is last');
      await tester.pump(const Duration(milliseconds: 800)); // 2100: done
      for (final p in [1, 2, 3]) {
        expect(hiddenFraction(tester, p, finalTops[p]!, heights[p]!), closeTo(0, .001), reason: 'bar $p up');
        expect(opacityOf(tester, find.byKey(ValueKey('podium-info-$p'))), 1);
      }
      expect(tester.hasRunningAnimations, isFalse, reason: 'the whole thing is over: nothing keeps running');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bars rise without a layout jump: the podium is the same size throughout', (tester) async {
      await pumpPodium(tester);
      final size0 = tester.getSize(find.byType(LeaderboardPodium));
      final floor0 = tester.getBottomLeft(find.byKey(const ValueKey('podium-block-1'))).dy;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 170));
        expect(tester.getSize(find.byType(LeaderboardPodium)), size0, reason: 'frame $i');
      }
      expect(size0.height, greaterThan(0));
      // at the end the bars stand on the same floor the layout always had
      final end = tester.getBottomLeft(find.byKey(const ValueKey('podium-block-1'))).dy;
      expect(end, closeTo(floor0 - 0, 200), reason: 'sanity');
    });

    testWidgets('"reduce animations": the finished podium from the first frame, nothing running', (tester) async {
      await pumpPodium(tester, reduce: true);
      for (final p in [1, 2, 3]) {
        expect(opacityOf(tester, find.byKey(ValueKey('podium-info-$p'))), 1);
      }
      expect(tester.hasRunningAnimations, isFalse);
      // the bars are at their layout positions: 2nd left, 1st middle and tallest, 3rd right, one floor
      final b1 = tester.getRect(find.byKey(const ValueKey('podium-block-1')));
      final b2 = tester.getRect(find.byKey(const ValueKey('podium-block-2')));
      final b3 = tester.getRect(find.byKey(const ValueKey('podium-block-3')));
      expect(b1.height, 96);
      expect(b2.height, 72);
      expect(b3.height, 52);
      expect((b1.bottom - b2.bottom).abs(), lessThan(.5));
      expect((b1.bottom - b3.bottom).abs(), lessThan(.5));
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale: the animated podium ends exactly where the static one stands, no overflow', (tester) async {
          await pumpPodium(tester, scale: scale, dark: dark);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final animated = [for (final p in [1, 2, 3]) tester.getRect(find.byKey(ValueKey('podium-block-$p')))];
          final infos = [for (final p in [1, 2, 3]) tester.getRect(find.byKey(ValueKey('podium-info-$p')))];
          await pumpPodium(tester, reduce: true, scale: scale, dark: dark);
          await tester.pump();
          final still = [for (final p in [1, 2, 3]) tester.getRect(find.byKey(ValueKey('podium-block-$p')))];
          final stillInfos = [for (final p in [1, 2, 3]) tester.getRect(find.byKey(ValueKey('podium-info-$p')))];
          for (var i = 0; i < 3; i++) {
            expect(animated[i], still[i]);
            expect(infos[i], stillInfos[i]);
          }
        });
      }
    }
  });

  // ------------------------------------------------------------------------------------------------ the page
  group('the Leaderboard page', () {
    Future<void> open(WidgetTester tester, {int n = 25, bool reduce = false, double scale = 1.0, bool dark = false}) async {
      phone(tester, scale);
      GenderDirectory.useForTests(() async => const GenderDirectory(mine: 'male', category: 'folk', femaleNames: {}, femaleUids: {}));
      await tester.pumpWidget(host(
        LeaderboardPage(
          username: 'Student1',
          docsStream: Stream.value(docs(n)),
          changesLoader: (_) async => {},
          resultsDots: ResultsDots(FakeFirebaseFirestore(), 'u1'),
        ),
        reduce: reduce,
        dark: dark,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }

    Finder rowFade(String name) => find.descendant(of: find.ancestor(of: find.text(name), matching: find.byType(RiseIn)).first, matching: find.byType(FadeTransition)).first;

    testWidgets('on opening: the podium first, then the list rises in row by row (a quick stagger); everything ends in place', (tester) async {
      await open(tester);
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 0);
      expect(opacityOf(tester, rowFade('Student4')), 0, reason: 'the list waits for the podium');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(opacityOf(tester, rowFade('Student4')), 0, reason: 'still waiting (the rows start after the last bar is up)');
      await tester.pump(const Duration(milliseconds: 450)); // ~1470
      final r1 = opacityOf(tester, rowFade('Student4')); // first row: started at 1300
      final r2 = opacityOf(tester, rowFade('Student5')); // 45 ms later
      final r5 = opacityOf(tester, rowFade('Student8')); // 180 ms later
      expect(r1, greaterThan(r2), reason: 'row by row');
      expect(r2, greaterThanOrEqualTo(r5));
      expect(r1, inExclusiveRange(0.2, 1.0));
      await tester.pump(const Duration(seconds: 3));
      for (final n in ['Student4', 'Student5', 'Student8']) {
        expect(opacityOf(tester, rowFade(n)), 1, reason: n);
      }
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 1);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only the rows on screen rise: a row far down the list is simply there', (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      // Student20 was never given a rise: no RiseIn around it
      expect(find.ancestor(of: find.text('Student20'), matching: find.byType(RiseIn)), findsNothing);
    });

    testWidgets('switching Weekly / Monthly replays the rise; switching Leaderboard / Scores plays the Scores cards\' rise', (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 1);
      // Weekly -> Monthly
      await tester.tap(find.text('Monthly'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250)); // the old content is gone (200 ms switch)
      expect(find.byKey(const ValueKey('podium-info-1')), findsOneWidget);
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 0, reason: 'the new podium plays from the start');
      await tester.pump(const Duration(seconds: 4));
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 1);
      // Leaderboard -> Scores: the cards rise
      await tester.tap(find.text('Scores'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final cardFades = find.descendant(of: find.byType(RiseIn), matching: find.byType(FadeTransition));
      expect(cardFades, findsWidgets);
      final first = opacityOf(tester, cardFades.first);
      expect(first, lessThan(1), reason: 'the Scores cards are still rising');
      await tester.pump(const Duration(seconds: 4));
      for (final e in cardFades.evaluate()) {
        expect((e.widget as FadeTransition).opacity.value, 1);
      }
      // and back to Leaderboard: the podium plays again
      await tester.tap(find.text('Leaderboard').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 0);
    });

    testWidgets('coming back to the page (Results opened and closed) does not replay anything', (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byKey(const ValueKey('results-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 1);
      expect(opacityOf(tester, rowFade('Student4')), 1);
      expect(tester.getTopLeft(find.byKey(const ValueKey('podium-block-1'))).dy, greaterThan(0));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 1);
    });

    testWidgets('"reduce animations": the finished Leaderboard from the first frame, then the Scores tab too', (tester) async {
      await open(tester, reduce: true);
      expect(opacityOf(tester, find.byKey(const ValueKey('podium-info-1'))), 1);
      expect(opacityOf(tester, rowFade('Student4')), 1);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.tap(find.text('Scores'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      for (final e in find.descendant(of: find.byType(RiseIn), matching: find.byType(FadeTransition)).evaluate()) {
        expect((e.widget as FadeTransition).opacity.value, 1);
      }
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale: the whole choreography runs without an overflow or an exception', (tester) async {
          await open(tester, scale: scale, dark: dark);
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 80));
            expect(tester.takeException(), isNull, reason: 'frame $i');
          }
          await tester.tap(find.text('Scores'));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ------------------------------------------------------------------------------------------------ the Results pages
  test('the Results pages (weekly and monthly) use the same gentle rise: no bouncy pop-up is left', () {
    for (final f in ['lib/scores/TopWeekResults.dart', 'lib/scores/TopMonthResults.dart']) {
      final src = File(f).readAsStringSync();
      expect(src, contains("import '../widgets/RiseIn.dart';"), reason: f);
      expect(src, contains('RiseIn('), reason: f);
      expect(src.contains('easeOutBack'), isFalse, reason: '$f: the overshooting pop-up is gone');
      expect(src.contains('TweenAnimationBuilder'), isFalse, reason: '$f: cards rise once, never replayed by a rebuild');
      expect(src, contains("key: ValueKey('results-card-\$index')"), reason: f);
    }
  });

  test('the motion constants are calm: bars rise slowly, staggered 3rd / 2nd / 1st, info after, rows after the podium', () {
    expect(RiseMotion.bar.inMilliseconds, inInclusiveRange(600, 1000), reason: 'slow and smooth');
    expect(RiseMotion.barStagger.inMilliseconds, inInclusiveRange(150, 400));
    expect(RiseMotion.info.inMilliseconds, inInclusiveRange(250, 500));
    final lastBarUp = RiseMotion.barStagger.inMilliseconds * 2 + RiseMotion.bar.inMilliseconds;
    expect(RiseMotion.rowsStart.inMilliseconds, greaterThanOrEqualTo(lastBarUp), reason: 'the list rises in after the podium bars');
    expect(RiseMotion.rowStagger.inMilliseconds, lessThanOrEqualTo(60), reason: 'a subtle, quick row stagger');
    expect(RiseMotion.rowOffset, lessThan(RiseMotion.cardOffset));
    expect(LeaderboardPodium.total.inMilliseconds, lessThan(2000), reason: 'calm, not endless');
  });
}
