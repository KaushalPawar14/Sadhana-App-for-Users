import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/CountUpText.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/MotionHelpers.dart';
import 'package:folk_app/widgets/PlayPauseIcon.dart';
import 'package:folk_app/widgets/SadhanaDayCell.dart';
import 'package:folk_app/widgets/StatTile.dart';
import 'package:folk_app/widgets/TypingDots.dart';
import 'package:table_calendar/table_calendar.dart';

Widget _app(Widget child, {bool reduce = false}) {
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(360, 800),
      disableAnimations: reduce,
    ),
    child: MaterialApp(
      theme: FolkTheme.light,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

int _tickers(WidgetTester tester) => tester.binding.transientCallbackCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget ghostScene({required bool loading, bool tickerMode = true}) {
    return TickerMode(
      enabled: tickerMode,
      child: GhostScope(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GhostCrossFade(
              loading: loading,
              ghost: const GhostPlaceholder(
                  width: 200, height: 50, showBars: false),
              child: const SizedBox(width: 200, height: 50, child: Text('real')),
            ),
            const SizedBox(height: 10),
            const GhostPlaceholder(width: 200, height: 20, showBars: false),
          ],
        ),
      ),
    );
  }

  group('ghosts: pulse in sync, cross-fade without a jump, no ticker off-screen', () {
    testWidgets('two ghosts under one scope pulse in sync', (tester) async {
      await tester.pumpWidget(_app(ghostScene(loading: true)));
      await tester.pump(const Duration(milliseconds: 700));
      final alphas = <double>[];
      for (final ghost in find.byType(GhostPlaceholder).evaluate()) {
        final box = find.descendant(
            of: find.byWidget(ghost.widget), matching: find.byType(Container));
        final deco = tester.widget<Container>(box.first).decoration as BoxDecoration;
        alphas.add(deco.color!.a);
      }
      expect(alphas.length, 2);
      expect(alphas[0], closeTo(alphas[1], 1e-6),
          reason: 'same base tint and the same animation value');
    });

    testWidgets('the scope animates only while a ghost is on screen', (tester) async {
      await tester.pumpWidget(_app(ghostScene(loading: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_tickers(tester), greaterThan(0), reason: 'ghosts pulse');

      // Content arrived: the first ghost fades out, but the second ghost (a
      // separate, still-showing one) keeps the scope alive. Remove both.
      await tester.pumpWidget(_app(
        GhostScope(
          child: GhostCrossFade(
            loading: false,
            ghost: const GhostPlaceholder(width: 200, height: 50, showBars: false),
            child: const SizedBox(width: 200, height: 50, child: Text('real')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(GhostPlaceholder), findsNothing);
      expect(_tickers(tester), 0, reason: 'no ghost, no ticker');
    });

    testWidgets('reduce animations: ghosts stay still, no ticker', (tester) async {
      await tester.pumpWidget(_app(ghostScene(loading: true), reduce: true));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(GhostPlaceholder), findsWidgets);
      expect(_tickers(tester), 0);
    });

    testWidgets('app in the background: the pulse stops; foreground: it resumes', (tester) async {
      await tester.pumpWidget(_app(ghostScene(loading: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_tickers(tester), greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(_tickers(tester), 0, reason: 'nothing animates in the background');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_tickers(tester), greaterThan(0));
    });

    testWidgets('a screen that is not on top (tickers muted) runs nothing', (tester) async {
      await tester.pumpWidget(_app(ghostScene(loading: true, tickerMode: false)));
      await tester.pump(const Duration(seconds: 1));
      expect(_tickers(tester), 0);
    });

    testWidgets('cross-fade 250 ms, ghost and content the same size: nothing moves', (tester) async {
      expect(FolkMotion.ghostCrossFade.inMilliseconds, inInclusiveRange(200, 300));
      await tester.pumpWidget(_app(ghostScene(loading: true)));
      final fadeFinder = find.byType(GhostCrossFade);
      final before = tester.getRect(fadeFinder);

      await tester.pumpWidget(_app(ghostScene(loading: false)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('real'), findsOneWidget, reason: 'content fading in');
      expect(find.byType(GhostPlaceholder), findsNWidgets(2), reason: 'ghost still fading out');
      expect(tester.getRect(fadeFinder), before, reason: 'no layout jump mid-fade');

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(GhostPlaceholder), findsOneWidget);
      expect(tester.getRect(fadeFinder), before);
    });

    testWidgets('reduce animations: the swap is instant', (tester) async {
      await tester.pumpWidget(_app(ghostScene(loading: true), reduce: true));
      await tester.pumpWidget(_app(ghostScene(loading: false), reduce: true));
      await tester.pump();
      expect(find.text('real'), findsOneWidget);
      expect(find.byType(GhostPlaceholder), findsOneWidget);
    });
  });

  group('numbers count up on FIRST appearance only', () {
    Widget tile(int value, {bool ghost = false, bool reduce = false}) => _app(
          SizedBox(
            width: 160,
            child: StatTile(
              value: '$value',
              label: 'Lifetime',
              style: FolkGradientStyle.coral,
              countUp: value,
              valueGhost: ghost,
            ),
          ),
          reduce: reduce,
        );

    String shown(WidgetTester tester) => tester
        .widget<Text>(find.descendant(
            of: find.byType(CountUpText), matching: find.byType(Text)))
        .data!;

    testWidgets('first appearance: 0 -> value over ~600 ms, then no ticker', (tester) async {
      await tester.pumpWidget(tile(40));
      expect(shown(tester), '0', reason: 'starts from 0 on the first frame');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 250));
      final mid = int.parse(shown(tester));
      expect(mid, inInclusiveRange(1, 39), reason: 'counting up');
      await tester.pump(const Duration(milliseconds: 600));
      expect(shown(tester), '40');
      await tester.pumpAndSettle();
      expect(_tickers(tester), 0);
    });

    testWidgets('after that, a changed value shows IMMEDIATELY (a round was just banked)', (tester) async {
      await tester.pumpWidget(tile(40));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      for (final v in [41, 42, 100, 7]) {
        await tester.pumpWidget(tile(v));
        await tester.pump(); // one frame, no time passes
        expect(shown(tester), '$v', reason: 'the true value at once');
      }
      expect(_tickers(tester), 0);
    });

    testWidgets('a value that changes DURING the first count-up jumps to the true value', (tester) async {
      await tester.pumpWidget(tile(40));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(tile(55));
      await tester.pump();
      expect(shown(tester), '55');
    });

    testWidgets('while loading the number is a ghost; the count-up starts when it is ready', (tester) async {
      await tester.pumpWidget(tile(25, ghost: true));
      expect(find.byType(CountUpText), findsNothing);
      expect(find.byType(GhostPlaceholder), findsOneWidget);

      await tester.pumpWidget(tile(25));
      await tester.pump();
      expect(find.byType(CountUpText), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(int.parse(shown(tester)), inInclusiveRange(0, 24), reason: 'counting up from the ghost');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(shown(tester), '25');
      expect(_tickers(tester), 0);
    });

    testWidgets('reduce animations: the value is shown at once', (tester) async {
      await tester.pumpWidget(tile(40, reduce: true));
      expect(shown(tester), '40');
      expect(_tickers(tester), 0);
    });
  });

  group('typing dots', () {
    Widget dots() => const Center(child: TypingDots(color: Colors.grey));

    testWidgets('three dots animate in the foreground', (tester) async {
      await tester.pumpWidget(_app(dots()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_tickers(tester), greaterThan(0));
      expect(find.descendant(of: find.byType(TypingDots), matching: find.byType(Container)), findsNWidgets(3));
    });

    testWidgets('stopped in the background, with reduce motion, and when muted', (tester) async {
      await tester.pumpWidget(_app(dots()));
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(_tickers(tester), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_tickers(tester), greaterThan(0));

      await tester.pumpWidget(_app(dots(), reduce: true));
      await tester.pump(const Duration(seconds: 1));
      expect(_tickers(tester), 0);
      expect(find.descendant(of: find.byType(TypingDots), matching: find.byType(Container)), findsNWidgets(3), reason: 'still drawn, just still');

      await tester.pumpWidget(_app(TickerMode(enabled: false, child: dots())));
      await tester.pump(const Duration(seconds: 1));
      expect(_tickers(tester), 0);

      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      expect(_tickers(tester), 0, reason: 'gone when removed');
    });
  });

  group('play / pause morph', () {
    Widget icon(bool playing) =>
        _app(PlayPauseIcon(playing: playing, color: Colors.black));

    testWidgets('both glyphs overlap mid-morph, only the new one remains', (tester) async {
      await tester.pumpWidget(icon(false));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.pumpWidget(icon(true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(_tickers(tester), 0);
    });

    testWidgets('reduce animations: it just swaps', (tester) async {
      await tester.pumpWidget(_app(PlayPauseIcon(playing: false, color: Colors.black), reduce: true));
      await tester.pumpWidget(_app(PlayPauseIcon(playing: true, color: Colors.black), reduce: true));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });
  });

  group('mini-player slide-up and smooth progress', () {
    Widget slot(bool shown, {bool reduce = false}) => _app(
          SizedBox(
            width: 200,
            height: 100,
            child: Stack(children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SlideUpSwitcher(
                  child: shown ? const SizedBox(height: 64, child: Text('player')) : null,
                ),
              ),
            ]),
          ),
          reduce: reduce,
        );

    testWidgets('slides up when shown and back down when removed', (tester) async {
      await tester.pumpWidget(slot(false));
      expect(find.text('player'), findsNothing);
      await tester.pumpWidget(slot(true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getTopLeft(find.text('player')).dy;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(find.text('player')).dy;
      expect(mid, greaterThan(end), reason: 'still below its final place mid-slide');

      await tester.pumpWidget(slot(false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('player'), findsOneWidget, reason: 'sliding out, not cut off');
      await tester.pumpAndSettle();
      expect(find.text('player'), findsNothing);
      expect(_tickers(tester), 0);
    });

    testWidgets('reduce animations: it just appears and disappears', (tester) async {
      await tester.pumpWidget(slot(false, reduce: true));
      await tester.pumpWidget(slot(true, reduce: true));
      await tester.pump();
      expect(find.text('player'), findsOneWidget);
      await tester.pumpWidget(slot(false, reduce: true));
      await tester.pump();
      expect(find.text('player'), findsNothing);
    });

    Widget eased(double value, {bool following = false, bool reduce = false}) => _app(
          EasedProgress(
            value: value,
            following: following,
            builder: (context, shown) => Text('${shown.round()}'),
          ),
          reduce: reduce,
        );

    testWidgets('progress eases between readings; follows the finger and reduce-motion exactly', (tester) async {
      await tester.pumpWidget(eased(0));
      await tester.pumpWidget(eased(100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final mid = int.parse(tester.widget<Text>(find.byType(Text)).data!);
      expect(mid, inInclusiveRange(30, 70), reason: 'easing toward 100');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('100'), findsOneWidget);

      await tester.pumpWidget(eased(10, following: true));
      await tester.pump();
      expect(find.text('10'), findsOneWidget, reason: 'while dragging: exactly the reading');

      await tester.pumpWidget(eased(0, reduce: true));
      await tester.pumpWidget(eased(80, reduce: true));
      await tester.pump();
      expect(find.text('80'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_tickers(tester), 0);
    });
  });

  group('new chat messages rise once; earlier ones never animate', () {
    testWidgets('only rows added after the first draw rise', (tester) async {
      final rise = NewItemRise();
      var count = 3;
      late StateSetter setOuter;
      await tester.pumpWidget(_app(
        SizedBox(
          width: 300,
          height: 400,
          child: StatefulBuilder(builder: (context, setState) {
            setOuter = setState;
            rise.markDrawn(count);
            return ListView.builder(
              itemCount: count,
              itemBuilder: (context, i) => rise.wrap(i, SizedBox(height: 40, child: Text('row $i'))),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(EntryAnimation), findsNothing, reason: 'the first draw does not animate');

      setOuter(() => count = 4);
      await tester.pump();
      expect(find.byType(EntryAnimation), findsOneWidget, reason: 'only the new row');
      expect(find.text('row 3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.widget<FadeTransition>(find
          .ancestor(of: find.text('row 3'), matching: find.byType(FadeTransition))
          .first)
          .opacity.value;
      expect(mid, inExclusiveRange(0, 1), reason: 'fading in');
      await tester.pumpAndSettle();
      expect(_tickers(tester), 0);

      // A later redraw does not replay it.
      setOuter(() {});
      await tester.pump();
      expect(tester.widget<FadeTransition>(find
          .ancestor(of: find.text('row 3'), matching: find.byType(FadeTransition))
          .first)
          .opacity.value, 1);
    });
  });

  group('Sadhana day-submitted fill', () {
    Widget cell(SadhanaDayState state, {bool reduce = false}) => _app(
          SizedBox(
            width: 44,
            height: 44,
            child: SadhanaDayCell(day: 9, state: state),
          ),
          reduce: reduce,
        );

    double scale(WidgetTester tester) => tester
        .widget<ScaleTransition>(find
            .descendant(
                of: find.byType(SadhanaDayCell),
                matching: find.byType(ScaleTransition))
            .first)
        .scale
        .value;

    testWidgets('a day that BECOMES submitted scales in over ~250 ms', (tester) async {
      await tester.pumpWidget(cell(SadhanaDayState.missed));
      expect(scale(tester), 1);
      await tester.pumpWidget(cell(SadhanaDayState.submitted));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(tester), lessThan(1));
      expect(scale(tester), greaterThanOrEqualTo(.8));
      await tester.pumpAndSettle();
      expect(scale(tester), 1);
      expect(_tickers(tester), 0);
    });

    testWidgets('today becoming submitted also fills in', (tester) async {
      await tester.pumpWidget(cell(SadhanaDayState.today));
      await tester.pumpWidget(cell(SadhanaDayState.todaySubmitted));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(tester), lessThan(1));
    });

    testWidgets('an already-submitted day drawn for the first time does not animate', (tester) async {
      await tester.pumpWidget(cell(SadhanaDayState.submitted));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(tester), 1);
      expect(_tickers(tester), 0);
    });

    testWidgets('submitted -> today-submitted and other changes do not replay it; reduce motion never plays it', (tester) async {
      await tester.pumpWidget(cell(SadhanaDayState.submitted));
      await tester.pumpWidget(cell(SadhanaDayState.todaySubmitted));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(tester), 1);

      await tester.pumpWidget(cell(SadhanaDayState.missed, reduce: true));
      await tester.pumpWidget(cell(SadhanaDayState.submitted, reduce: true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(tester), 1);
      expect(_tickers(tester), 0);
    });
  });

  group('Sadhana calendar ghost is exactly the real calendar card\'s height', () {
    for (final month in [
      DateTime(2026, 2, 1), // 4 weeks (starts on a Sunday)
      DateTime(2026, 10, 1), // 5 weeks
      DateTime(2026, 8, 1), // 6 weeks (starts on a Saturday)
      DateTime(2026, 11, 1),
      DateTime(2027, 5, 1), // 6 weeks
    ]) {
      testWidgets('${month.year}-${month.month}: ${SadhanaCalendarGhost.weeksIn(month)} weeks', (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const rowHeight = 360 * 0.12;
        const chevronPadding = EdgeInsets.all(2);
        final key = GlobalKey();
        final last = DateTime(month.year, month.month + 1, 0);

        // The same card, calendar and header settings as pages/Calendar.dart.
        await tester.pumpWidget(MaterialApp(
          theme: FolkTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                key: key,
                padding: const EdgeInsets.all(FolkSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TableCalendar(
                      focusedDay: month,
                      firstDay: DateTime(month.year, month.month - 1, 1),
                      lastDay: last,
                      rowHeight: rowHeight,
                      daysOfWeekHeight: 30,
                      calendarStyle: const CalendarStyle(outsideDaysVisible: false),
                      headerStyle: HeaderStyle(
                        titleCentered: true,
                        formatButtonVisible: false,
                        headerPadding: const EdgeInsets.only(bottom: FolkSpace.md),
                        leftChevronIcon: const SizedBox(width: 44, height: 44),
                        rightChevronIcon: const SizedBox(width: 44, height: 44),
                        leftChevronPadding: chevronPadding,
                        rightChevronPadding: chevronPadding,
                        leftChevronMargin: EdgeInsets.zero,
                        rightChevronMargin: EdgeInsets.zero,
                      ),
                      calendarBuilders: CalendarBuilders(
                        prioritizedBuilder: (context, date, _) =>
                            SadhanaDayCell(day: date.day, state: SadhanaDayState.future),
                      ),
                    ),
                    const SizedBox(height: SadhanaCalendarGhost.legendGap),
                    const SizedBox(
                        height: SadhanaCalendarGhost.legendHeight,
                        child: SadhanaLegend()),
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final real = tester.getSize(find.byKey(key)).height;
        final ghost = SadhanaCalendarGhost.cardHeight(month, rowHeight);
        expect(real, closeTo(ghost, .5),
            reason: 'real card $real vs ghost $ghost: no layout jump');
      });
    }
  });

  group('navigation pill morph (verified)', () {
    Widget nav(int index, {bool reduce = false}) => _app(
          StatefulBuilder(builder: (context, setState) {
            return FloatingPillNavBar(
              currentIndex: index,
              onTap: (_) {},
              items: [
                for (final label in ['Insights', 'Journey', 'Sadhana', 'Profile'])
                  FolkNavItem(
                    label: label,
                    iconBuilder: (context, selected, color) =>
                        Icon(Icons.circle, size: 22, color: color),
                  ),
              ],
            );
          }),
          reduce: reduce,
        );

    double tabWidth(WidgetTester tester, int i) =>
        tester.getSize(find.byType(AnimatedContainer).at(i)).width;

    testWidgets('the active pill widens over ~250 ms (not a snap) and the label appears', (tester) async {
      await tester.pumpWidget(nav(1));
      await tester.pumpAndSettle();
      final collapsed = tabWidth(tester, 2);

      await tester.pumpWidget(nav(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tabWidth(tester, 2);
      await tester.pumpAndSettle();
      final expanded = tabWidth(tester, 2);

      expect(collapsed, 48);
      expect(mid, greaterThan(collapsed));
      expect(mid, lessThan(expanded));
      expect(expanded, greaterThan(collapsed));
      expect(find.text('Sadhana'), findsOneWidget);
      expect(find.text('Journey'), findsNothing);
      expect(FolkMotion.navMorph.inMilliseconds, 250);
      expect(_tickers(tester), 0);
    });

    testWidgets('reduce animations: the pill switches at once', (tester) async {
      await tester.pumpWidget(nav(1, reduce: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(nav(2, reduce: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Sadhana'), findsOneWidget);
      expect(tabWidth(tester, 2), greaterThan(48));
    });
  });

  test('scheduler binding is the test binding (sanity)', () {
    expect(SchedulerBinding.instance, isNotNull);
  });
}
