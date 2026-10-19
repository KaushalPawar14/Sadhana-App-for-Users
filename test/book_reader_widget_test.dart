// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/widgets/ReaderChrome.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/utils/ReaderContrast.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The reader as the student sees it: first chapter first, the Next button waiting
// for the rest, and text that can be read in Light, Dark and Sepia.
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

ParsedChapter chapter(int n, {int paragraphs = 3}) => ParsedChapter(
      title: 'Chapter title $n',
      titleRuns: [TextRun('Chapter title $n', bold: true)],
      paragraphs: [
        for (var p = 0; p < paragraphs; p++)
          [
            TextRun('Paragraph $p of $n black. ', color: 0xFF000000),
            const TextRun('navy words ', color: 0xFF000080, bold: true),
            const TextRun('cyan words ', color: 0xFF00FFFF),
            const TextRun('plain default words.'),
          ],
      ],
    );

ParsedBook book(int chapters) => ParsedBook([for (var i = 1; i <= chapters; i++) chapter(i)], const {});

Widget host(Widget reader, {bool reduce = true}) => MaterialApp(
      theme: FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: reader,
    );

BookReaderPage reader(Stream<BookLoadUpdate> Function(String, String) loader) => BookReaderPage(
      dropboxUrl: 'https://example.invalid/book.docx?dl=0',
      bookTitle: 'Test Book',
      bookKey: 'book_1',
      level: 'level-1',
      uid: 'u1',
      loader: loader,
      // no bookmark, default preferences, not finished
      extras: () async => <Object?>[null, <String, Object?>{}, false],
    );

// Every text run drawn in the paragraphs, with its colour.
List<TextSpan> runsOnScreen(WidgetTester tester) {
  final out = <TextSpan>[];
  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    rt.text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').isNotEmpty && span.style?.fontFamily == 'serif') out.add(span);
      return true;
    });
  }
  return out;
}

Future<void> pickMode(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Reading settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(10, 10)); // close the sheet
  await tester.pumpAndSettle();
}

