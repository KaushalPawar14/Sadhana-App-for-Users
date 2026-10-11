// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/widgets/ReaderChrome.dart';

import 'book_reader_navigation_test.dart' show bookOf, scrollOf;
import 'book_reader_widget_test.dart' show phone, host;
import 'text_scale_test.dart' show scales, loadAppFonts;

// Bookmarking must never move the text: entering bookmark mode, picking a paragraph
// and leaving the mode keep the paragraph at the top of the screen exactly where it
// is (and the scroll offset unchanged).

BookReaderPage readerWith({String theme = 'light', int? bookmarkParagraph}) => BookReaderPage(
      dropboxUrl: 'https://example.invalid/book.docx?dl=0',
      bookTitle: 'Test Book',
      bookKey: 'book_1',
      level: 'level-1',
      uid: 'u1',
      loader: (u, t) => Stream.value(BookLoadUpdate(bookOf([80, 20]), complete: true)),
      extras: () async => <Object?>[
        bookmarkParagraph == null ? null : <String, int>{'chapter': 0, 'paragraph': bookmarkParagraph},
        <String, Object?>{'theme': theme},
        false,
      ],
    );

Finder para(int p) => find.textContaining('Paragraph $p of 1 ', findRichText: true);

Future<void> open(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(host(w));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The paragraph that is first below the chapter strip, found once.
int topParagraph(WidgetTester tester) {
  final top = tester.getBottomLeft(find.byType(ReaderChapterStrip)).dy;
  int? best;
  double bestGap = double.infinity;
  for (var p = 0; p < 80; p++) {
    if (para(p).evaluate().isEmpty) continue;
    final gap = tester.getTopLeft(para(p)).dy - top;
    if (gap >= 0 && gap < bestGap) {
      bestGap = gap;
      best = p;
    }
  }
  return best!;
}

/// Where a paragraph is on screen, and how far the page is scrolled.
({double y, double x, double offset}) where(WidgetTester tester, int p) {
  final tl = tester.getTopLeft(para(p));
  return (y: tl.dy, x: tl.dx, offset: scrollOf(tester).pixels);
}

void expectStill(WidgetTester tester, int p, ({double y, double x, double offset}) before, String step) {
  final now = where(tester, p);
  expect(now.offset, closeTo(before.offset, 1), reason: '$step: scroll offset moved');
  expect(now.y, closeTo(before.y, 1), reason: '$step: paragraph $p moved on screen (${before.y} -> ${now.y})');
  expect(now.x, closeTo(before.x, 1), reason: '$step: paragraph $p moved sideways (${before.x} -> ${now.x})');
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> scrollHalf(WidgetTester tester) async {
  final pos = scrollOf(tester);
  pos.jumpTo(pos.maxScrollExtent * .5);
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  for (final scale in scales) {
    for (final theme in ['light', 'dark', 'sepia']) {
      testWidgets('$theme, text scale $scale: entering bookmark mode, picking a paragraph and leaving it keep the text still', (tester) async {
        phone(tester, scale);
        await open(tester, readerWith(theme: theme));
        await scrollHalf(tester);
        final anchor = topParagraph(tester);
        final start = where(tester, anchor);
        expect(start.offset, greaterThan(100), reason: 'mid-chapter');

        // 1. tap the bookmark icon: bookmark mode on
        await tester.tap(find.byTooltip('Add a bookmark'));
        await settle(tester);
        expect(find.text('Tap a paragraph to bookmark'), findsOneWidget, reason: 'bookmark mode is on');
        expectStill(tester, anchor, start, 'entering bookmark mode');

        // 2. tap a visible paragraph: it is chosen (the write has no database here, so the mode ends)
        await tester.tap(para(anchor + 2));
        await settle(tester);
        expectStill(tester, anchor, start, 'tapping a paragraph');

        // 3. leave the mode if it is still on (Cancel), and check again
        if (find.byTooltip('Cancel').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Cancel'));
          await settle(tester);
        }
        expect(find.text('Tap a paragraph to bookmark'), findsNothing, reason: 'bookmark mode is off');
        expectStill(tester, anchor, start, 'leaving bookmark mode');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in scales) {
    testWidgets('text scale $scale: cancelling bookmark mode straight away keeps the text still', (tester) async {
      phone(tester, scale);
      await open(tester, readerWith());
      await scrollHalf(tester);
      final anchor = topParagraph(tester);
      final start = where(tester, anchor);
      await tester.tap(find.byTooltip('Add a bookmark'));
      await settle(tester);
      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester);
      expectStill(tester, anchor, start, 'cancel');
    });
  }

  testWidgets('a bookmarked paragraph takes exactly the room of any other (setting or moving a bookmark moves nothing)', (tester) async {
    phone(tester, 1.3);
    await open(tester, readerWith(bookmarkParagraph: 3));
    final h3 = tester.getSize(para(3)).height;
    final h4 = tester.getSize(para(4)).height;
    expect(h3, closeTo(h4, .5), reason: 'the bookmarked paragraph is not padded');
    final gap = tester.getTopLeft(para(4)).dy - tester.getTopLeft(para(3)).dy;
    final gapNext = tester.getTopLeft(para(5)).dy - tester.getTopLeft(para(4)).dy;
    expect(gap, closeTo(gapNext, 1), reason: 'same spacing around the bookmarked paragraph');
    expect(tester.getTopLeft(para(3)).dx, closeTo(tester.getTopLeft(para(4)).dx, .5), reason: 'same text column');
  });

  testWidgets('the chapter strip and the title bar keep their height when a bookmark exists or bookmark mode is on', (tester) async {
    for (final scale in [1.0, 1.6]) {
      phone(tester, scale);
      await tester.pumpWidget(const SizedBox()); // a fresh reader each round
      await open(tester, readerWith());
      final strip = tester.getSize(find.byType(ReaderChapterStrip)).height;
      final bar = tester.getSize(find.byType(AppBar)).height;
      await tester.tap(find.byTooltip('Add a bookmark'));
      await settle(tester);
      expect(tester.getSize(find.byType(ReaderChapterStrip)).height, strip, reason: 'strip, scale $scale');
      expect(tester.getSize(find.byType(AppBar)).height, bar, reason: 'title bar, scale $scale');

      await tester.pumpWidget(const SizedBox()); // a fresh reader, not the same state
      await open(tester, readerWith(bookmarkParagraph: 12));
      expect(tester.getSize(find.byType(ReaderChapterStrip)).height, strip, reason: 'strip with a saved bookmark, scale $scale');
      expect(find.textContaining('Saved at ch 1'), findsOneWidget);
    }
  });

  testWidgets('scroll-to-bookmark still runs when the book opens', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerWith(bookmarkParagraph: 60));
    await tester.pumpAndSettle();
    expect(scrollOf(tester).pixels, greaterThan(500), reason: 'opened at the bookmark, not at the top');
    expect(find.textContaining('Paragraph 60 of 1 ', findRichText: true), findsOneWidget);
  });

  test('the bookmark code never scrolls: only opening the book and the explicit jump do', () {
    final src = File('lib/pages/BookReaderPage.dart').readAsStringSync();
    expect(RegExp(r'_scrollToBookmarkedParagraph\(\)').allMatches(src).length, 2, reason: 'definition + the one call after the book opens');
    final tile = src.substring(src.indexOf('Widget _paragraphTile'), src.indexOf('Widget build(BuildContext context)'));
    expect(tile.contains('Padding('), isFalse, reason: 'a paragraph tile never changes its own size');
  });
}
