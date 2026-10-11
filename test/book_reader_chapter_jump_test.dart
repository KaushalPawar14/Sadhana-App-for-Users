// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/widgets/ReaderChrome.dart';

import 'book_reader_navigation_test.dart' show bookOf, readerOf, open, scrollOf, scrollTo;
import 'book_reader_widget_test.dart' show phone, chapter, host, expectChapter, reader;
import 'text_scale_test.dart' show scales, loadAppFonts;

// "Chapter [6] of 38": the number is a typeable box that jumps to a chapter.

Finder get box => find.descendant(of: find.byType(ReaderChapterStrip), matching: find.byType(TextField));

Future<void> typeAndDone(WidgetTester tester, String value) async {
  await tester.tap(box);
  await tester.pump();
  await tester.enterText(box, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('the number is a visible, typeable box with a numeric keyboard', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf(List.filled(38, 6))));
    expectChapter(tester, 1, 38);
    final field = tester.widget<TextField>(box);
    expect(field.keyboardType, TextInputType.number);
    expect(field.textInputAction, TextInputAction.done);
    final border = field.decoration!.enabledBorder as OutlineInputBorder;
    expect(border.borderSide.width, greaterThan(0), reason: 'a thin border: it looks typeable');
    expect(field.decoration!.filled, isTrue);
    expect(tester.getSize(box).height, greaterThanOrEqualTo(30));
    expect(tester.getSize(find.byType(ReaderChapterStrip)).height, greaterThanOrEqualTo(48));
    // letters never get in
    await tester.tap(box);
    await tester.enterText(box, 'a1b2');
    expect(tester.widget<TextField>(box).controller!.text, '12');
  });

  testWidgets('type 6 and press Done: the top of chapter 6, the box shows 6, the arrows follow', (tester) async {
    phone(tester, 1.0);
    await open(tester, readerOf(bookOf(List.filled(38, 40))));
    await scrollTo(tester, .5);
    expect(scrollOf(tester).pixels, greaterThan(0));
    await typeAndDone(tester, '6');
    expectChapter(tester, 6, 38);
    expect(scrollOf(tester).pixels, 0, reason: 'the top of the chapter');
    expect(find.textContaining('Chapter title 6', findRichText: true), findsWidgets);
    // an arrow tap updates the box too
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pumpAndSettle();
    expectChapter(tester, 7, 38);
    await tester.tap(find.byTooltip('Previous chapter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous chapter'));
    await tester.pumpAndSettle();
    expectChapter(tester, 5, 38);
    // the first and the last
    await typeAndDone(tester, '38');
    expectChapter(tester, 38, 38);
    await typeAndDone(tester, '1');
    expectChapter(tester, 1, 38);
  });

  for (final bad in ['0', '39', '999', '']) {
    testWidgets('"$bad" is refused: "Enter a chapter between 1 and 38", and the reader stays', (tester) async {
      phone(tester, 1.0);
      await open(tester, readerOf(bookOf(List.filled(38, 40))));
      await typeAndDone(tester, '4');
      expectChapter(tester, 4, 38);
      await scrollTo(tester, .4);
      final where = scrollOf(tester).pixels;
      await typeAndDone(tester, bad);
      expect(find.text('Enter a chapter between 1 and 38'), findsOneWidget);
      expectChapter(tester, 4, 38);
      expect(scrollOf(tester).pixels, where, reason: 'nothing moved');
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('a chapter that is still being read: the loading state, then the jump', (tester) async {
    phone(tester, 1.0);
    final controller = StreamController<BookLoadUpdate>();
    await tester.pumpWidget(host(reader((u, t) => controller.stream)));
    await tester.pump();
    controller.add(BookLoadUpdate(ParsedBook([chapter(1), chapter(2)], const {}), complete: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expectChapter(tester, 1, null);
    await typeAndDone(tester, '5');
    expect(find.text('Enter a chapter between 1 and 2'), findsNothing, reason: 'not an error: it is still loading');
    expect(find.bySemanticsLabel('Loading next chapter'), findsOneWidget, reason: 'the existing loading state');
    expectChapter(tester, 1, null);
    // more of the book arrives, still not enough
    controller.add(BookLoadUpdate(ParsedBook([for (var i = 1; i <= 4; i++) chapter(i)], const {}), complete: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expectChapter(tester, 1, null);
    expect(find.bySemanticsLabel('Loading next chapter'), findsOneWidget);
    // chapter 5 is there: the jump
    controller.add(BookLoadUpdate(ParsedBook([for (var i = 1; i <= 8; i++) chapter(i)], const {}), complete: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expectChapter(tester, 5, 8);
    expect(find.bySemanticsLabel('Loading next chapter'), findsNothing);
    unawaited(controller.close());
  });

  testWidgets('a number past the end of a book that finishes loading is refused', (tester) async {
    phone(tester, 1.0);
    final controller = StreamController<BookLoadUpdate>();
    await tester.pumpWidget(host(reader((u, t) => controller.stream)));
    await tester.pump();
    controller.add(BookLoadUpdate(ParsedBook([chapter(1), chapter(2)], const {}), complete: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await typeAndDone(tester, '9');
    controller.add(BookLoadUpdate(ParsedBook([for (var i = 1; i <= 3; i++) chapter(i)], const {}), complete: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Enter a chapter between 1 and 3'), findsOneWidget);
    expectChapter(tester, 1, 3);
    await tester.pump(const Duration(seconds: 5));
    unawaited(controller.close());
  });

  for (final mode in ['light', 'dark', 'sepia']) {
    for (final scale in scales) {
      testWidgets('$mode, text scale $scale on 360 dp: no overflow, the strip keeps its height, with and without a bookmark', (tester) async {
        phone(tester, scale);
        await open(tester, readerOf(bookOf(List.filled(38, 20)), theme: mode));
        final strip = tester.getSize(find.byType(ReaderChapterStrip)).height;
        expectChapter(tester, 1, 38);
        expect(tester.takeException(), isNull);
        await typeAndDone(tester, '27');
        expectChapter(tester, 27, 38);
        expect(tester.getSize(find.byType(ReaderChapterStrip)).height, strip, reason: 'the keyboard row does not change the strip');
        expect(tester.takeException(), isNull);
        final r = tester.getRect(box);
        expect(r.left, greaterThanOrEqualTo(48));
        expect(r.right, lessThanOrEqualTo(360 - 48));
        expect(tester.getSize(box).height, greaterThanOrEqualTo(30));
      });
    }
  }

  for (final scale in scales) {
    testWidgets('with a saved bookmark pill, text scale $scale: still one line, no overflow, the box still works', (tester) async {
      phone(tester, scale);
      await open(
        tester,
        BookReaderPage(
          dropboxUrl: 'https://example.invalid/book.docx?dl=0',
          bookTitle: 'Test Book',
          bookKey: 'book_1',
          level: 'level-1',
          uid: 'u1',
          loader: (u, t) => Stream.value(BookLoadUpdate(bookOf(List.filled(38, 20)), complete: true)),
          extras: () async => <Object?>[
            <String, int>{'chapter': 11, 'paragraph': 3},
            <String, Object?>{'theme': 'light'},
            false,
          ],
        ),
      );
      expectChapter(tester, 12, 38);
      expect(find.textContaining('Saved at ch 12'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await typeAndDone(tester, '3');
      expectChapter(tester, 3, 38);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(box).right, lessThanOrEqualTo(360 - 48));
    });
  }
}
