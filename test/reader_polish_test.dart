// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/pages/BooksNotesPage.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/utils/BookNotes.dart';
import 'package:folk_app/utils/ReaderContrast.dart';
import 'package:folk_app/widgets/PressScale.dart';
import 'package:folk_app/widgets/ReaderHighlights.dart';
import 'package:folk_app/widgets/ReaderLoadingGhost.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Book reader polish: the selection buttons, the category colours, the note jump and the loading screen.
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

Widget host(Widget home, {bool dark = false, bool reduce = true}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: home,
    );

int argb(Color c) => c.toARGB32();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  // ----------------------------------------------------------------------------------------- the selection bar
  group('selection toolbar: one small floating container with a 2 x 2 grid of pills', () {
    Widget bar(String mode, {List<String>? log}) => Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(ReaderSelectionBar.sideMargin, 0, ReaderSelectionBar.sideMargin, ReaderSelectionBar.bottomGap),
            child: ReaderSelectionBar(
              background: kReaderPalettes[mode]!.chrome,
              onSentence: () => log?.add('sentence'),
              onParagraph: () => log?.add('paragraph'),
              onCancel: () => log?.add('cancel'),
              onHighlight: () => log?.add('highlight'),
            ),
          ),
        );

    Future<void> show(WidgetTester tester, String mode, double scale, {double width = 360, bool reduce = true}) async {
      phone(tester, scale);
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(host(Scaffold(backgroundColor: kReaderPalettes[mode]!.background, body: bar(mode)), dark: mode == 'dark', reduce: reduce));
      await tester.pumpAndSettle();
    }

    const keys = ['sel-sentence', 'sel-paragraph', 'sel-cancel', 'sel-highlight'];
    Rect r(WidgetTester tester, String k) => tester.getRect(find.byKey(ValueKey(k)));
    Rect toolbar(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('selection-toolbar')));

    void expectGrid(WidgetTester tester, {required String reason}) {
      final sen = r(tester, 'sel-sentence'), par = r(tester, 'sel-paragraph'), can = r(tester, 'sel-cancel'), hi = r(tester, 'sel-highlight');
      expect((sen.top - par.top).abs(), lessThan(1), reason: '$reason: Sentence and Paragraph share the top row');
      expect((can.top - hi.top).abs(), lessThan(1), reason: '$reason: Cancel and Highlight share the bottom row');
      expect(can.top, greaterThanOrEqualTo(sen.bottom - .5), reason: '$reason: the second row is below, never beside');
      expect((sen.left - can.left).abs(), lessThan(1), reason: '$reason: the left column lines up');
      expect((par.left - hi.left).abs(), lessThan(1), reason: '$reason: the right column lines up');
      expect(sen.left, lessThan(par.left));
      expect((sen.width - par.width).abs(), lessThan(1), reason: '$reason: equal pills');
      expect((sen.width - can.width).abs(), lessThan(1));
      expect((sen.width - hi.width).abs(), lessThan(1));
      expect(hi.top, greaterThan(par.top), reason: '$reason: Highlight, the primary action, bottom right');
    }

    for (final mode in ['light', 'dark', 'sepia']) {
      testWidgets('text 1.0, 360 dp ($mode): ONE small container, a 2 x 2 grid, compact, centred, 16 dp above the bottom', (tester) async {
        await show(tester, mode, 1.0);
        expect(find.byKey(const ValueKey('selection-toolbar')), findsOneWidget, reason: 'one container for all four');
        expectGrid(tester, reason: mode);
        final box = toolbar(tester);
        for (final k in keys) {
          final rect = r(tester, k);
          expect(rect.left, greaterThanOrEqualTo(box.left));
          expect(rect.right, lessThanOrEqualTo(box.right));
          expect(rect.top, greaterThanOrEqualTo(box.top));
          expect(rect.bottom, lessThanOrEqualTo(box.bottom));
        }
        expect(box.width, lessThanOrEqualTo(260), reason: 'compact: a small card, not a full-width bar');
        expect(box.height, lessThanOrEqualTo(106), reason: 'two rows of 48 dp targets and a little padding');
        expect(box.left, greaterThanOrEqualTo(ReaderSelectionBar.sideMargin - .5));
        expect(360 - box.right, greaterThanOrEqualTo(ReaderSelectionBar.sideMargin - .5));
        expect(((box.left + box.right) / 2 - 180).abs(), lessThan(1), reason: 'centred');
        expect(800 - box.bottom, closeTo(ReaderSelectionBar.bottomGap, 1), reason: 'hovering 16 dp above the bottom edge');
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in scales) {
      for (final mode in ['light', 'dark', 'sepia']) {
        testWidgets('tap targets and no overflow - $mode, text $scale', (tester) async {
          await show(tester, mode, scale);
          final box = toolbar(tester);
          for (final k in keys) {
            final rect = r(tester, k);
            expect(rect.height, greaterThanOrEqualTo(ReaderToolbarPill.tapTarget), reason: '$k: a 48 dp tap target');
            expect(rect.width, greaterThanOrEqualTo(ReaderToolbarPill.tapTarget), reason: '$k: wide enough');
            expect(rect.left, greaterThanOrEqualTo(box.left - .5));
            expect(rect.right, lessThanOrEqualTo(box.right + .5));
            expect(rect.top, greaterThanOrEqualTo(box.top - .5));
            expect(rect.bottom, lessThanOrEqualTo(box.bottom + .5));
            // the visible pill is about 38 dp tall inside that target
            final pill = tester.getRect(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Container)).first);
            if (scale == 1.0) {
              expect(pill.height, ReaderToolbarPill.visualHeight);
            } else {
              expect(pill.height, greaterThanOrEqualTo(ReaderToolbarPill.visualHeight), reason: 'grows with the text, never clips it');
            }
          }
          expect(box.left, greaterThanOrEqualTo(ReaderSelectionBar.sideMargin - .5));
          expect(box.right, lessThanOrEqualTo(360 - ReaderSelectionBar.sideMargin + .5));
          expectGrid(tester, reason: '$mode text $scale: still exactly 2 x 2');
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('text 1.6: still 2 x 2 (never 4 x 1, never a different layout), all inside the one container', (tester) async {
      await show(tester, 'light', 1.6);
      expectGrid(tester, reason: 'text 1.6');
      final tops = {for (final k in keys) r(tester, k).top.round()};
      final lefts = {for (final k in keys) r(tester, k).left.round()};
      expect(tops.length, 2, reason: 'two rows');
      expect(lefts.length, 2, reason: 'two columns');
      expect(find.byKey(const ValueKey('selection-toolbar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow 320 dp phone: still 2 x 2, no overflow', (tester) async {
      await show(tester, 'light', 1.6, width: 320);
      expect(tester.takeException(), isNull);
      expectGrid(tester, reason: '320 dp, text 1.6');
      final box = toolbar(tester);
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(320));
      for (final k in keys) {
        expect(r(tester, k).right, lessThanOrEqualTo(box.right + .5));
      }
    });

    for (final mode in ['light', 'dark', 'sepia']) {
      test('colours ($mode): every label is 4.5:1 on its pill (violet on its tint, red on the toolbar, ink on both gold stops)', () {
        final chrome = kReaderPalettes[mode]!.chrome;
        final look = ReaderToolbarLook.of(chrome);
        final violetPill = compositeOver(argb(look.violetFill), argb(chrome));
        expect(contrastRatio(argb(look.violetText), violetPill), greaterThanOrEqualTo(4.5), reason: '$mode violet text on the violet tint');
        expect(contrastRatio(argb(look.redText), argb(chrome)), greaterThanOrEqualTo(4.5), reason: '$mode soft red text on the toolbar');
        for (final stop in look.gold.colors) {
          expect(contrastRatio(argb(look.goldText), argb(stop)), greaterThanOrEqualTo(4.5), reason: '$mode ink on gold ${stop.toARGB32().toRadixString(16)}');
        }
        // violet really is violet, red really is red (soft), gold is the app's own
        expect(look.violetText.b, greaterThan(look.violetText.g));
        expect(look.redText.r, greaterThan(look.redText.g));
        expect(look.redText.r, greaterThan(look.redText.b));
        expect(look.gold, FolkGradients.saffron);
        expect(look.goldText, FolkColors.onGradient);
      });
    }

    testWidgets('only Highlight is solid: Sentence / Paragraph are tinted, Cancel has no fill', (tester) async {
      await show(tester, 'light', 1.0);
      BoxDecoration deco(String k) => tester.widget<Container>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Container)).first).decoration! as BoxDecoration;
      for (final k in ['sel-sentence', 'sel-paragraph']) {
        expect(deco(k).color, isNotNull, reason: '$k: a light violet tint');
        expect(deco(k).gradient, isNull);
      }
      expect(deco('sel-cancel').color, isNull, reason: 'Cancel: a quiet pill');
      expect(deco('sel-cancel').gradient, isNull);
      expect(deco('sel-highlight').gradient, FolkGradients.saffron, reason: 'Highlight: the theme gold gradient, the primary action');
      expect(deco('sel-highlight').color, isNull);
      // Highlight is the last one, on the right
      expect(r(tester, 'sel-highlight').left, greaterThan(r(tester, 'sel-cancel').left));
    });

    testWidgets('the buttons call back', (tester) async {
      final log = <String>[];
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: bar('light', log: log))));
      await tester.pumpAndSettle();
      for (final k in keys) {
        await tester.tap(find.byKey(ValueKey(k)));
        await tester.pump();
      }
      expect(log, ['sentence', 'paragraph', 'cancel', 'highlight']);
    });

    testWidgets('a quick fade-in (and none with reduce motion); press feedback is the app\'s PressScale', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: bar('light')), reduce: false));
      double opacity() => tester.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('selection-toolbar')), matching: find.byType(Opacity)).first).opacity;
      await tester.pump();
      expect(opacity(), lessThan(1), reason: 'starts transparent');
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(), 1);
      expect(find.descendant(of: find.byKey(const ValueKey('sel-highlight')), matching: find.byType(PressScale)), findsOneWidget);
      final button = find.byKey(const ValueKey('sel-highlight'));
      double scale() => tester.widget<AnimatedScale>(find.descendant(of: button, matching: find.byType(AnimatedScale))).scale;
      final g = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 200));
      expect(scale(), lessThan(1));
      await g.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scale(), 1);
      // reduce motion: shown at once
      await tester.pumpWidget(host(Scaffold(body: bar('light')), reduce: true));
      await tester.pump();
      expect(opacity(), 1);
    });

    testWidgets('the shadow is the only elevation: a soft shadow, a hairline border, no animation beyond the fade', (tester) async {
      await show(tester, 'light', 1.0);
      final deco = tester.widget<Container>(find.byKey(const ValueKey('selection-toolbar'))).decoration! as BoxDecoration;
      expect(deco.boxShadow, hasLength(1));
      expect(deco.boxShadow!.single.blurRadius, greaterThanOrEqualTo(16), reason: 'soft');
      expect(deco.borderRadius, BorderRadius.circular(FolkShape.navRadius), reason: 'the radius of the app\'s floating nav pill');
      expect(deco.color, kReaderPalettes['light']!.chrome, reason: 'the reading mode\'s surface colour');
    });
  });

  // ----------------------------------------------------------------------------------------- the colours
  group('category colours', () {
    test('Good gold, Excellent green, Rare a soft purple that glows a little', () {
      Color c(HighlightCategory x) => Color(x.argb);
      final gold = c(HighlightCategory.good);
      expect(gold.r, greaterThan(gold.g), reason: 'gold: red over green over blue');
      expect(gold.g, greaterThan(gold.b * 3));
      expect(gold.b, lessThan(.1), reason: 'a warm, saturated gold');
      expect(c(HighlightCategory.excellent).g, greaterThan(c(HighlightCategory.excellent).r));
      expect(c(HighlightCategory.rare).b, greaterThan(c(HighlightCategory.rare).g), reason: 'purple');
      expect(c(HighlightCategory.rare).r, greaterThan(c(HighlightCategory.rare).g));
      expect([for (final k in HighlightCategory.values) k.glows], [false, false, true]);
    });

    test('Rare is balanced with the other two: its tint is not heavier, its border not darker than theirs by much', () {
      double tintL(HighlightCategory k, String mode) => luminance(compositeOver(k.tintArgb, kReaderModeColors[mode]!.background));
      for (final mode in ['light', 'dark', 'sepia']) {
        final ls = [for (final k in HighlightCategory.values) tintL(k, mode)];
        final spread = ls.reduce((a, b) => a > b ? a : b) - ls.reduce((a, b) => a < b ? a : b);
        expect(spread, lessThan(mode == 'dark' ? .08 : .12), reason: '$mode: the three tints look about equally strong');
      }
      expect(luminance(HighlightCategory.rare.argb), greaterThan(luminance(0xFF9C4DFF)), reason: 'lighter than the old Rare');
    });

    test('every category stays clearly visible in every mode - the gold Good too, even on sepia (a gold-ish page)', () {
      for (final mode in ['light', 'dark', 'sepia']) {
        final page = kReaderModeColors[mode]!.background;
        for (final k in HighlightCategory.values) {
          expect(contrastRatio(k.argb, page), greaterThanOrEqualTo(2.3), reason: '$mode ${k.label}: the border against the page');
          final tint = compositeOver(k.tintArgb, page);
          expect(contrastRatio(tint, page), greaterThan(1.07), reason: '$mode ${k.label}: the tint is a visible patch on the page');
          expect(contrastRatio(k.argb, tint), greaterThanOrEqualTo(2.0), reason: '$mode ${k.label}: the border against its own tint');
        }
        // Good (gold) against the three modes' backgrounds is not weaker than the other two by much
        double edge(HighlightCategory k) => contrastRatio(k.argb, page);
        final weakest = HighlightCategory.values.map(edge).reduce((a, b) => a < b ? a : b);
        expect(edge(HighlightCategory.good), lessThan(weakest + 3.5), reason: '$mode: balanced, not a different strength');
      }
    });

    test('text stays at 4.5:1 on every tint, in light, dark and sepia', () {
      for (final mode in ['light', 'dark', 'sepia']) {
        final page = kReaderModeColors[mode]!.background;
        for (final cats in [
          for (final k in HighlightCategory.values) {k},
          HighlightCategory.values.toSet(),
        ]) {
          for (final run in <int?>[null, 0xFF000000, 0xFFFFFFFF, 0xFF1D1D1D, 0xFFE0E0E0, 0xFF4B3621, 0xFF000080, 0xFF00FFFF]) {
            final text = readableOnHighlights(run, mode, cats);
            expect(contrastRatio(text, page), greaterThanOrEqualTo(kReaderMinContrast), reason: '$mode $cats $run on the page');
            for (final k in cats) {
              expect(contrastRatio(text, compositeOver(k.tintArgb, page)), greaterThanOrEqualTo(kReaderMinContrast), reason: '$mode $k $run on its tint');
            }
          }
        }
      }
    });
  });

  group('Notes tiles wear the theme gradients', () {
    // (checked on the real screen in books_history_notes_test: Good = saffron / gold, Excellent = green, Rare = violet)
    test('the three gradients are the theme\'s own', () {
      expect(categoryGradient(HighlightCategory.good), FolkGradients.saffron);
      expect(categoryGradient(HighlightCategory.excellent), FolkGradients.green);
      expect(categoryGradient(HighlightCategory.rare), FolkGradients.violet);
    });
  });

  // ----------------------------------------------------------------------------------------- the note jump
  group('jump to a note number', () {
    NoteBook book(int n) => NoteBook(bookId: 'level-1__b', title: 'A Book', entries: [
          for (var i = 1; i <= n; i++)
            NoteEntry(id: 'n$i', level: 'level-1', bookKey: 'b', bookTitle: 'A Book', category: HighlightCategory.good, text: 'Passage number $i', note: '', chapter: 0, paragraph: i, offset: 0, truncated: false),
        ]);

    Future<void> open(WidgetTester tester, {int total = 30, double scale = 1.0, bool dark = false}) async {
      phone(tester, scale);
      await tester.pumpWidget(host(NotesCardsPage(category: HighlightCategory.good, book: book(total)), dark: dark));
      await tester.pumpAndSettle();
    }

    String boxText(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('note-jump-box'))).controller!.text;

    Future<void> type(WidgetTester tester, String v) async {
      await tester.tap(find.byKey(const ValueKey('note-jump-box')));
      await tester.enterText(find.byKey(const ValueKey('note-jump-box')), v);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('the header reads "Note [1] of 30", with the progress bar', (tester) async {
      await open(tester);
      expect(find.text('Note'), findsOneWidget);
      expect(boxText(tester), '1');
      expect(find.textContaining('of 30'), findsOneWidget);
      expect(find.byKey(const ValueKey('notes-progress-bar')), findsOneWidget);
    });

    testWidgets('a valid number jumps to that card, and the box follows swiping', (tester) async {
      await open(tester);
      await type(tester, '7');
      expect(find.byKey(const ValueKey('note-card-7')), findsOneWidget);
      expect(boxText(tester), '7');
      expect(find.text('Passage number 7'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(boxText(tester), '8', reason: 'swiping updates the box');
      await type(tester, '30');
      expect(boxText(tester), '30');
      await type(tester, '1');
      expect(boxText(tester), '1');
      expect(find.byKey(const ValueKey('note-card-1')), findsOneWidget);
    });

    for (final bad in ['0', '31', '999', '']) {
      testWidgets('"$bad": "Enter a note between 1 and 30", and the card stays', (tester) async {
        await open(tester);
        await type(tester, '5');
        await type(tester, bad);
        expect(find.text('Enter a note between 1 and 30'), findsOneWidget);
        expect(boxText(tester), '5', reason: 'the box shows the real card again');
        expect(find.byKey(const ValueKey('note-card-5')), findsOneWidget);
      });
    }

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('header fits without overflow — ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
          await open(tester, scale: scale, dark: dark, total: 120);
          expect(tester.takeException(), isNull);
          final box = tester.getRect(find.byKey(const ValueKey('note-jump-box')));
          expect(box.left, greaterThanOrEqualTo(0));
          expect(box.right, lessThanOrEqualTo(360));
          expect(box.height, greaterThanOrEqualTo(32));
        });
      }
    }
  });

  // ----------------------------------------------------------------------------------------- the loading screen
  group('book loading screen', () {
    Future<void> openLoading(WidgetTester tester, {required bool dark, Map<String, Object?> prefs = const {}, double scale = 1.0, bool reduce = true, String? lastUsed}) async {
      phone(tester, scale);
      ReaderLook.debugReset();
      ReaderLook.theme = lastUsed;
      addTearDown(ReaderLook.debugReset);
      final never = StreamController<BookLoadUpdate>();
      addTearDown(never.close);
      await tester.pumpWidget(host(
        BookReaderPage(
          dropboxUrl: 'https://example.invalid/book.docx?dl=0',
          bookTitle: 'Test Book',
          bookKey: 'book_1',
          level: 'level-1',
          uid: 'u1',
          loader: (u, t) => never.stream,
          extras: () async => <Object?>[null, prefs, false],
        ),
        dark: dark,
        reduce: reduce,
      ));
    }

    Color pageBackground(WidgetTester tester) => tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

    for (final c in [
      (name: 'light', dark: false, prefs: <String, Object?>{}, mode: 'light', last: null as String?),
      (name: 'dark app', dark: true, prefs: <String, Object?>{}, mode: 'dark', last: null),
      (name: 'sepia (last used on this device)', dark: false, prefs: <String, Object?>{'theme': 'sepia'}, mode: 'sepia', last: 'sepia'),
      (name: 'dark reading mode in a light app (last used)', dark: false, prefs: <String, Object?>{'theme': 'dark'}, mode: 'dark', last: 'dark'),
    ]) {
      for (final scale in scales) {
        testWidgets('${c.name}: a ghost in the reading colours, no spinner, no white frame — text $scale', (tester) async {
          await openLoading(tester, dark: c.dark, prefs: c.prefs, scale: scale, lastUsed: c.last);
          // the very first frame, then a few more as the saved mode arrives
          for (var i = 0; i < 4; i++) {
            expect(find.byKey(const ValueKey('reader-loading-ghost')), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            {
              expect(pageBackground(tester), kReaderPalettes[c.mode]!.background, reason: '${c.name} frame $i');
              expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('reader-loading-ghost'))).color, kReaderPalettes[c.mode]!.background);
            }
            if (c.mode != 'light') {
              expect(pageBackground(tester), isNot(Colors.white), reason: 'never a white flash in ${c.mode}');
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(tester.takeException(), isNull);
          expect(find.textContaining('Test Book'), findsOneWidget, reason: 'the title bar is there');
        });
      }
    }

    testWidgets('the ghost is paragraph-shaped (a title bar and lines) and still under reduce motion', (tester) async {
      await openLoading(tester, dark: false, reduce: true);
      await tester.pump();
      final lines = find.descendant(of: find.byKey(const ValueKey('reader-loading-ghost')), matching: find.byType(FractionallySizedBox));
      expect(lines.evaluate().length, greaterThan(20), reason: 'a title bar and many text lines');
      expect(tester.binding.transientCallbackCount, 0, reason: 'nothing animates under reduce motion');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('it breathes when motion is allowed, and stops when the text appears (cross-fade, no layout jump)', (tester) async {
      phone(tester, 1.0);
      final updates = StreamController<BookLoadUpdate>();
      addTearDown(updates.close);
      await tester.pumpWidget(host(
        BookReaderPage(
          dropboxUrl: 'https://example.invalid/book.docx?dl=0',
          bookTitle: 'Test Book',
          bookKey: 'book_1',
          level: 'level-1',
          uid: 'u1',
          loader: (u, t) => updates.stream,
          extras: () async => <Object?>[null, <String, Object?>{'theme': 'sepia'}, false],
        ),
        reduce: false,
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'breathing');
      final before = tester.getRect(find.byKey(const ValueKey('reader-loading-ghost')));
      updates.add(BookLoadUpdate(
        ParsedBook([
          ParsedChapter(
            title: 'Chapter title 1',
            titleRuns: [TextRun('Chapter title 1', bold: true)],
            paragraphs: [
              [const TextRun('A paragraph of the first chapter.')],
            ],
          ),
        ], const {}),
        complete: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      // mid-fade: both are in the same box
      if (find.byKey(const ValueKey('reader-loading-ghost')).evaluate().isNotEmpty) {
        expect(tester.getRect(find.byKey(const ValueKey('reader-loading-ghost'))), before, reason: 'the ghost does not move while it fades');
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-loading-ghost')), findsNothing);
      expect(find.textContaining('Chapter title 1', findRichText: true), findsWidgets);
    });
  });
}
