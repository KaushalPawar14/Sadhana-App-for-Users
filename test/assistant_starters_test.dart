import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/AssistantStarters.dart';
import 'package:folk_app/widgets/AssistantStarterCards.dart';
import 'package:folk_app/widgets/GradientCard.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The four coloured starter questions of an empty chat.

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

Widget host(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FolkSpace.pagePadding),
            child: child,
          ),
        ),
      ),
    );

// The four cards in reading order, with their style and rect.
List<({FolkGradientStyle style, Rect rect, String label})> cards(WidgetTester tester) {
  final out = <({FolkGradientStyle style, Rect rect, String label})>[];
  for (final e in find.byType(GradientCard).evaluate()) {
    final w = e.widget as GradientCard;
    out.add((style: w.style, rect: tester.getRect(find.byWidget(w)), label: w.semanticLabel ?? ''));
  }
  return out;
}

FolkGradientStyle style(String category) =>
    kStarterCategories.firstWhere((c) => c.label == category).style;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('the question pools', () {
    test('four categories, in grid order, with their colours', () {
      expect(kStarterCategories.map((c) => c.label), ['Spiritual question', 'How the app works', 'Daily practice', 'How am I doing']);
      expect(kStarterCategories.map((c) => c.style), [FolkGradientStyle.violet, FolkGradientStyle.saffron, FolkGradientStyle.green, FolkGradientStyle.coral]);
    });

    test('about eight varied questions per category, each one or two sentences, all different', () {
      final all = <String>{};
      for (final c in kStarterCategories) {
        expect(c.questions.length, 8, reason: c.label);
        expect(c.questions.toSet().length, 8, reason: 'no repeat inside ${c.label}');
        for (final q in c.questions) {
          expect(q.length, inInclusiveRange(20, 120), reason: q);
          expect(q.endsWith('?') || q.endsWith('.'), isTrue, reason: q);
          expect(RegExp(r'[.?!]').allMatches(q).length, lessThanOrEqualTo(2), reason: 'one or two sentences: $q');
          expect(all.add(q), isTrue, reason: 'unique across categories: $q');
        }
      }
    });

    test('the named examples are in their pools', () {
      expect(kStarterCategories[0].questions, contains("Who am I if I'm not this body? What does Prabhupada say?"));
      expect(kStarterCategories[1].questions, contains('How do I mark a book as already completed?'));
      expect(kStarterCategories[2].questions, contains('How can I chant my 16 rounds with more attention?'));
      expect(kStarterCategories[3].questions, contains('How am I doing compared to others in my group? What should I improve?'));
    });
  });

  group('rotation: a different question per category each day', () {
    test('one question per category, from its own pool; the same day gives the same set', () {
      final day = DateTime(2026, 10, 14);
      final s = startersForDay(day);
      expect(s.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(kStarterCategories[i].questions, contains(s[i]));
      }
      expect(startersForDay(DateTime(2026, 10, 14, 23, 59)), s, reason: 'a day is a day');
    });

    test('every category changes every day, and the same set never shows two days running', () {
      var previous = startersForDay(DateTime(2026, 1, 1));
      for (var d = 1; d < 400; d++) {
        final now = startersForDay(DateTime(2026, 1, 1).add(Duration(days: d)));
        for (var i = 0; i < 4; i++) {
          expect(now[i], isNot(previous[i]), reason: 'day $d, ${kStarterCategories[i].label}');
        }
        previous = now;
      }
    });

    test('over a few days every question of every pool comes up, and the four are not locked in step', () {
      final seen = [for (final _ in kStarterCategories) <String>{}];
      final sets = <String>{};
      for (var d = 0; d < 8; d++) {
        final s = startersForDay(DateTime(2026, 3, 1).add(Duration(days: d)));
        for (var i = 0; i < 4; i++) {
          seen[i].add(s[i]);
        }
        sets.add(s.join('|'));
      }
      for (final s in seen) {
        expect(s.length, 8);
      }
      expect(sets.length, 8, reason: 'eight different sets');
      // the position in each pool differs between categories on a given day
      final n = startersForDay(DateTime(2026, 3, 1));
      final positions = [for (var i = 0; i < 4; i++) kStarterCategories[i].questions.indexOf(n[i])];
      expect(positions.toSet().length, greaterThan(1));
    });
  });

  group('the cards', () {
    final day = DateTime(2026, 10, 14);

    testWidgets('2x2 grid at normal text: purple top-left, orange top-right, green bottom-left, PINK bottom-right', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(AssistantStarterCards(onPick: (_) {}, today: day)));
      await tester.pumpAndSettle();
      final c = cards(tester);
      expect(c.map((x) => x.style), [FolkGradientStyle.violet, FolkGradientStyle.saffron, FolkGradientStyle.green, FolkGradientStyle.coral]);
      final purple = c[0].rect, orange = c[1].rect, green = c[2].rect, pink = c[3].rect;
      expect(purple.top, orange.top);
      expect(green.top, pink.top);
      expect(purple.left, green.left);
      expect(orange.left, pink.left);
      expect(orange.left, greaterThan(purple.right - .5), reason: 'purple and orange are side by side');
      expect(green.top, greaterThan(purple.bottom - .5));
      // the diagonal: purple top-left, pink bottom-right; never beside or above each other
      expect(pink.left, greaterThan(purple.left));
      expect(pink.top, greaterThan(purple.top));
      expect(pink.top, isNot(purple.top), reason: 'not side by side');
      expect(pink.left, isNot(purple.left), reason: 'not one above the other');
      // each row's two cards are the same height
      expect(purple.height, closeTo(orange.height, .5));
      expect(green.height, closeTo(pink.height, .5));
      expect(purple.width, closeTo(orange.width, .5));
    });

    testWidgets('each card shows its small label and the day\'s question, in ink (#1E1B2E)', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(AssistantStarterCards(onPick: (_) {}, today: day)));
      await tester.pumpAndSettle();
      final qs = startersForDay(day);
      for (var i = 0; i < 4; i++) {
        expect(find.text(kStarterCategories[i].label.toUpperCase()), findsOneWidget);
        final t = tester.widget<Text>(find.text(qs[i]));
        expect(t.style!.color, FolkColors.onGradient);
      }
      expect(FolkColors.onGradient, const Color(0xFF1E1B2E));
    });

    testWidgets('tapping a card sends its question; a disabled set ignores taps', (tester) async {
      phone(tester, 1.0);
      final sent = <String>[];
      await tester.pumpWidget(host(AssistantStarterCards(onPick: sent.add, today: day)));
      await tester.pumpAndSettle();
      final qs = startersForDay(day);
      for (final i in [3, 0, 2, 1]) {
        await tester.tap(find.text(qs[i]));
        await tester.pump();
      }
      expect(sent, [qs[3], qs[0], qs[2], qs[1]]);
      sent.clear();
      await tester.pumpWidget(host(AssistantStarterCards(onPick: sent.add, enabled: false, today: day)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(qs[0]), warnIfMissed: false);
      await tester.pump();
      expect(sent, isEmpty);
    });

    testWidgets('semantics: each card is a button labelled with its category and question', (tester) async {
      phone(tester, 1.0);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(AssistantStarterCards(onPick: (_) {}, today: day)));
      await tester.pumpAndSettle();
      final qs = startersForDay(day);
      expect(find.bySemanticsLabel(RegExp('How am I doing: ${RegExp.escape(qs[3])}')), findsOneWidget);
      handle.dispose();
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale, real fonts: no overflow, every card 112 dp or taller, a valid layout', (tester) async {
          phone(tester, scale);
          // every day of the 8-day cycle, so the longest questions are all measured
          for (var d = 0; d < 8; d++) {
            final date = DateTime(2026, 3, 1).add(Duration(days: d));
            await tester.pumpWidget(host(AssistantStarterCards(onPick: (_) {}, today: date), dark: dark));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'day $d scale $scale dark $dark');
            final c = cards(tester);
            expect(c.map((x) => x.style), [FolkGradientStyle.violet, FolkGradientStyle.saffron, FolkGradientStyle.green, FolkGradientStyle.coral]);
            for (final x in c) {
              expect(x.rect.height, greaterThanOrEqualTo(112 - .5), reason: x.label);
              expect(x.rect.width, greaterThanOrEqualTo(48));
              expect(x.rect.right, lessThanOrEqualTo(360 - FolkSpace.pagePadding + .5), reason: 'inside the page: ${x.label}');
            }
            final stacked = c[0].rect.left == c[1].rect.left;
            if (stacked) {
              // full width, in order: purple first, pink last
              for (var i = 1; i < 4; i++) {
                expect(c[i].rect.top, greaterThan(c[i - 1].rect.bottom - .5));
              }
              expect(c.first.style, FolkGradientStyle.violet);
              expect(c.last.style, FolkGradientStyle.coral);
              expect(c[0].rect.width, closeTo(360 - 2 * FolkSpace.pagePadding, 1));
            } else {
              expect(c[3].rect.left, greaterThan(c[0].rect.left));
              expect(c[3].rect.top, greaterThan(c[0].rect.top));
            }
          }
        });
      }
    }

    testWidgets('at normal text the grid is used for every question; at the largest text it stacks instead of cramming', (tester) async {
      phone(tester, 1.0);
      for (var d = 0; d < 8; d++) {
        await tester.pumpWidget(host(AssistantStarterCards(onPick: (_) {}, today: DateTime(2026, 3, 1).add(Duration(days: d)))));
        await tester.pumpAndSettle();
        final c = cards(tester);
        expect(c[0].rect.top, c[1].rect.top, reason: 'a grid at 1.0, day $d');
      }
      phone(tester, 1.6);
      await tester.pumpWidget(host(AssistantStarterCards(onPick: (_) {}, today: day)));
      await tester.pumpAndSettle();
      final c = cards(tester);
      expect(c[0].rect.left, c[1].rect.left, reason: 'stacked at 1.6');
      expect(c.first.style, FolkGradientStyle.violet);
      expect(c.last.style, FolkGradientStyle.coral);
    });
  });

  group('the chat uses them', () {
    test('AssistantScreen shows the cards in its empty view and sends through the same _send; the old chips are gone', () {
      final src = File('lib/pages/AssistantScreen.dart').readAsStringSync();
      expect(src, contains('AssistantStarterCards(onPick: _send, enabled: !_sending)'));
      expect(src.contains('_starterChip'), isFalse);
      expect(src.contains('static const List<String> _starters'), isFalse);
      expect(src, contains('_turns.isEmpty'));
    });
  });
}
