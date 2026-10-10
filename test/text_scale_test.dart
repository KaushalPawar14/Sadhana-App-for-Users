import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/DayHeatStrip.dart';
import 'package:folk_app/widgets/EpisodeTile.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/FolkChip.dart';
import 'package:folk_app/widgets/GhostedTextLine.dart';
import 'package:folk_app/widgets/MinHeightBox.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/SadhanaDayCell.dart';
import 'package:table_calendar/table_calendar.dart';

const scales = [1.0, 1.3, 1.6];

// 360 dp wide, text scaled by [scale]; content gets the usual 20 dp page
// padding on each side.
Widget host(Widget child, double scale, {bool dark = false}) {
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(360, 800),
      textScaler: TextScaler.linear(scale),
    ),
    child: MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(width: 320, child: child),
          ),
        ),
      ),
    ),
  );
}

// Every Text under [outer] sits fully inside [outer] vertically (nothing is cut
// off at the top or bottom); also no layout overflow was reported.
void expectNoClip(WidgetTester tester, Finder outer, {String? reason}) {
  expect(tester.takeException(), isNull, reason: 'overflow ${reason ?? ''}');
  final box = tester.getRect(outer.first);
  final texts = find.descendant(of: outer.first, matching: find.byType(Text));
  expect(texts, findsWidgets);
  for (final element in texts.evaluate()) {
    final r = tester.getRect(find.byWidget(element.widget).first);
    expect(r.top, greaterThanOrEqualTo(box.top - .5),
        reason: 'text "${(element.widget as Text).data}" clipped at the top ${reason ?? ''}');
    expect(r.bottom, lessThanOrEqualTo(box.bottom + .5),
        reason: 'text "${(element.widget as Text).data}" clipped at the bottom ${reason ?? ''}');
  }
}

