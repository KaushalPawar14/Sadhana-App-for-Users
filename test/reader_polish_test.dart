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
  group('selection bar: 2 x 2 compact pills in the app\'s button style', () {
    Widget bar(String mode, {List<String>? log}) => Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ReaderSelectionBar(
              background: kReaderPalettes[mode]!.chrome,
              onSentence: () => log?.add('sentence'),
              onParagraph: () => log?.add('paragraph'),
              onCancel: () => log?.add('cancel'),
              onHighlight: () => log?.add('highlight'),
            ),
          ),
        );

    for (final mode in ['light', 'dark', 'sepia']) {
      for (final scale in scales) {
        testWidgets('layout, compact 44 dp targets, no overflow — $mode, text $scale', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host(Scaffold(backgroundColor: kReaderPalettes[mode]!.background, body: bar(mode)), dark: mode == 'dark'));
          await tester.pumpAndSettle();
          Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
          final s = r('sel-sentence'), p = r('sel-paragraph'), c = r('sel-cancel'), h = r('sel-highlight');
          expect((s.top - p.top).abs(), lessThan(1), reason: 'Sentence and Paragraph share the top row');
          expect((c.top - h.top).abs(), lessThan(1), reason: 'Cancel and Highlight share the bottom row');
          expect(c.top, greaterThanOrEqualTo(s.bottom), reason: 'the second row is below');
          expect(s.left, lessThan(p.left));
          expect(c.left, lessThan(h.left), reason: 'Cancel left, Highlight right');
          expect((s.left - c.left).abs(), lessThan(1), reason: 'the columns line up');
          for (final rect in [s, p, c, h]) {
            expect(rect.height, greaterThanOrEqualTo(ReaderPillButton.minHeight), reason: 'a 44 dp tap target at least');
            expect(rect.width, greaterThanOrEqualTo(ReaderPillButton.minHeight));
            expect(rect.right, lessThanOrEqualTo(360));
          }
          expect(ReaderPillButton.minHeight, inInclusiveRange(44, 48));
          if (scale == 1.0) {
            expect(s.height, 44, reason: 'compact at the normal text size');
            final bar = tester.getRect(find.byType(ReaderSelectionBar));
            expect(bar.height, lessThanOrEqualTo(112), reason: 'the bar takes little vertical space (it was 128 dp)');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    test('the colours: the theme violet and saffron gradients and a soft medium red; the ink label is readable on every stop', () {
      expect(ReaderPillTone.purple.gradient, FolkGradients.violet, reason: 'Sentence + Paragraph: the theme violet');
      expect(ReaderPillTone.gold.gradient, FolkGradients.saffron, reason: 'Highlight: the theme saffron / gold');
      for (final tone in ReaderPillTone.values) {
        expect(tone.label, FolkColors.onGradient, reason: 'the ink colour on every gradient, like the other gradient tiles');
        for (final stop in tone.gradient.colors) {
          expect(contrastRatio(argb(tone.label), argb(stop)), greaterThanOrEqualTo(4.5), reason: '$tone label on ${stop.toARGB32().toRadixString(16)}');
        }
        expect(tone.gradient.colors.first.computeLuminance(), greaterThan(tone.gradient.colors.last.computeLuminance()), reason: 'light to deeper');
      }
      final purple = ReaderPillTone.purple.gradient.colors.last;
      expect(purple.b, greaterThan(purple.g));
      expect(purple.r, lessThan(purple.b), reason: 'violet');
      for (final red in ReaderPillTone.red.gradient.colors) {
        expect(red.r * 255, greaterThan(220), reason: 'a red family: red dominant');
        expect(red.g, lessThan(red.r), reason: 'red, not orange or pink');
        expect(red.g * 255, lessThan(200));
      }
      expect(ReaderPillTone.red.gradient.colors.last.g * 255, lessThan(140), reason: 'medium, not a pastel pink');
      final gold = ReaderPillTone.gold.gradient.colors.last;
      expect(gold.r * 255, greaterThan(240));
      expect(gold.g * 255, inInclusiveRange(150, 210), reason: 'golden');
      expect(gold.b * 255, lessThan(120));
    });

    testWidgets('the buttons are the app\'s: pill radius, chip typography, a soft shadow only', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: bar('light'))));
      await tester.pumpAndSettle();
      for (final k in ['sel-sentence', 'sel-paragraph', 'sel-cancel', 'sel-highlight']) {
        final container = tester.widget<Container>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Container)).first);
        final deco = container.decoration! as BoxDecoration;
        expect(deco.borderRadius, BorderRadius.circular(FolkShape.buttonRadius), reason: 'the same radius as the other buttons');
        expect(deco.border, isNull, reason: 'no outline: less bulky');
        expect(deco.boxShadow, hasLength(1));
        expect(deco.boxShadow!.single.blurRadius, lessThanOrEqualTo(8));
        expect(deco.boxShadow!.single.color.a, lessThanOrEqualTo(.2), reason: 'soft');
        final label = tester.widget<Text>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Text)));
        expect(label.style!.fontSize, 14);
        expect(label.style!.fontWeight, FontWeight.w700);
        expect(label.style!.color, FolkColors.onGradient);
      }
    });

    testWidgets('the buttons call back; the colours are the same in every reading mode', (tester) async {
      final log = <String>[];
      phone(tester, 1.0);
      for (final mode in ['light', 'dark', 'sepia']) {
        await tester.pumpWidget(host(Scaffold(body: bar(mode, log: log)), dark: mode == 'dark'));
        await tester.pumpAndSettle();
        final gradients = [
          for (final k in ['sel-sentence', 'sel-paragraph', 'sel-cancel', 'sel-highlight'])
            (tester.widget<Container>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Container)).first).decoration! as BoxDecoration).gradient
        ];
        expect(gradients[0], ReaderPillTone.purple.gradient);
        expect(gradients[1], ReaderPillTone.purple.gradient);
        expect(gradients[2], ReaderPillTone.red.gradient);
        expect(gradients[3], ReaderPillTone.gold.gradient);
      }
      for (final k in ['sel-sentence', 'sel-paragraph', 'sel-cancel', 'sel-highlight']) {
        await tester.tap(find.byKey(ValueKey(k)));
        await tester.pump();
      }
      expect(log, ['sentence', 'paragraph', 'cancel', 'highlight']);
    });

    testWidgets('press feedback is the app\'s PressScale: it sinks while pressed and comes back', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: bar('light')), reduce: false));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('sel-highlight'));
      double scale() => tester.widget<AnimatedScale>(find.descendant(of: button, matching: find.byType(AnimatedScale))).scale;
      expect(find.descendant(of: button, matching: find.byType(PressScale)), findsOneWidget);
      expect(scale(), 1);
      final g = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 200));
      expect(scale(), lessThan(1));
      await g.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scale(), 1);
    });

    testWidgets('reduce motion: no scale at all', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Scaffold(body: bar('light')), reduce: true));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('sel-cancel'));
      final g = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedScale>(find.descendant(of: button, matching: find.byType(AnimatedScale))).scale, 1);
      await g.up();
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
