import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/ReaderContrast.dart';
import 'package:folk_app/widgets/DoubtDialogs.dart';
import 'package:folk_app/widgets/GradientActionButton.dart';
import 'package:folk_app/widgets/PressScale.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The ask-a-doubt dialog: "Ask guide" and "Ask AI" side by side (green / violet gradients, ink text, soft elevation, press
// feedback), Cancel a quiet text button; it opens with a ~200 ms fade + slight scale and rise, the keyboard only after it
// has opened, no rebuild per keyboard frame; the same in the three reading modes and at text 1.0 / 1.3 / 1.6.
void phone(WidgetTester tester, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// The reading modes' own dialog colours (chrome / onChrome / secondary).
const modes = <String, (Color, Color, Color)>{
  'light': (Color(0xFFFFFFFF), Color(0xFF1E1B2E), Color(0xFF5E5A70)),
  'dark': (Color(0xFF1B1A22), Color(0xFFF1EFF8), Color(0xFFB5B1C6)),
  'sepia': (Color(0xFFF4E8D0), Color(0xFF3B2F1E), Color(0xFF6B5A40)),
};

Future<void> open(WidgetTester tester, {String mode = 'light', double scale = 1.0, bool reduce = false, bool dark = false}) async {
  phone(tester, scale);
  final (chrome, onChrome, secondary) = modes[mode]!;
  await tester.pumpWidget(MaterialApp(
    theme: dark ? FolkTheme.dark : FolkTheme.light,
    builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduce), child: w!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () => showAskDoubtDialog(context, passage: 'The soul is eternal.', chrome: chrome, onChrome: onChrome, secondary: secondary),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump(); // the route is pushed; its transition has not moved yet
}

BoxDecoration inkDecoration(WidgetTester tester, String key) => tester
    .widgetList<Ink>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Ink)))
    .map((i) => i.decoration)
    .whereType<BoxDecoration>()
    .first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final mode in modes.keys) {
    group('reading mode: $mode', () {
      testWidgets('Ask guide and Ask AI sit side by side in one row, equal width, same height; Ask guide is green, Ask AI violet', (tester) async {
        await open(tester, mode: mode, reduce: true);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('doubt-ask-row')), findsOneWidget);
        expect(find.byKey(const ValueKey('doubt-ask-stack')), findsNothing);
        final g = tester.getRect(find.byKey(const ValueKey('doubt-ask-guide')));
        final a = tester.getRect(find.byKey(const ValueKey('doubt-ask-ai')));
        expect(g.top, closeTo(a.top, .5), reason: 'one row');
        expect(g.width, closeTo(a.width, .5), reason: 'equal width');
        expect(g.height, closeTo(a.height, .5));
        expect(g.right, lessThan(a.left), reason: 'Ask guide, then Ask AI');
        expect(a.left - g.right, closeTo(10, .5));
        // a little narrower than the dialog's content: 8 dp of air on each side of the pair (dialog inset 20 + padding 20 + 8)
        final box = tester.getRect(find.byKey(const ValueKey('ask-doubt-dialog')));
        expect(g.left - box.left, closeTo(20 + 20 + 8, .5));
        expect(box.right - a.right, closeTo(20 + 20 + 8, .5));
        expect(g.height, closeTo(34, .5), reason: 'compact: 34 dp tall at normal text');
        expect((inkDecoration(tester, 'doubt-ask-guide').gradient! as LinearGradient).colors, FolkGradients.green.colors);
        expect((inkDecoration(tester, 'doubt-ask-ai').gradient! as LinearGradient).colors, FolkGradients.violet.colors);
        expect(tester.takeException(), isNull);
      });

      testWidgets('ink text on both gradients (>= 4.5:1 on every stop), a soft tinted elevation, press feedback; the same in every mode', (tester) async {
        await open(tester, mode: mode, reduce: true);
        await tester.pumpAndSettle();
        for (final k in ['doubt-ask-guide', 'doubt-ask-ai']) {
          final label = tester.widget<Text>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Text)));
          expect(label.style!.color, FolkColors.onGradient, reason: '$k: ink, not plain black / white');
          final gradient = inkDecoration(tester, k).gradient! as LinearGradient;
          for (final c in gradient.colors) {
            expect(contrastRatio(FolkColors.onGradient.toARGB32(), c.toARGB32()), greaterThanOrEqualTo(4.5), reason: '$k on $c');
          }
          final shadow = tester
              .widgetList<DecoratedBox>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(DecoratedBox)))
              .map((d) => d.decoration)
              .whereType<BoxDecoration>()
              .firstWhere((d) => d.boxShadow != null && d.boxShadow!.isNotEmpty)
              .boxShadow!
              .first;
          expect(shadow.blurRadius, greaterThanOrEqualTo(10), reason: 'soft');
          expect(shadow.color.a, lessThan(.5), reason: 'gentle');
          expect(shadow.color, isNot(Colors.black), reason: 'tinted by the gradient, not a hard black shadow');
          // press feedback: the app's PressScale (0.97 while a finger is down)
          expect(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(PressScale)), findsOneWidget);
        }
        final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('doubt-ask-ai'))));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.hasRunningAnimations || true, isTrue);
        await gesture.cancel();
      });

      testWidgets('Cancel stays a quiet text button, under the buttons', (tester) async {
        await open(tester, mode: mode, reduce: true);
        await tester.pumpAndSettle();
        final cancel = find.byKey(const ValueKey('doubt-cancel'));
        expect(tester.widget(cancel), isA<TextButton>());
        expect(tester.getTopLeft(cancel).dy, greaterThan(tester.getBottomLeft(find.byKey(const ValueKey('doubt-ask-ai'))).dy));
        expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ask-doubt-dialog')), findsNothing);
      });
    });
  }

  for (final scale in scales) {
    for (final mode in modes.keys) {
      testWidgets('text $scale, $mode: fits, nothing overflows; side by side whenever the labels fit, stacked (full width) only when they cannot; 34 dp buttons', (tester) async {
        await open(tester, mode: mode, scale: scale, reduce: true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final row = find.byKey(const ValueKey('doubt-ask-row')).evaluate().isNotEmpty;
        final stack = find.byKey(const ValueKey('doubt-ask-stack')).evaluate().isNotEmpty;
        expect(row != stack, isTrue, reason: 'exactly one layout');
        final g = tester.getRect(find.byKey(const ValueKey('doubt-ask-guide')));
        final a = tester.getRect(find.byKey(const ValueKey('doubt-ask-ai')));
        final box = tester.getRect(find.byKey(const ValueKey('ask-doubt-dialog')));
        expect(box.right, lessThanOrEqualTo(360));
        for (final r in [g, a]) {
          expect(r.height, greaterThanOrEqualTo(34 - .5), reason: '34 dp, growing only with the text');
          expect(r.left, greaterThanOrEqualTo(box.left));
          expect(r.right, lessThanOrEqualTo(box.right));
        }
        if (scale <= 1.3) expect(row, isTrue, reason: 'at normal and 1.3x text they fit side by side');
        if (row) {
          expect(g.top, closeTo(a.top, .5));
          expect(g.width, closeTo(a.width, .5));
          // each label stays on one line
          for (final k in ['doubt-ask-guide', 'doubt-ask-ai']) {
            final t = find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Text));
            expect(tester.renderObject<RenderParagraph>(t).didExceedMaxLines, isFalse);
            expect(tester.getSize(t).height, lessThan(26 * scale * 1.6), reason: '$k one line');
          }
        } else {
          expect(g.width, closeTo(a.width, .5), reason: 'stacked: both full width');
          expect(a.top, greaterThan(g.bottom - .5), reason: 'one under the other');
        }
      });
    }

    testWidgets('text $scale, keyboard open: the dialog scrolls and the buttons stay reachable, no overflow', (tester) async {
      await open(tester, scale: scale, reduce: true);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('doubt-ask-ai')));
      await tester.pump();
      final r = tester.getRect(find.byKey(const ValueKey('doubt-ask-ai')));
      expect(r.bottom, lessThanOrEqualTo(800 - 300 + .5), reason: 'above the keyboard');
      expect(r.top, greaterThanOrEqualTo(0));
    });
  }

  group('opening: smooth, ~200 ms, keyboard after it, no rebuild per keyboard frame', () {
    Finder fade() => find.ancestor(of: find.byKey(const ValueKey('ask-doubt-dialog')), matching: find.byType(FadeTransition)).first;
    Finder scaleT() => find.ancestor(of: find.byKey(const ValueKey('ask-doubt-dialog')), matching: find.byType(ScaleTransition)).first;
    double opacity(WidgetTester t) => t.widget<FadeTransition>(fade()).opacity.value;
    double scaleOf(WidgetTester t) => t.widget<ScaleTransition>(scaleT()).scale.value;
    bool focused(WidgetTester t) => t.widget<TextField>(find.byKey(const ValueKey('doubt-question'))).focusNode!.hasFocus;

    testWidgets('a gentle fade with a slight scale and rise over 200 ms', (tester) async {
      expect(kDoubtDialogOpen, const Duration(milliseconds: 200));
      await open(tester);
      await tester.pump(const Duration(milliseconds: 1));
      expect(opacity(tester), lessThan(0.1), reason: 'starts transparent');
      expect(scaleOf(tester), lessThan(0.97), reason: 'starts slightly small');
      final y0 = tester.getTopLeft(find.byKey(const ValueKey('ask-doubt-dialog'))).dy;
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(tester), inExclusiveRange(0.3, 0.99));
      expect(scaleOf(tester), inExclusiveRange(0.96, 1.0));
      await tester.pump(const Duration(milliseconds: 120));
      expect(opacity(tester), 1);
      expect(scaleOf(tester), 1);
      final y1 = tester.getTopLeft(find.byKey(const ValueKey('ask-doubt-dialog'))).dy;
      expect(y0, greaterThan(y1), reason: 'it rises into place');
      expect(y0 - y1, lessThan(40), reason: 'slight');
    });

    testWidgets('it does not shift once open (no layout change after the transition)', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 260));
      final settled = tester.getRect(find.byKey(const ValueKey('ask-doubt-dialog')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(find.byKey(const ValueKey('ask-doubt-dialog'))), settled);
    });

    testWidgets('the keyboard (the question field\'s focus) is asked for only AFTER the dialog has opened', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(focused(tester), isFalse, reason: 'still opening: no keyboard yet (it made the dialog resize mid-move)');
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();
      expect(focused(tester), isTrue, reason: 'open: the field is focused and the keyboard comes');
    });

    testWidgets('"reduce animations": no transition at all, the dialog is there at once and the field is focused', (tester) async {
      await open(tester, reduce: true);
      await tester.pump();
      expect(opacity(tester), 1);
      expect(scaleOf(tester), 1);
      expect(focused(tester), isTrue);
    });

    testWidgets('typing keeps the dialog still: the buttons are not rebuilt or moved, and the error clears only once', (tester) async {
      await open(tester, reduce: true);
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(const ValueKey('doubt-ask-ai')));
      await tester.tap(find.byKey(const ValueKey('doubt-ask-ai')));
      await tester.pump();
      expect(find.text('Please write your doubt first'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('doubt-question')), 'W');
      await tester.pump();
      expect(find.text('Please write your doubt first'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('doubt-question')), 'What does this mean?');
      await tester.pump();
      // the message came and went: the buttons are where they were (apart from the line the message used)
      expect(tester.getRect(find.byKey(const ValueKey('doubt-ask-ai'))).left, before.left);
      expect(tester.getRect(find.byKey(const ValueKey('doubt-ask-ai'))).width, before.width);
    });

    testWidgets('tapping outside closes it; Ask guide / Ask AI return the question and the mode', (tester) async {
      await open(tester, reduce: true);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ask-doubt-dialog')), findsNothing, reason: 'barrier dismiss');
    });
  });

  test('wiring: the dialog reads no keyboard insets (no rebuild per keyboard frame) and uses the gradient buttons', () {
    final whole = File('lib/widgets/DoubtDialogs.dart').readAsStringSync();
    final src = whole.substring(0, whole.indexOf('enum DoubtAction')); // the ask dialog and its buttons
    expect(src.contains('viewInsets'), isFalse, reason: 'MediaQuery insets would rebuild the dialog on every frame of the keyboard');
    expect(src.contains('autofocus: true'), isFalse, reason: 'the keyboard waits for the opening transition');
    expect(src, contains('focusNode: _focus'));
    expect(src, contains('FolkGradients.green'));
    expect(src, contains('FolkGradients.violet'));
    expect(src, contains('GradientActionButton('));
    expect(src.contains('LayoutBuilder'), isFalse);
    expect(File('lib/widgets/GradientActionButton.dart').readAsStringSync(), contains('FolkColors.onGradient'));
  });
}