/// The chapter header reads "Chapter [n] of total": a typeable box with the number.
void expectChapter(WidgetTester tester, int n, int? total) {
  final field = find.descendant(of: find.byType(ReaderChapterStrip), matching: find.byType(TextField));
  expect(field, findsOneWidget);
  expect(tester.widget<TextField>(field).controller!.text, '$n', reason: 'the box shows the chapter on screen');
  expect(find.descendant(of: find.byType(ReaderChapterStrip), matching: find.text('Chapter')), findsOneWidget);
  if (total == null) {
    expect(find.descendant(of: find.byType(ReaderChapterStrip), matching: find.textContaining('of ')), findsNothing);
  } else {
    expect(find.descendant(of: find.byType(ReaderChapterStrip), matching: find.text('of $total')), findsOneWidget);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('the first chapter shows while the rest is still being read; the next arrow waits, then works', (tester) async {
    phone(tester, 1.0);
    final controller = StreamController<BookLoadUpdate>();
    await tester.pumpWidget(host(reader((u, t) => controller.stream)));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-loading-ghost')), findsOneWidget, reason: 'nothing yet: the ghost of the page, no spinner');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    controller.add(BookLoadUpdate(ParsedBook([chapter(1)], const {}), complete: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Chapter title 1', findRichText: true), findsWidgets, reason: 'the first chapter is on screen');
    expectChapter(tester, 1, null);
    expect(find.bySemanticsLabel('Loading next chapter'), findsOneWidget, reason: 'the right arrow shows a spinner');
    expect(find.byTooltip('Next chapter'), findsNothing);
    expect(find.text('Next Chapter  →'), findsNothing);
    expect(tester.takeException(), isNull);

    controller.add(BookLoadUpdate(book(3), complete: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expectChapter(tester, 1, 3);
    expect(find.byTooltip('Next chapter'), findsOneWidget);
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expectChapter(tester, 2, 3);
    unawaited(controller.close());
  });

  test('the reader palettes and the colour rule use the same three modes', () {
    for (final mode in ['light', 'dark', 'sepia']) {
      final palette = kReaderPalettes[mode]!;
      final colours = kReaderModeColors[mode]!;
      expect(palette.background.toARGB32(), colours.background, reason: mode);
      expect(palette.text.toARGB32(), colours.text, reason: mode);
      expect(palette.secondaryText.toARGB32(), colours.secondaryText, reason: mode);
      expect(palette.onChrome.toARGB32(), colours.onChrome, reason: mode);
    }
  });

  testWidgets('a book that cannot be read shows the error, not a spinner forever', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(reader((u, t) => Stream<BookLoadUpdate>.error(StateError('bad')))));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not open this book.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an empty result is an error too', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(reader((u, t) => const Stream<BookLoadUpdate>.empty())));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not open this book.'), findsOneWidget);
  });

  for (final scale in scales) {
    for (final mode in ['Light', 'Dark', 'Sepia']) {
      testWidgets('$mode, text scale $scale: no overflow, and every run reaches 4.5:1 on its background', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(host(reader((u, t) => Stream.value(BookLoadUpdate(book(2), complete: true)))));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        if (mode != 'Light') await pickMode(tester, mode);
        expect(tester.takeException(), isNull, reason: '$mode $scale');

        final bg = kReaderModeColors[mode.toLowerCase()]!.background;
        final runs = runsOnScreen(tester);
        expect(runs, isNotEmpty);
        var checked = 0;
        for (final r in runs) {
          if (r.text!.trim().isEmpty) continue;
          // heading banner runs are not in this fixture; everything sits on the page colour
          final c = r.style!.color!.toARGB32();
          expect(contrastRatio(c, bg), greaterThanOrEqualTo(4.5), reason: '"${r.text}" in $mode (colour ${c.toRadixString(16)})');
          checked++;
        }
        expect(checked, greaterThan(10));
      });
    }
  }

  testWidgets('Dark: authored black text is drawn in the mode text colour; a colour that already reads is kept', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(reader((u, t) => Stream.value(BookLoadUpdate(book(1), complete: true)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await pickMode(tester, 'Dark');
    final runs = runsOnScreen(tester);
    final black = runs.firstWhere((r) => r.text!.contains('black'));
    expect(black.style!.color!.toARGB32(), kReaderModeColors['dark']!.text);
    final cyan = runs.firstWhere((r) => r.text!.contains('cyan'));
    expect(cyan.style!.color!.toARGB32(), 0xFF00FFFF, reason: 'cyan reads on a dark page, so it is kept');
    final navy = runs.firstWhere((r) => r.text!.contains('navy'));
    expect(navy.style!.color!.toARGB32(), isNot(0xFF000080), reason: 'navy on near-black is unreadable');
    expect(navy.style!.fontWeight, FontWeight.bold, reason: 'only the colour changes, not the formatting');
  });

  testWidgets('Light: cyan text (unreadable on white) is fixed, black is untouched', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(reader((u, t) => Stream.value(BookLoadUpdate(book(1), complete: true)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final runs = runsOnScreen(tester);
    expect(runs.firstWhere((r) => r.text!.contains('black')).style!.color!.toARGB32(), 0xFF000000);
    final cyan = runs.firstWhere((r) => r.text!.contains('cyan')).style!.color!.toARGB32();
    expect(contrastRatio(cyan, 0xFFFFFFFF), greaterThanOrEqualTo(4.5));
    final plain = runs.firstWhere((r) => r.text!.contains('plain default'));
    expect(plain.style!.color!.toARGB32(), kReaderDefaultTextArgb);
  });

  testWidgets('a shaded heading banner: its text is readable on the banner, in every mode', (tester) async {
    phone(tester, 1.0);
    final banner = ParsedChapter(
      title: 'Banner',
      titleRuns: const [TextRun('Banner heading', color: 0xFF800000, bold: true)], // maroon on teal: unreadable
      titleDecoration: const ParsedDecoration(fill: 0xFF008080, centered: true),
      paragraphs: [
        [const TextRun('body text')]
      ],
    );
    await tester.pumpWidget(host(reader((u, t) => Stream.value(BookLoadUpdate(ParsedBook([banner], const {}), complete: true)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (final mode in ['Light', 'Dark', 'Sepia']) {
      if (mode != 'Light') await pickMode(tester, mode);
      final run = runsOnScreen(tester).firstWhere((r) => r.text == 'Banner heading');
      expect(contrastRatio(run.style!.color!.toARGB32(), 0xFF008080), greaterThanOrEqualTo(4.5), reason: mode);
    }
  });
}
