import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BottomNavBar.dart' show hostNavItems;
import 'package:folk_app/utils/UnseenDot.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/FolkSegmented.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// ONE dot for the whole Student app: green with a thin, crisp dark border (#1E1B2E), the same size and place as the orange
// one it replaced, in light and dark mode. Journey tab and cards, Insights, Leaderboard, Results, Monthly, RDUA Friends,
// the AI button, Expeditions, Books: they all draw `UnseenDot` (through `UnseenBadge` / `UnseenFeatureBadge`).
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

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: home,
    );

/// The dot's own circle: its decoration.
BoxDecoration dotDecoration(WidgetTester tester, Finder dot) =>
    tester.widget<Container>(find.descendant(of: dot, matching: find.byType(Container)).first).decoration! as BoxDecoration;

void expectGreenDarkBordered(BoxDecoration d, {String? reason}) {
  expect(d.color, kUnseenDotFill, reason: reason ?? 'green fill');
  expect(d.shape, BoxShape.circle);
  final border = d.border! as Border;
  expect(border.top.color, kUnseenDotBorder, reason: reason ?? 'dark border');
  expect(border.top.width, 1.2, reason: 'thin and crisp');
  expect(border.top.style, BorderStyle.solid);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  test('the colours: a clear green fill and the app ink for the border', () {
    expect(kUnseenDotFill, const Color(0xFF2FBF71));
    expect(kUnseenDotBorder, const Color(0xFF1E1B2E));
    expect((kUnseenDotBorder.r * 255).round(), 0x1E);
    expect((kUnseenDotBorder.g * 255).round(), 0x1B);
    expect((kUnseenDotBorder.b * 255).round(), 0x2E);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('UnseenDot: green with a thin dark border, 9 dp by default, the same whatever is behind it — $mode', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const Scaffold(body: Center(child: UnseenDot())), dark: dark));
      expectGreenDarkBordered(dotDecoration(tester, find.byType(UnseenDot)));
      expect(tester.getSize(find.byType(UnseenDot)), const Size(9, 9));
      await tester.pumpWidget(host(const Scaffold(body: Center(child: UnseenDot(size: 12))), dark: dark));
      expect(tester.getSize(find.byType(UnseenDot)), const Size(12, 12));
      expectGreenDarkBordered(dotDecoration(tester, find.byType(UnseenDot)));
    });

    testWidgets('UnseenBadge: the dot sits where it always did (top-right, inset by the offset), and only while shown — $mode', (tester) async {
      phone(tester, 1.0);
      Widget badge(bool show) => host(
            Scaffold(
              body: Center(
                child: UnseenBadge(
                  show: show,
                  offset: const Offset(6, 4),
                  dotSize: 10,
                  child: const SizedBox(key: ValueKey('target'), width: 60, height: 40),
                ),
              ),
            ),
            dark: dark,
          );
      await tester.pumpWidget(badge(false));
      expect(find.byType(UnseenDot), findsNothing);
      await tester.pumpWidget(badge(true));
      final target = tester.getRect(find.byKey(const ValueKey('target')));
      final dot = tester.getRect(find.byType(UnseenDot));
      expect(dot.size, const Size(10, 10));
      expect(dot.right, closeTo(target.right - 6, .01));
      expect(dot.top, closeTo(target.top + 4, .01));
      expectGreenDarkBordered(dotDecoration(tester, find.byType(UnseenDot)));
    });

    testWidgets('the Insights and Journey tabs of the pill nav: both dots are green with the dark border, in place — $mode', (tester) async {
      phone(tester, 1.0);
      final insights = StreamController<bool>.broadcast();
      final journey = StreamController<bool>.broadcast();
      addTearDown(insights.close);
      addTearDown(journey.close);
      await tester.pumpWidget(host(
        Builder(
          builder: (context) => Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: FloatingPillNavBar(
              items: hostNavItems(context, journeyUnseen: journey.stream, insightsUnseen: insights.stream),
              currentIndex: 2,
              onTap: (_) {},
            ),
          ),
        ),
        dark: dark,
      ));
      await tester.pump();
      insights.add(true);
      journey.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(UnseenDot), findsNWidgets(2));
      for (final dot in find.byType(UnseenDot).evaluate()) {
        expectGreenDarkBordered(dotDecoration(tester, find.byWidget(dot.widget)));
      }
    });

    testWidgets('the Monthly segment: a green dot with the dark border beside the label — $mode', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FolkSegmented<int>(
              segments: const [FolkSegment(value: 0, label: 'Weekly'), FolkSegment(value: 1, label: 'Monthly', dot: true)],
              value: 0,
              onChanged: (_) {},
            ),
          ),
        ),
        dark: dark,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(UnseenDot), findsOneWidget);
      expect(tester.getSize(find.byType(UnseenDot)), const Size(8, 8), reason: 'same size as before');
      expectGreenDarkBordered(dotDecoration(tester, find.byType(UnseenDot)));
    });
  }

  for (final scale in scales) {
    testWidgets('the dot keeps its size at text $scale (it is not text)', (tester) async {
      phone(tester, scale);
      await tester.pumpWidget(host(const Scaffold(body: Center(child: UnseenBadge(show: true, child: SizedBox(width: 50, height: 50))))));
      expect(tester.getSize(find.byType(UnseenDot)), const Size(9, 9));
    });
  }

  group('one shared dot style - no orange dot left', () {
    final dir = Directory('lib');
    final files = [for (final f in dir.listSync(recursive: true)) if (f is File && f.path.endsWith('.dart')) f];

    test('the dot widget has no orange in it', () {
      final src = File('lib/utils/UnseenDot.dart').readAsStringSync();
      expect(src.contains('Colors.orange'), isFalse);
      expect(src, contains('kUnseenDotFill'));
      expect(src, contains('kUnseenDotBorder'));
      expect(src.contains('ringColor'), isFalse, reason: 'one style: no per-place ring colour');
    });

    test('every "new" indicator goes through UnseenBadge / UnseenFeatureBadge; nobody paints a dot of their own', () {
      for (final f in files) {
        final src = f.readAsStringSync();
        if (f.path.replaceAll('\\', '/').endsWith('utils/UnseenDot.dart')) continue;
        expect(RegExp(r'UnseenDot\(').hasMatch(src), isFalse, reason: '${f.path} builds a UnseenDot directly (use UnseenBadge)');
        expect(RegExp(r'class\s+\w*(Unseen|New|Badge)\w*Dot\w*\s+extends').hasMatch(src), isFalse, reason: '${f.path} defines its own dot widget');
      }
    });

    test('the callers keep their sizes and offsets (nothing moved): the known sites still pass their own size and offset', () {
      final nav = File('lib/utils/BottomNavBar.dart').readAsStringSync();
      expect(RegExp(r'offset: const Offset\(0, -2\)').allMatches(nav).length, 2, reason: 'Journey and Insights tabs');
      final seg = File('lib/widgets/FolkSegmented.dart').readAsStringSync();
      expect(seg, contains('offset: const Offset(-9, -3)'));
      expect(seg, contains('dotSize: 8'));
      final comp = File('lib/pages/Competition.dart').readAsStringSync();
      expect(comp, contains('offset: const Offset(7, 7)'));
      expect(comp, contains('dotSize: 10'));
      final board = File('lib/pages/LeaderboardPage.dart').readAsStringSync();
      expect(board, contains('offset: const Offset(2, 2)'));
      final ai = File('lib/utils/FloatingAssistantOverlay.dart').readAsStringSync();
      expect(ai, contains('offset: const Offset(6, 6)'));
    });
  });
}
