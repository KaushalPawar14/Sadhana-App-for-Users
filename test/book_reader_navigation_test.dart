// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/widgets/ReaderChrome.dart';

import 'book_reader_widget_test.dart' show phone, chapter, host, expectChapter;
import 'text_scale_test.dart' show scales, loadAppFonts;

// The reader's chapter arrows, the bottom progress bar and the Finish Book area.

ParsedBook bookOf(List<int> paragraphsPerChapter) => ParsedBook([
      for (var i = 0; i < paragraphsPerChapter.length; i++) chapter(i + 1, paragraphs: paragraphsPerChapter[i]),
    ], const {});

BookReaderPage readerOf(ParsedBook b, {bool finished = false, String theme = 'light'}) => BookReaderPage(
      dropboxUrl: 'https://example.invalid/book.docx?dl=0',
      bookTitle: 'Test Book',
      bookKey: 'book_1',
      level: 'level-1',
      uid: 'u1',
      loader: (u, t) => Stream.value(BookLoadUpdate(b, complete: true)),
      extras: () async => <Object?>[null, <String, Object?>{'theme': theme}, finished],
    );

Future<void> open(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(host(w));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

ScrollPosition scrollOf(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable)).first)
    .position;

double progressOf(WidgetTester tester) => tester.widget<ReaderProgressBar>(find.byType(ReaderProgressBar)).progress;

