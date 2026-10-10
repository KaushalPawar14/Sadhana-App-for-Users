import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/widgets/AttentionPulse.dart';

// The AI button's attention pulse: ~1.2 s every ~6 s, nothing in between, and
// never in the background, under TickerMode off, or with reduce motion.
Widget app({bool reduce = false, bool tickers = true, Key? key}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: TickerMode(
            enabled: tickers,
            child: const AttentionPulse(
              size: 58,
              child: SizedBox(width: 58, height: 58, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.purple))),
            ),
          ),
        ),
      ),
    );

int tickers(WidgetTester tester) => tester.binding.transientCallbackCount;

double scale(WidgetTester tester) => tester.widget<ScaleTransition>(find.descendant(of: find.byType(AttentionPulse), matching: find.byType(ScaleTransition))).scale.value;

void main() {
  testWidgets('first pulse after 2 s, lasts 1.2 s, then none for 4.8 s, then again (6 s cycle)', (tester) async {
    await tester.pumpWidget(app());
    expect(tickers(tester), 0, reason: 'idle on appearing: no ticker');
    await tester.pump(const Duration(milliseconds: 1900));
    expect(tickers(tester), 0, reason: 'still waiting for the first pulse');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tickers(tester), 1, reason: 'pulsing');
    expect(scale(tester), greaterThan(1.0));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tickers(tester), 0, reason: 'pulse over: ticker gone');
    expect(scale(tester), 1.0);
    // 4.8 s of rest: no ticker at any point
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      expect(tickers(tester), 0, reason: 'between pulses ($i)');
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tickers(tester), 1, reason: 'second pulse ~6 s after the first started');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rest of the time the pulse is a single waiting Timer (no frames requested)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(tickers(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'idle between pulses');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stops in the background and starts again on resume', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tickers(tester), 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tickers(tester), 0, reason: 'background: stopped');
    expect(scale(tester), 1.0);
    await tester.pump(const Duration(seconds: 30));
    expect(tickers(tester), 0, reason: 'no pulses in the background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 4700));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tickers(tester), 1, reason: 'pulses again ~4.8 s after resume');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TickerMode off (hidden route): no pulse; on again: pulses', (tester) async {
    await tester.pumpWidget(app(tickers: false));
    await tester.pump(const Duration(seconds: 20));
    expect(tickers(tester), 0);
    expect(scale(tester), 1.0);
    await tester.pumpWidget(app(tickers: true));
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tickers(tester), 1);
    await tester.pumpWidget(app(tickers: false));
    await tester.pump();
    expect(tickers(tester), 0);
    await tester.pump(const Duration(seconds: 20));
    expect(tickers(tester), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: never pulses', (tester) async {
    await tester.pumpWidget(app(reduce: true));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(tickers(tester), 0);
    }
    expect(scale(tester), 1.0);
  });

  testWidgets('the rings paint in their own repaint layer, with no blur or backdrop filter', (tester) async {
    await tester.pumpWidget(app());
    expect(find.descendant(of: find.byType(AttentionPulse), matching: find.byType(RepaintBoundary)), findsWidgets);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposing mid-pulse leaves no timer or ticker behind', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tickers(tester), 0);
  });
}