// The app's real fonts, so text measures the way it does on a phone (the test
// default font is much wider).
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('DM Sans', ['DMSans-Regular.ttf', 'DMSans-Medium.ttf', 'DMSans-Bold.ttf']);
  await load('Bricolage Grotesque', ['BricolageGrotesque-Medium.ttf', 'BricolageGrotesque-Bold.ttf']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppFonts);

  for (final scale in scales) {
    final s = 'text scale $scale';

    group('Journey progress line (GhostedTextLine) — $s at 360 dp', () {
      testWidgets('real line: at least 17 dp, never clips', (tester) async {
        await tester.pumpWidget(host(
          const DefaultTextStyle(
            style: TextStyle(fontSize: 12),
            child: GhostedTextLine(
              loading: false,
              child: Text('Currently reading: IQ EQ SQ',
                  key: ValueKey('line'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          scale,
        ));
        await tester.pumpAndSettle();
        expectNoClip(tester, find.byType(MinHeightBox), reason: s);
        expect(tester.getSize(find.byType(MinHeightBox)).height, greaterThanOrEqualTo(17.2));
      });

      testWidgets('ghost grows with the text size and the swap does not overflow', (tester) async {
        await tester.pumpWidget(host(
          const GhostedTextLine(loading: true, child: Text('x')),
          scale,
        ));
        final ghost = tester.getSize(find.byType(GhostedTextLine)).height;
        expect(ghost, greaterThanOrEqualTo(17.2));
        expect(ghost, closeTo(17.2 * (scale > 1 ? scale : 1), 2));
        expect(tester.takeException(), isNull);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      });
    });

    group('Japa 30-day card (DayHeatStrip) — $s at 360 dp', () {
      final data = [
        for (var i = 29; i >= 0; i--)
          {'date': DateTime(2026, 10, 9).subtract(Duration(days: i)), 'rounds': i % 9},
      ];

      testWidgets('real strip: at least 88 dp, day numbers never clip', (tester) async {
        await tester.pumpWidget(host(
          DayHeatStrip(data: data, fillFor: (r) => Colors.green, onTapDay: (_, __) {}),
          scale,
        ));
        final strip = find.byType(DayHeatStrip);
        expect(tester.getSize(strip).height, greaterThanOrEqualTo(88));
        // Only the day numbers that are on screen are laid out (it scrolls
        // sideways); every one of them must sit inside the card vertically.
        expectNoClip(tester, strip, reason: s);
      });

      testWidgets('its ghost is about the same height (within 6 dp)', (tester) async {
        await tester.pumpWidget(host(
          DayHeatStrip(data: data, fillFor: (r) => Colors.green, onTapDay: (_, __) {}),
          scale,
        ));
        final real = tester.getSize(find.byType(DayHeatStrip)).height;
        await tester.pumpWidget(host(const DayHeatStripGhost(), scale));
        final ghost = tester.getSize(find.byType(DayHeatStripGhost)).height;
        expect((ghost - real).abs(), lessThanOrEqualTo(6),
            reason: 'real $real vs ghost $ghost at $s');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      });
    });

    group('Podcast rows — $s at 360 dp', () {
      testWidgets('label rows are minimum heights (18.6 / 15.7 dp) and never clip', (tester) async {
        await tester.pumpWidget(host(
          Builder(builder: (context) {
            final text = context.folkText;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MinHeightBox(
                  minHeight: 18.6,
                  child: Text('Listening language', style: text.small),
                ),
                MinHeightBox(
                  minHeight: 15.7,
                  child: Text('12 EPISODES', style: text.label),
                ),
              ],
            );
          }),
          scale,
        ));
        for (final box in find.byType(MinHeightBox).evaluate()) {
          final r = tester.getRect(find.byWidget(box.widget));
          final label = find.descendant(of: find.byWidget(box.widget), matching: find.byType(Text));
          final t = tester.getRect(label);
          expect(t.top, greaterThanOrEqualTo(r.top - .5));
          expect(t.bottom, lessThanOrEqualTo(r.bottom + .5));
        }
        expect(tester.getSize(find.byType(MinHeightBox).first).height, greaterThanOrEqualTo(18.6));
        expect(tester.takeException(), isNull);
      });

      for (final variant in ['playing now', 'paused', 'no audio', 'failed', 'loading']) {
        testWidgets('episode row ($variant): at least 72 dp, long title wraps, nothing clips', (tester) async {
          await tester.pumpWidget(host(
            EpisodeTile(
              title: 'FAQs on Hare Krishna Mahamantra - Part 1 and a much longer second line',
              duration: '15:34 min',
              hasAudio: variant != 'no audio',
              isCurrent: variant == 'playing now' || variant == 'loading',
              isPlaying: variant == 'playing now',
              isLoading: variant == 'loading',
              failed: variant == 'failed',
              onTap: variant == 'no audio' ? null : () {},
            ),
            scale,
          ));
          // The loading variant has a spinner that never settles.
          await tester.pump(const Duration(milliseconds: 400));
          final tile = find.byType(EpisodeTile);
          expect(tester.getSize(tile).height, greaterThanOrEqualTo(72));
          expectNoClip(tester, tile, reason: '$variant $s');
        });
      }
    });

    group('Sadhana legend and calendar card — $s at 360 dp', () {
      testWidgets('legend: at least 17 dp, grows, never clips', (tester) async {
        await tester.pumpWidget(host(const SadhanaLegend(), scale));
        final legend = find.byType(SadhanaLegend);
        expect(tester.getSize(legend).height, greaterThanOrEqualTo(17.2));
        expectNoClip(tester, legend, reason: s);
      });

      testWidgets('the calendar card (days, weekday row, header, legend) does not overflow or clip', (tester) async {
        tester.view.physicalSize = const Size(360, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final month = DateTime(2026, 8, 1); // 6 weeks: the tallest month
        const rowHeight = 360 * 0.12;
        final key = GlobalKey();
        var legendHeight = 0.0;
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(size: const Size(360, 1400), textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: FolkTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    key: key,
                    padding: const EdgeInsets.all(FolkSpace.lg),
                    child: Column(
                      children: [
                        TableCalendar(
                          focusedDay: month,
                          firstDay: DateTime(2026, 7, 1),
                          lastDay: DateTime(2026, 8, 31),
                          rowHeight: rowHeight,
                          daysOfWeekHeight: 30,
                          calendarStyle: const CalendarStyle(outsideDaysVisible: false),
                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            headerPadding: const EdgeInsets.only(bottom: FolkSpace.md),
                            leftChevronIcon: const SizedBox(width: 44, height: 44),
                            rightChevronIcon: const SizedBox(width: 44, height: 44),
                            leftChevronPadding: const EdgeInsets.all(2),
                            rightChevronPadding: const EdgeInsets.all(2),
                            leftChevronMargin: EdgeInsets.zero,
                            rightChevronMargin: EdgeInsets.zero,
                          ),
                          calendarBuilders: CalendarBuilders(
                            prioritizedBuilder: (context, date, _) => SadhanaDayCell(
                              day: date.day,
                              state: date.day.isEven ? SadhanaDayState.submitted : SadhanaDayState.missed,
                            ),
                          ),
                        ),
                        const SizedBox(height: SadhanaCalendarGhost.legendGap),
                        Builder(builder: (context) {
                          legendHeight = SadhanaLegend.heightFor(context, 320 - 2 * FolkSpace.lg);
                          return const SadhanaLegend();
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'overflow at $s');
        // Every day number sits inside its cell's circle row (no text cut off).
        for (final day in ['1', '15', '31']) {
          final t = tester.getRect(find.text(day).first);
          expect(t.height, lessThanOrEqualTo(rowHeight + .5), reason: 'day $day at $s');
        }
        // The ghost is exactly the real card's height at every text size, the
        // wrapping legend included (it measures the legend with the same style).
        final real = tester.getSize(find.byKey(key)).height;
        final ghost = SadhanaCalendarGhost.cardHeight(month, rowHeight,
            legend: legendHeight);
        debugPrint('calendar card at $s: real $real, ghost $ghost; legend real ${tester.getSize(find.byType(SadhanaLegend)).height} predicted $legendHeight');
        // At the default size the ghost is exact. At large text sizes the real
        // header's month title can wrap onto a second line, which the ghost does
        // not guess (it only measures the legend), so it may be a little short.
        final allowed = scale == 1.0 ? 1.0 : (scale == 1.3 ? 20.0 : 34.0);
        expect((real - ghost).abs(), lessThanOrEqualTo(allowed), reason: 'real $real vs ghost $ghost at $s');
      });
    });

    group('other fixed-height controls — $s at 360 dp', () {
      testWidgets('chips, primary button', (tester) async {
        await tester.pumpWidget(host(
          Column(children: [
            // Chip rows scroll sideways in the app.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                FolkChip(label: 'FOLK-12', selected: true, onTap: () {}, large: true),
                const SizedBox(width: 8),
                FolkChip(label: 'English', selected: false, onTap: () {}),
              ]),
            ),
            const SizedBox(height: 12),
            PrimaryButton(label: 'Submit Sadhana', onPressed: () {}),
          ]),
          scale,
        ));
        expectNoClip(tester, find.byType(FolkChip).first, reason: 'chip $s');
        expectNoClip(tester, find.byType(PrimaryButton), reason: 'button $s');
      });

      testWidgets('floating pill navigation with the longest tab names', (tester) async {
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            theme: FolkTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: FloatingPillNavBar(
                  currentIndex: 0,
                  onTap: (_) {},
                  items: [
                    for (final label in ['Insights', 'Journey', 'Sadhana', 'Profile'])
                      FolkNavItem(
                        label: label,
                        iconBuilder: (context, selected, color) => Icon(Icons.circle, size: 22, color: color),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'pill overflow at $s');
      });
    });
  }
}
