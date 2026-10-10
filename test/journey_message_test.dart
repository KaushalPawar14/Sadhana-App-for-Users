import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/services/DailyMessageService.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/DailyMessageCard.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/TypingDots.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// "Today's message" at the top of Journey: its states (loading with dots, ready,
// disclosure not accepted, failed), at every text size.
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

DailyMessageState stateOf(bool loading, String? message) => loading
    ? const DailyMessageState(DailyMessageStatus.loading)
    : message == null
        ? const DailyMessageState(DailyMessageStatus.needsDisclosure)
        : DailyMessageState(DailyMessageStatus.ready, text: message);

Widget scene({
  required bool loading,
  String? message,
  DailyMessageState? state,
  bool dark = false,
  bool reduce = false,
  VoidCallback? onTap,
}) {
  return MaterialApp(
    theme: dark ? FolkTheme.dark : FolkTheme.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: Scaffold(
          body: GhostScope(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                JourneyTodayMessage(
                  state: state ?? stateOf(loading, message),
                  onTap: onTap ?? () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

const short = 'You kept your promise to Krishna yesterday.';
const medium =
    'You kept your promise to Krishna yesterday, and that steady faithfulness is beautiful.';
const long = 'You kept your promise to Krishna yesterday, and that steady faithfulness '
    'is beautiful. Keep chanting with attention today, and let every round be '
    'an offering. Small steady steps carry you further than a rush of effort, '
    'so return to the holy name whenever the mind wanders, and know that you '
    'are never alone on this path.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text scale $scale, 360 dp';

      group('Journey today\'s message — $s', () {
        testWidgets('message: label and text, no overflow, ellipsis past 4 lines',
            (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(scene(loading: false, message: long, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text("TODAY'S MESSAGE"), findsOneWidget);
          final text = tester.widget<Text>(find.text(long));
          expect(text.maxLines, 4);
          expect(text.overflow, TextOverflow.ellipsis);
          // The label and message sit fully inside the card.
          final card = tester.getRect(find.byType(DailyMessageCard));
          for (final f in [find.text("TODAY'S MESSAGE"), find.text(long)]) {
            final r = tester.getRect(f);
            expect(r.top, greaterThanOrEqualTo(card.top));
            expect(r.bottom, lessThanOrEqualTo(card.bottom));
            expect(r.right, lessThanOrEqualTo(card.right));
          }
        });

        testWidgets('no message yet: the same card with the waiting line',
            (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(scene(loading: false, message: null, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text("TODAY'S MESSAGE"), findsOneWidget);
          expect(find.text(JourneyTodayMessage.waitingText), findsOneWidget);
        });

        testWidgets('a tap, with or without a message, calls onTap (opens Ask)',
            (tester) async {
          phone(tester, scale);
          var taps = 0;
          await tester.pumpWidget(
              scene(loading: false, message: medium, dark: dark, onTap: () => taps++));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DailyMessageCard));
          await tester.pumpAndSettle();
          expect(taps, 1);
          await tester.pumpWidget(
              scene(loading: false, message: null, dark: dark, onTap: () => taps++));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DailyMessageCard));
          await tester.pumpAndSettle();
          expect(taps, 2);
        });

        testWidgets('loading: the same card with "Loading" and animated dots, no ghost',
            (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(scene(loading: true, dark: dark));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(find.text("TODAY'S MESSAGE"), findsOneWidget);
          expect(find.text('Loading'), findsOneWidget);
          expect(find.byType(TypingDots), findsOneWidget);
          expect(find.byType(GhostPlaceholder), findsNothing);
          expect(find.byType(DailyMessageCard), findsOneWidget);
          // a tap in the loading state still opens Ask
          var taps = 0;
          await tester.pumpWidget(scene(loading: true, dark: dark, onTap: () => taps++));
          await tester.pump();
          await tester.tap(find.byType(DailyMessageCard));
          await tester.pump();
          expect(taps, 1);
          await tester.pumpWidget(const SizedBox());
        });

        testWidgets('failed and not-accepted both show the "tap to open" line',
            (tester) async {
          phone(tester, scale);
          for (final st in [
            const DailyMessageState(DailyMessageStatus.failed),
            const DailyMessageState(DailyMessageStatus.needsDisclosure),
          ]) {
            await tester.pumpWidget(scene(loading: false, state: st, dark: dark));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: s);
            expect(find.text("TODAY'S MESSAGE"), findsOneWidget);
            expect(find.text(JourneyTodayMessage.waitingText), findsOneWidget);
            expect(find.text('Loading'), findsNothing);
          }
        });

        testWidgets('loading -> ready cross-fades; the text appears and the dots go',
            (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(scene(loading: true, dark: dark));
          await tester.pump();
          await tester.pumpWidget(scene(loading: false, message: medium, dark: dark));
          await tester.pump(const Duration(milliseconds: 60));
          expect(find.text(medium), findsOneWidget, reason: 'fading in');
          await tester.pumpAndSettle();
          expect(find.text(medium), findsOneWidget);
          expect(find.text('Loading'), findsNothing);
          expect(find.byType(TypingDots), findsNothing);
        });

        testWidgets('every state is the same height (no jump when the message arrives)',
            (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(scene(loading: true, dark: dark));
          await tester.pump();
          final ghost = tester.getSize(find.byType(JourneyTodayMessage)).height;
          await tester.pumpWidget(const SizedBox());
          for (final m in [short, medium, long, null]) {
            await tester.pumpWidget(scene(loading: false, message: m, dark: dark));
            await tester.pumpAndSettle();
            final real = tester.getSize(find.byType(JourneyTodayMessage)).height;
            expect(real, closeTo(ghost, 1.0),
                reason: 'message ${m == null ? 'waiting' : m.length} chars, $s');
          }
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        });

        testWidgets('reduce motion: the dots are still and the swap is instant, no ticker left',
            (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(scene(loading: true, dark: dark, reduce: true));
          await tester.pump();
          expect(tester.binding.transientCallbackCount, 0,
              reason: 'dots must not animate');
          await tester.pumpWidget(
              scene(loading: false, message: medium, dark: dark, reduce: true));
          await tester.pump();
          expect(find.text(medium), findsOneWidget);
          expect(find.byType(GhostPlaceholder), findsNothing);
          expect(tester.binding.transientCallbackCount, 0);
        });
      });
    }
  }

  testWidgets('Ask\'s own card (no tap) is not a button and has no ellipsis cap',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FolkTheme.light,
      home: const Scaffold(body: DailyMessageCard(text: long)),
    ));
    expect(find.byType(InkWell), findsNothing);
    expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
  });
}