Future<void> scrollTo(WidgetTester tester, double fraction) async {
  final pos = scrollOf(tester);
  pos.jumpTo(pos.maxScrollExtent * fraction);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

double arrowOpacity(WidgetTester tester, String tooltip) {
  final op = find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(Opacity));
  return tester.widget<Opacity>(op.first).opacity;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('chapter arrows: 48 dp targets, faded at the ends, change the chapter and scroll to the top', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([40, 40, 40])));
    expectChapter(tester, 1, 3);
    expect(arrowOpacity(tester, 'Previous chapter'), lessThan(1), reason: 'first chapter: left arrow faded');
    expect(arrowOpacity(tester, 'Next chapter'), 1);
    for (final tip in ['Previous chapter', 'Next chapter']) {
      final size = tester.getSize(find.ancestor(of: find.byTooltip(tip), matching: find.byType(SizedBox)).first);
      expect(size.width, greaterThanOrEqualTo(48), reason: tip);
      expect(size.height, greaterThanOrEqualTo(48), reason: tip);
    }
    await tester.tap(find.byTooltip('Previous chapter'));
    await tester.pump();
    expectChapter(tester, 1, 3);

    await scrollTo(tester, .6);
    expect(scrollOf(tester).pixels, greaterThan(0));
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expectChapter(tester, 2, 3);
    expect(scrollOf(tester).pixels, 0, reason: 'a chapter change starts at the top');
    expect(progressOf(tester), 0);
    expect(arrowOpacity(tester, 'Previous chapter'), 1);

    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expectChapter(tester, 3, 3);
    expect(arrowOpacity(tester, 'Next chapter'), lessThan(1), reason: 'last chapter: right arrow faded');
    await tester.tap(find.byTooltip('Previous chapter'));
    await tester.pumpAndSettle();
    expectChapter(tester, 2, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('there is no Next Chapter button any more', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([40, 40])));
    expect(find.textContaining('Next Chapter'), findsNothing);
    expect(find.text('Finish Book'), findsNothing, reason: 'not on a middle chapter');
  });

  testWidgets('the bottom bar follows the scroll position of the current chapter, 0 to 100 %', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([60, 60])));
    expect(find.byType(ReaderProgressBar), findsOneWidget);
    expect(progressOf(tester), 0);
    expect(find.text('0%'), findsOneWidget);

    await scrollTo(tester, .5);
    expect(progressOf(tester), closeTo(.5, .01));
    expect(find.text('50%'), findsOneWidget);

    await scrollTo(tester, 1);
    expect(progressOf(tester), 1);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expect(progressOf(tester), 0, reason: 'a new chapter starts at 0 %');
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('a chapter too short to scroll counts as 100 %', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([1, 60])));
    expect(scrollOf(tester).maxScrollExtent, lessThanOrEqualTo(1));
    expect(progressOf(tester), 1);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('the page has room under the last line for the bar', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([60, 60])));
    final padded = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final bar = tester.getSize(find.byType(ReaderProgressBar)).height;
    expect((padded.padding as EdgeInsets).bottom, greaterThanOrEqualTo(bar));
    await scrollTo(tester, 1);
    final lastParagraph = tester.getRect(find.textContaining('Paragraph 59 of 1', findRichText: true).first);
    final barTop = tester.getTopLeft(find.byType(ReaderProgressBar)).dy;
    expect(lastParagraph.bottom, lessThanOrEqualTo(barTop), reason: 'the last lines are not hidden by the bar');
  });

  testWidgets('Finish Book appears only on the last chapter, only at 100 %, just above the bar', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([60, 60])));
    expect(find.text('Finish Book'), findsNothing);
    await scrollTo(tester, 1);
    expect(find.text('Finish Book'), findsNothing, reason: 'chapter 1 of 2 is not the last');

    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expect(find.text('Finish Book'), findsNothing, reason: 'last chapter, not read yet');
    await scrollTo(tester, .5);
    expect(find.text('Finish Book'), findsNothing);
    await scrollTo(tester, 1);
    await tester.pump();
    await tester.pump();
    expect(find.text('Finish Book'), findsOneWidget);
    final button = tester.getRect(find.text('Finish Book'));
    final bar = tester.getRect(find.byType(ReaderProgressBar));
    expect(button.bottom, lessThanOrEqualTo(bar.top), reason: 'above the bar');
    expect(bar.top - button.bottom, lessThan(40), reason: 'just above it');
    expect(progressOf(tester), 1, reason: 'the area appearing keeps the end in view');
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // scrolling back up does not make the button flicker away
    await scrollTo(tester, .9);
    expect(find.text('Finish Book'), findsOneWidget);

    // tapping starts the same completion write (_finishBook: the button goes into its busy state;
    // there is no database in a widget test, so it never completes)
    await tester.tap(find.text('Finish Book'));
    await tester.pump();
    expect(find.descendant(of: find.byType(ReaderGradientButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
  });

  testWidgets('a short last chapter shows Finish Book straight away (it counts as read)', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([60, 1])));
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.text('Finish Book'), findsOneWidget);
  });

  testWidgets('an already finished book keeps the Finished banner and gets no Finish button', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf([60]), finished: true));
    expect(find.text('Finish Book'), findsNothing);
    await scrollTo(tester, 1);
    await tester.pump();
    await tester.pump();
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Marked as finished'), findsOneWidget);
    expect(find.text('Finish Book'), findsNothing);
  });

  testWidgets('RDUA: "Mark as Read" instead of "Finish Book"', (tester) async {
    phone(tester, 1.0);
    final page = BookReaderPage(
      dropboxUrl: 'https://example.invalid/x.docx?dl=0',
      bookTitle: 'Topic',
      bookKey: '1',
      level: 'topic_1',
      uid: 'u1',
      isRdua: true,
      loader: (u, t) => Stream.value(BookLoadUpdate(bookOf([60, 60]), complete: true)),
      extras: () async => <Object?>[null, <String, Object?>{}, false],
    );
    await open(tester, page);
    expect(find.byTooltip('Chapter title 2'), findsOneWidget, reason: 'the RDUA arrow names the real next chapter');
    await tester.tap(find.byTooltip('Chapter title 2'));
    await tester.pumpAndSettle();
    await scrollTo(tester, 1);
    await tester.pump();
    await tester.pump();
    expect(find.text('Mark as Read'), findsOneWidget);
  });

  for (final scale in scales) {
    for (final theme in ['light', 'dark', 'sepia']) {
      testWidgets('$theme, text scale $scale on 360 dp: header, bar and finish area do not overflow', (tester) async {
        phone(tester, scale);
        await open(tester, readerOf(bookOf([60, 60]), theme: theme));
        expect(tester.takeException(), isNull);
        await scrollTo(tester, .4);
        await tester.tap(find.byTooltip('Next chapter'));
        await tester.pumpAndSettle();
        await scrollTo(tester, 1);
        await tester.pump();
        await tester.pump();
        expect(find.text('Finish Book'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$theme $scale');
        final screen = tester.view.physicalSize;
        for (final f in [find.byType(ReaderChapterStrip), find.byType(ReaderProgressBar)]) {
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(screen.width));
          expect(r.bottom, lessThanOrEqualTo(screen.height));
        }
        // the finish button stays on screen and clear of the bar
        final b = tester.getRect(find.text('Finish Book'));
        expect(b.right, lessThanOrEqualTo(screen.width));
        expect(b.bottom, lessThanOrEqualTo(tester.getTopLeft(find.byType(ReaderProgressBar)).dy));
        // the page is still readable under the overlays: the first visible text starts below the header
        expect(b.top, greaterThan(tester.getBottomLeft(find.byType(ReaderChapterStrip)).dy));
      });
    }
  }

  testWidgets('reduce motion: the bar jumps to its value, no animation', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(readerOf(bookOf([60])), reduce: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await scrollTo(tester, .5);
    final fill = tester.widget<FractionallySizedBox>(find.descendant(of: find.byType(ReaderProgressBar), matching: find.byType(FractionallySizedBox)));
    expect(fill.widthFactor, closeTo(.5, .02), reason: 'no tween under reduce motion');
  });

  test('the completion write is the same _finishBook as before', () {
    // reading the source is enough: the write block and its fields are unchanged
    final src = File('lib/pages/BookReaderPage.dart').readAsStringSync();
    for (final needle in ["'endDate': today", "'finishedViaButton': true", "'isCurrentBook': false", "'isRead': true", "Future<void> _finishBook()"]) {
      expect(src.contains(needle), isTrue, reason: needle);
    }
    expect(src.contains('Next Chapter  →'), isFalse);
  });
}
