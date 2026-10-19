// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookHighlightStore.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/utils/ReaderContrast.dart';
import 'package:folk_app/widgets/ReaderChrome.dart';
import 'package:folk_app/widgets/ReaderHighlights.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Highlights & notes in the book reader, as the student uses them: long-press to select, handles, focus mode (the
// bars slide away), the panel, saved highlights drawn in their colour, tap -> note, long-press -> resize / delete,
// re-anchoring when the book changes, the reading timer, and bookmarks that never get in the way.

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

// ------------------------------------------------------------------------------------------------ the book
const p0 = 'First paragraph. It has two sentences here, and more words follow to make a long line that wraps over several lines on a narrow phone screen.';
const p1 = 'Second paragraph of the first chapter, short.';
const p2 = 'Third paragraph closes the chapter.';

ParsedChapter chapterOf(String title, List<String> paragraphs) => ParsedChapter(
      title: title,
      titleRuns: [TextRun(title, bold: true)],
      paragraphs: [for (final p in paragraphs) [TextRun(p)]],
    );

ParsedBook theBook({List<String> first = const [p0, p1, p2]}) => ParsedBook([
      chapterOf('Chapter one', first),
      chapterOf('Chapter two', ['Chapter two begins here.', 'More text in chapter two.']),
    ], const {});

List<List<String>> textsOf(ParsedBook b) => [for (final c in b.chapters) [for (final p in c.paragraphs) renderedParagraphText(p)]];

// ------------------------------------------------------------------------------------------------ the store
class FakeStore implements HighlightStore {
  FakeStore([List<BookHighlight>? start]) : items = [...?start];

  final List<BookHighlight> items;
  int loads = 0;
  int _n = 0;
  bool failAdd = false;

  @override
  Future<List<BookHighlight>> load({required String uid, required String bookKey, required String level}) async {
    loads++;
    return [...items];
  }

  @override
  Future<BookHighlight> add({required String uid, required String bookKey, required String level, required String bookTitle, required BookHighlight highlight}) async {
    if (failAdd) throw StateError('offline');
    final saved = BookHighlight(
      id: 'h${++_n}',
      anchor: highlight.anchor,
      text: highlight.text,
      textLength: highlight.textLength,
      snippetStart: highlight.snippetStart,
      snippetEnd: highlight.snippetEnd,
      category: highlight.category,
      note: highlight.note,
      createdMillis: 1000 + _n,
    );
    items.add(saved);
    return saved;
  }

  @override
  Future<void> update(String id, Map<String, Object?> fields) async {
    final i = items.indexWhere((h) => h.id == id);
    items[i] = BookHighlight.fromFields(id, {...items[i].toFields(), ...fields}, createdMillis: items[i].createdMillis)!;
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((h) => h.id == id);
}

BookHighlight saved(String id, ParsedBook book, ReaderRange range, HighlightCategory c, {int chapter = 0, String note = '', int at = 1}) =>
    BookHighlight.create(id: id, chapter: chapter, range: range, paragraphs: textsOf(book)[chapter], category: c, note: note, createdMillis: at);

// ------------------------------------------------------------------------------------------------ the reader
Widget host(Widget home) => MaterialApp(
      theme: FolkTheme.light,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: home,
    );

BookReaderPage reader(
  FakeStore store, {
  ParsedBook? book,
  DateTime Function()? clock,
  Map<String, int>? bookmark,
  String theme = 'light',
  bool rdua = false,
}) {
  final b = book ?? theBook();
  return BookReaderPage(
    dropboxUrl: 'https://example.invalid/book.docx?dl=0',
    bookTitle: 'Test Book',
    bookKey: 'book_1',
    level: 'level-1',
    uid: 'u1',
    isRdua: rdua,
    loader: (u, t) => Stream.value(BookLoadUpdate(b, complete: true)),
    extras: () async => <Object?>[bookmark, <String, Object?>{'theme': theme}, false],
    highlightStore: store,
    clock: clock,
  );
}

Future<void> open(WidgetTester tester, FakeStore store, {double scale = 1.0, ParsedBook? book, DateTime Function()? clock, Map<String, int>? bookmark, String theme = 'light', bool rdua = false}) async {
  phone(tester, scale);
  await tester.pumpWidget(host(reader(store, book: book, clock: clock, bookmark: bookmark, theme: theme, rdua: rdua)));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder richStarting(String prefix) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith(prefix));

/// The screen point of character [offset] of the paragraph that starts with [prefix] (inside that character).
Offset pointAt(WidgetTester tester, String prefix, int offset) {
  final rp = tester.renderObject<RenderParagraph>(richStarting(prefix));
  final caret = rp.getOffsetForCaret(TextPosition(offset: offset), Rect.zero);
  final h = rp.getFullHeightForCaret(TextPosition(offset: offset));
  return rp.localToGlobal(caret + Offset(3, h / 2));
}

double barHeight(WidgetTester tester, String key) => tester.getSize(find.byKey(ValueKey(key))).height;
bool barsShown(WidgetTester tester) =>
    barHeight(tester, 'bar-appbar') > 40 && barHeight(tester, 'bar-strip') > 20 && barHeight(tester, 'bar-bottom') > 10;
bool barsGone(WidgetTester tester) =>
    barHeight(tester, 'bar-appbar') == 0 && barHeight(tester, 'bar-strip') == 0 && barHeight(tester, 'bar-bottom') == 0;

/// What every paragraph paints (in order), as [PaintedRange]s.
List<List<PaintedRange>> painted(WidgetTester tester) => [
      for (final c in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (c.painter is ParagraphHighlightPainter) (c.painter as ParagraphHighlightPainter).ranges,
    ];

Future<void> longPress(WidgetTester tester, Offset at) async {
  await tester.longPressAt(at);
  await settle(tester);
}

Future<void> dragHandle(WidgetTester tester, String key, Offset toTextPoint) async {
  final from = tester.getCenter(find.byKey(ValueKey(key)));
  // the knob hangs under the line: the app reads the point 30 dp above the finger
  final to = toTextPoint + const Offset(0, 30);
  await tester.dragFrom(from, to - from);
  await settle(tester);
}

Finder byKeyName(String k) => find.byKey(ValueKey(k));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('a new highlight', () {
    testWidgets('long-press selects the word, the bars slide away, handles and the action bar appear', (tester) async {
      await open(tester, FakeStore());
      expect(barsShown(tester), isTrue);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      expect(barsGone(tester), isTrue, reason: 'focus mode: title bar, chapter strip and progress bar are gone');
      expect(byKeyName('sel-highlight'), findsOneWidget);
      expect(byKeyName('handle-start'), findsOneWidget);
      expect(byKeyName('handle-end'), findsOneWidget);
      // the word "First" is the selection
      expect(painted(tester)[0], [const PaintedRange(0, 5, null)]);
    });

    testWidgets('the bars come back when the selection is cancelled; nothing is saved', (tester) async {
      final store = FakeStore();
      await open(tester, store);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await tester.tap(byKeyName('sel-cancel'));
      await settle(tester);
      expect(barsShown(tester), isTrue);
      expect(byKeyName('handle-start'), findsNothing);
      expect(painted(tester).every((r) => r.isEmpty), isTrue);
      expect(store.items, isEmpty);
    });

    testWidgets('a tap on the page closes a plain selection', (tester) async {
      await open(tester, FakeStore());
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await tester.tapAt(pointAt(tester, 'Third paragraph', 3));
      await settle(tester);
      expect(barsShown(tester), isTrue);
      expect(byKeyName('sel-highlight'), findsNothing);
    });

    testWidgets('the panel: choose a category, write a note, Submit saves it and draws it; the bars return', (tester) async {
      final store = FakeStore();
      await open(tester, store);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await tester.tap(byKeyName('sel-highlight'));
      await tester.pumpAndSettle();
      expect(byKeyName('highlight-category-good'), findsOneWidget);
      expect(byKeyName('highlight-category-excellent'), findsOneWidget);
      expect(byKeyName('highlight-category-rare'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(byKeyName('highlight-submit')).onPressed, isNull, reason: 'a category must be chosen first');
      expect(barsGone(tester), isTrue, reason: 'still in focus mode while the panel is open');
      await tester.tap(byKeyName('highlight-category-rare'));
      await tester.pump();
      await tester.enterText(byKeyName('highlight-note'), 'A wonderful line to remember.');
      await tester.tap(byKeyName('highlight-submit'));
      await tester.pumpAndSettle();
      expect(store.items, hasLength(1));
      final h = store.items.single;
      expect(h.category, HighlightCategory.rare);
      expect(h.note, 'A wonderful line to remember.');
      expect(h.text, 'First');
      expect(h.anchor, const HighlightAnchor(0, ReaderRange(0, 0, 0, 5)));
      expect(barsShown(tester), isTrue);
      expect(painted(tester)[0], [const PaintedRange(0, 5, HighlightCategory.rare)]);
    });

    testWidgets('Cancel in the panel saves nothing and restores the bars', (tester) async {
      final store = FakeStore();
      await open(tester, store);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await tester.tap(byKeyName('sel-highlight'));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('highlight-category-good'));
      await tester.pump();
      await tester.enterText(byKeyName('highlight-note'), 'never saved');
      await tester.tap(byKeyName('highlight-cancel'));
      await tester.pumpAndSettle();
      expect(store.items, isEmpty);
      expect(barsShown(tester), isTrue);
      expect(painted(tester).every((r) => r.isEmpty), isTrue);
    });

    testWidgets('a note of any length: long, multi-line notes are saved whole', (tester) async {
      final store = FakeStore();
      await open(tester, store);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await tester.tap(byKeyName('sel-highlight'));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('highlight-category-good'));
      final note = List.generate(60, (i) => 'Line $i of a very long note.').join('\n');
      await tester.enterText(byKeyName('highlight-note'), note);
      await tester.pump();
      await tester.tap(byKeyName('highlight-submit'));
      await tester.pumpAndSettle();
      expect(store.items.single.note, note);
    });

    testWidgets('the shortcuts: a whole sentence, a whole paragraph', (tester) async {
      await open(tester, FakeStore());
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await tester.tap(byKeyName('sel-sentence'));
      await settle(tester);
      expect(painted(tester)[0], [const PaintedRange(0, 16, null)], reason: '"First paragraph."');
      await tester.tap(byKeyName('sel-paragraph'));
      await settle(tester);
      expect(painted(tester)[0], [PaintedRange(0, p0.length, null)]);
    });

    testWidgets('dragging a handle extends the selection across paragraphs; the saved highlight spans them', (tester) async {
      final store = FakeStore();
      await open(tester, store);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await dragHandle(tester, 'handle-end', pointAt(tester, 'Second paragraph', 10));
      final ranges = painted(tester);
      expect(ranges[0], [PaintedRange(0, p0.length, null)].isEmpty ? isEmpty : isNotEmpty);
      expect(ranges[0].single.start, 0);
      expect(ranges[0].single.end, p0.length, reason: 'the whole first paragraph is covered');
      expect(ranges[1].single, const PaintedRange(0, 10, null));
      expect(ranges[2], isEmpty);
      await tester.tap(byKeyName('sel-highlight'));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('highlight-category-excellent'));
      await tester.pump();
      await tester.tap(byKeyName('highlight-submit'));
      await tester.pumpAndSettle();
      final h = store.items.single;
      expect(h.anchor.range, ReaderRange(0, 0, 1, 10));
      expect(h.text, '$p0\n${p1.substring(0, 10)}');
      expect(painted(tester)[0].single.category, HighlightCategory.excellent);
      expect(painted(tester)[1].single, const PaintedRange(0, 10, HighlightCategory.excellent));
    });

    testWidgets('the start handle moves the start (part of a line)', (tester) async {
      await open(tester, FakeStore());
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await dragHandle(tester, 'handle-end', pointAt(tester, 'First paragraph', 16));
      await dragHandle(tester, 'handle-start', pointAt(tester, 'First paragraph', 6));
      expect(painted(tester)[0], [const PaintedRange(6, 16, null)]);
    });

    testWidgets('a failed save keeps the selection so it can be tried again', (tester) async {
      final store = FakeStore()..failAdd = true;
      await open(tester, store);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      await tester.tap(byKeyName('sel-highlight'));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('highlight-category-good'));
      await tester.pump();
      await tester.tap(byKeyName('highlight-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save the highlight. Try again.'), findsOneWidget);
      expect(byKeyName('sel-highlight'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      store.failAdd = false;
      await tester.tap(byKeyName('sel-highlight'));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('highlight-category-good'));
      await tester.pump();
      await tester.tap(byKeyName('highlight-submit'));
      await tester.pumpAndSettle();
      expect(store.items, hasLength(1));
    });

    testWidgets('Back while selecting closes the selection; it does not leave the book', (tester) async {
      await open(tester, FakeStore());
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      final app = tester.state(find.byType(WidgetsApp)) as WidgetsBindingObserver;
      await app.didPopRoute();
      await settle(tester);
      expect(byKeyName('sel-highlight'), findsNothing);
      expect(barsShown(tester), isTrue);
      expect(find.byType(BookReaderPage), findsOneWidget);
    });
  });

  group('saved highlights', () {
    ParsedBook book0() => theBook();

    testWidgets('every time the book is opened, all saved highlights appear, in their colours', (tester) async {
      final b = book0();
      final store = FakeStore([
        saved('1', b, const ReaderRange(0, 0, 0, 5), HighlightCategory.good, at: 1),
        saved('2', b, const ReaderRange(0, 17, 0, 60), HighlightCategory.excellent, at: 2),
        saved('3', b, const ReaderRange(1, 7, 2, 5), HighlightCategory.rare, at: 3),
      ]);
      await open(tester, store, book: b);
      final r = painted(tester);
      expect(r[0], [const PaintedRange(0, 5, HighlightCategory.good), const PaintedRange(17, 60, HighlightCategory.excellent)]);
      expect(r[1], [PaintedRange(7, p1.length, HighlightCategory.rare)]);
      expect(r[2], [const PaintedRange(0, 5, HighlightCategory.rare)]);
      expect(store.loads, 1);
    });

    testWidgets('the layout does not change: paragraphs have the same size with and without highlights', (tester) async {
      final b = book0();
      await open(tester, FakeStore(), book: b);
      final plain = [for (final f in [richStarting('First paragraph'), richStarting('Second paragraph')]) tester.getSize(f)];
      await tester.pumpWidget(const SizedBox());
      await open(tester, FakeStore([saved('1', b, ReaderRange(0, 0, 1, 10), HighlightCategory.rare)]), book: b);
      final lit = [for (final f in [richStarting('First paragraph'), richStarting('Second paragraph')]) tester.getSize(f)];
      expect(lit, plain);
    });

    testWidgets('tap on a highlight: its category and note; tap outside closes it and reading continues', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 0, 0, 15), HighlightCategory.excellent, note: 'Remember this.')]);
      await open(tester, store, book: b);
      await tester.tapAt(pointAt(tester, 'First paragraph', 4));
      await tester.pumpAndSettle();
      expect(find.text('EXCELLENT'), findsOneWidget);
      expect(find.text('Remember this.'), findsOneWidget);
      expect(byKeyName('highlight-edit-note'), findsOneWidget);
      expect(byKeyName('highlight-change-category'), findsOneWidget);
      await tester.tapAt(const Offset(4, 790));
      await tester.pumpAndSettle();
      expect(find.text('Remember this.'), findsNothing);
      expect(barsShown(tester), isTrue, reason: 'back to reading, nothing changed');
      expect(store.items.single.note, 'Remember this.');
    });

    testWidgets('a long note scrolls in the dialog', (tester) async {
      final b = book0();
      final note = List.generate(80, (i) => 'Note line $i.').join('\n');
      await open(tester, FakeStore([saved('1', b, const ReaderRange(0, 0, 0, 15), HighlightCategory.good, note: note)]), book: b);
      await tester.tapAt(pointAt(tester, 'First paragraph', 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = find.ancestor(of: byKeyName('highlight-info-note'), matching: find.byType(SingleChildScrollView));
      expect(scroll, findsOneWidget);
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no note yet: the dialog says so', (tester) async {
      final b = book0();
      await open(tester, FakeStore([saved('1', b, const ReaderRange(0, 0, 0, 15), HighlightCategory.good)]), book: b);
      await tester.tapAt(pointAt(tester, 'First paragraph', 4));
      await tester.pumpAndSettle();
      expect(find.text('No note yet.'), findsOneWidget);
    });

    testWidgets('Edit note: only the note changes (category kept)', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 0, 0, 15), HighlightCategory.rare, note: 'old')]);
      await open(tester, store, book: b);
      await tester.tapAt(pointAt(tester, 'First paragraph', 4));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('highlight-edit-note'));
      await tester.pumpAndSettle();
      expect(byKeyName('highlight-category-good'), findsNothing, reason: 'the note panel has no categories');
      expect(tester.widget<TextField>(byKeyName('highlight-note')).controller!.text, 'old');
      await tester.enterText(byKeyName('highlight-note'), 'a better note');
      await tester.tap(byKeyName('highlight-submit'));
      await tester.pumpAndSettle();
      expect(store.items.single.note, 'a better note');
      expect(store.items.single.category, HighlightCategory.rare);
    });

    testWidgets('Change category: only the category changes (note kept) and the colour on the page follows', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 0, 0, 15), HighlightCategory.good, note: 'keep me')]);
      await open(tester, store, book: b);
      await tester.tapAt(pointAt(tester, 'First paragraph', 4));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('highlight-change-category'));
      await tester.pumpAndSettle();
      expect(byKeyName('highlight-note'), findsNothing, reason: 'the category panel has no note field');
      await tester.tap(byKeyName('highlight-category-excellent'));
      await tester.pump();
      await tester.tap(byKeyName('highlight-submit'));
      await tester.pumpAndSettle();
      expect(store.items.single.category, HighlightCategory.excellent);
      expect(store.items.single.note, 'keep me');
      expect(painted(tester)[0].single.category, HighlightCategory.excellent);
    });

    testWidgets('long-press on a highlight: edit mode (focus mode, handles, Delete / Cancel / Save)', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 6, 0, 16), HighlightCategory.rare, note: 'n')]);
      await open(tester, store, book: b);
      await longPress(tester, pointAt(tester, 'First paragraph', 8));
      expect(barsGone(tester), isTrue);
      expect(byKeyName('edit-delete'), findsOneWidget);
      expect(byKeyName('edit-cancel'), findsOneWidget);
      expect(byKeyName('edit-save'), findsOneWidget);
      expect(byKeyName('sel-highlight'), findsNothing, reason: 'this is an edit, not a new selection');
      expect(byKeyName('handle-start'), findsOneWidget);
      expect(byKeyName('handle-end'), findsOneWidget);
      expect(painted(tester)[0], [const PaintedRange(6, 16, HighlightCategory.rare)], reason: 'drawn once, in its colour');
    });

    testWidgets('edit: extend with a handle, Save keeps the category and note', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 6, 0, 16), HighlightCategory.excellent, note: 'my note')]);
      await open(tester, store, book: b);
      await longPress(tester, pointAt(tester, 'First paragraph', 8));
      await dragHandle(tester, 'handle-end', pointAt(tester, 'Second paragraph', 6));
      await tester.tap(byKeyName('edit-save'));
      await settle(tester);
      final h = store.items.single;
      expect(h.anchor.range, ReaderRange(0, 6, 1, 6));
      expect(h.category, HighlightCategory.excellent);
      expect(h.note, 'my note');
      expect(h.text, '${p0.substring(6)}\n${p1.substring(0, 6)}');
      expect(barsShown(tester), isTrue);
      expect(painted(tester)[1].single, const PaintedRange(0, 6, HighlightCategory.excellent));
    });

    testWidgets('edit: shrink with the start handle', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 6, 0, 30), HighlightCategory.good)]);
      await open(tester, store, book: b);
      await longPress(tester, pointAt(tester, 'First paragraph', 8));
      await dragHandle(tester, 'handle-start', pointAt(tester, 'First paragraph', 20));
      await tester.tap(byKeyName('edit-save'));
      await settle(tester);
      expect(store.items.single.anchor.range, const ReaderRange(0, 20, 0, 30));
    });

    testWidgets('edit: Cancel changes nothing', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 6, 0, 16), HighlightCategory.good)]);
      await open(tester, store, book: b);
      await longPress(tester, pointAt(tester, 'First paragraph', 8));
      await dragHandle(tester, 'handle-end', pointAt(tester, 'Second paragraph', 6));
      await tester.tap(byKeyName('edit-cancel'));
      await settle(tester);
      expect(store.items.single.anchor.range, const ReaderRange(0, 6, 0, 16));
      expect(barsShown(tester), isTrue);
      expect(painted(tester)[0], [const PaintedRange(6, 16, HighlightCategory.good)]);
    });

    testWidgets('edit: Delete asks first; Cancel keeps it, Delete removes it', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 6, 0, 16), HighlightCategory.good, note: 'n')]);
      await open(tester, store, book: b);
      await longPress(tester, pointAt(tester, 'First paragraph', 8));
      await tester.tap(byKeyName('edit-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this highlight?'), findsOneWidget);
      await tester.tap(byKeyName('delete-cancel'));
      await tester.pumpAndSettle();
      expect(store.items, hasLength(1));
      expect(byKeyName('edit-save'), findsOneWidget, reason: 'still editing');
      await tester.tap(byKeyName('edit-delete'));
      await tester.pumpAndSettle();
      await tester.tap(byKeyName('delete-confirm'));
      await tester.pumpAndSettle();
      expect(store.items, isEmpty);
      expect(barsShown(tester), isTrue);
      expect(painted(tester).every((r) => r.isEmpty), isTrue);
    });

    testWidgets('a highlight keeps the other highlights and the text beside it tappable/selectable', (tester) async {
      final b = book0();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 0, 0, 5), HighlightCategory.good)]);
      await open(tester, store, book: b);
      // long-press next to (not on) the highlight starts a NEW selection
      await longPress(tester, pointAt(tester, 'First paragraph', 25));
      expect(byKeyName('sel-highlight'), findsOneWidget);
      expect(byKeyName('edit-save'), findsNothing);
    });
  });

  group('the book changed: highlights find their place again', () {
    testWidgets('a paragraph was added before it: drawn at its new place, stored untouched', (tester) async {
      final old = theBook(first: const ['A preface paragraph.', p0, p1, p2]);
      final h = saved('1', old, const ReaderRange(1, 0, 1, 15), HighlightCategory.excellent, note: 'kept');
      final store = FakeStore([h]);
      await open(tester, store, book: theBook()); // the replaced file: no preface
      expect(painted(tester)[0], [const PaintedRange(0, 15, HighlightCategory.excellent)]);
      expect(store.items.single.anchor, h.anchor, reason: 'reading never rewrites it');
    });

    testWidgets('its text is gone: kept, not drawn, no crash', (tester) async {
      final other = ParsedBook([chapterOf('X', ['Some totally different words live here now.'])], const {});
      final h = saved('1', other, const ReaderRange(0, 5, 0, 20), HighlightCategory.rare, note: 'orphan');
      final store = FakeStore([h]);
      await open(tester, store);
      expect(tester.takeException(), isNull);
      expect(painted(tester).every((r) => r.isEmpty), isTrue);
      expect(store.items, hasLength(1));
      expect(store.items.single.note, 'orphan');
      // and the reader still works
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      expect(byKeyName('sel-highlight'), findsOneWidget);
    });

    testWidgets('a damaged stored position (outside the book) does not crash', (tester) async {
      final b = theBook();
      final h = BookHighlight(
        id: 'z',
        anchor: HighlightAnchor(7, const ReaderRange(90, 4, 91, 8)),
        text: 'First paragraph.',
        textLength: 16,
        snippetStart: 'First paragraph.',
        snippetEnd: 'First paragraph.',
        category: HighlightCategory.good,
      );
      await open(tester, FakeStore([h]), book: b);
      expect(tester.takeException(), isNull);
      expect(painted(tester)[0], [const PaintedRange(0, 16, HighlightCategory.good)]);
    });
  });

  group('the reading timer never pauses', () {
    testWidgets('selection, panel, dialogs and edit mode all count as reading time', (tester) async {
      var now = DateTime(2026, 10, 1, 10);
      final b = theBook();
      final store = FakeStore([saved('1', b, const ReaderRange(0, 20, 0, 30), HighlightCategory.good, note: 'n')]);
      int? popped;
      phone(tester, 1.0);
      await tester.pumpWidget(host(Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              popped = await Navigator.push<int>(
                context,
                MaterialPageRoute(builder: (_) => reader(store, book: b, clock: () => now, bookmark: {'chapter': 0, 'paragraph': 0})),
              );
            },
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      now = now.add(const Duration(seconds: 30)); // reading
      await longPress(tester, pointAt(tester, 'First paragraph', 2)); // selecting
      now = now.add(const Duration(seconds: 45));
      await tester.tap(byKeyName('sel-highlight')); // the panel
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 20));
      await tester.tap(byKeyName('highlight-cancel'));
      await tester.pumpAndSettle();
      await tester.tapAt(pointAt(tester, 'First paragraph', 24)); // a dialog
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 10));
      await tester.tapAt(const Offset(4, 790));
      await tester.pumpAndSettle();
      await longPress(tester, pointAt(tester, 'First paragraph', 24)); // edit mode
      now = now.add(const Duration(seconds: 5));
      await tester.tap(byKeyName('edit-cancel'));
      await settle(tester);
      now = now.add(const Duration(seconds: 7));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(popped, 30 + 45 + 20 + 10 + 5 + 7);
    });
  });

  group('bookmarks, chapters and the finish button keep working', () {
    testWidgets('bookmark mode and highlighting never conflict', (tester) async {
      final b = theBook();
      await open(tester, FakeStore([saved('1', b, const ReaderRange(0, 0, 0, 15), HighlightCategory.good)]), book: b);
      await tester.tap(find.byTooltip('Add a bookmark'));
      await settle(tester);
      expect(find.text('Tap a paragraph to bookmark'), findsOneWidget);
      await longPress(tester, pointAt(tester, 'Second paragraph', 3));
      expect(byKeyName('sel-highlight'), findsNothing, reason: 'in bookmark mode a long-press selects nothing');
      await tester.tapAt(pointAt(tester, 'First paragraph', 4));
      await tester.pumpAndSettle();
      expect(byKeyName('highlight-edit-note'), findsNothing, reason: 'a tap on a highlight opens nothing in bookmark mode');
      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester);
      // and the other way: after bookmark mode, highlighting works again
      await longPress(tester, pointAt(tester, 'Second paragraph', 3));
      expect(byKeyName('sel-highlight'), findsOneWidget);
    });

    testWidgets('the bookmark button is out of reach while a selection or an edit is open (the bars are away)', (tester) async {
      await open(tester, FakeStore());
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      expect(barHeight(tester, 'bar-appbar'), 0);
      expect(tester.getSize(find.byKey(const ValueKey('bar-appbar'))).height, 0);
    });

    testWidgets('chapter arrows work with highlights; each chapter draws only its own', (tester) async {
      final b = theBook();
      final store = FakeStore([
        saved('1', b, const ReaderRange(0, 0, 0, 5), HighlightCategory.good, at: 1),
        saved('2', b, const ReaderRange(0, 0, 0, 7), HighlightCategory.rare, chapter: 1, at: 2),
      ]);
      await open(tester, store, book: b);
      expect(painted(tester)[0], [const PaintedRange(0, 5, HighlightCategory.good)]);
      await tester.tap(find.byTooltip('Next chapter'));
      await settle(tester);
      expect(find.textContaining('Chapter two begins here.', findRichText: true), findsWidgets);
      expect(painted(tester)[0], [const PaintedRange(0, 7, HighlightCategory.rare)]);
      await tester.tap(find.byTooltip('Previous chapter'));
      await settle(tester);
      expect(painted(tester)[0], [const PaintedRange(0, 5, HighlightCategory.good)]);
    });

    testWidgets('a chapter change while selecting closes the selection', (tester) async {
      await open(tester, FakeStore());
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      expect(byKeyName('sel-highlight'), findsOneWidget);
      // (the arrows are away in focus mode; a typed chapter number still goes there)
      await tester.enterText(find.descendant(of: find.byType(ReaderChapterStrip), matching: find.byType(TextField)), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(byKeyName('sel-highlight'), findsNothing);
      expect(barsShown(tester), isTrue);
    });
  });

  group('RDUA modules have no highlights', () {
    testWidgets('no store read, a long-press selects nothing', (tester) async {
      final store = FakeStore();
      await open(tester, store, rdua: true);
      expect(store.loads, 0);
      await longPress(tester, pointAt(tester, 'First paragraph', 2));
      expect(byKeyName('sel-highlight'), findsNothing);
      expect(barsShown(tester), isTrue);
    });
  });

  // Light, Dark, Sepia x text scale 1.0 / 1.3 / 1.6, the app's real fonts.
  for (final theme in ['light', 'dark', 'sepia']) {
    for (final scale in scales) {
      final s = '$theme, text scale $scale';

      testWidgets('saved highlights: shape, colours and readable text — $s', (tester) async {
        final b = theBook();
        final store = FakeStore([
          saved('1', b, const ReaderRange(0, 0, 0, 5), HighlightCategory.good, at: 1), // part of a line
          saved('2', b, const ReaderRange(0, 40, 0, 120), HighlightCategory.excellent, at: 2), // several lines
          saved('3', b, const ReaderRange(1, 7, 2, 12), HighlightCategory.rare, at: 3), // across paragraphs
        ]);
        await open(tester, store, book: b, scale: scale, theme: theme);
        expect(tester.takeException(), isNull);
        expect(painted(tester).where((r) => r.isNotEmpty).length, 3);
        final page = backgroundFor(theme);
        for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
          rt.text.visitChildren((span) {
            if (span is TextSpan && (span.text ?? '').isNotEmpty && span.style?.fontFamily == 'serif') {
              final c = span.style!.color!.toARGB32();
              expect(contrastRatio(c, page), greaterThanOrEqualTo(kReaderMinContrast), reason: '${span.text} on the $theme page');
              for (final cat in HighlightCategory.values) {
                if ((rt.text.toPlainText().startsWith('First') && cat != HighlightCategory.good && cat != HighlightCategory.excellent) ||
                    (!rt.text.toPlainText().startsWith('First') && !rt.text.toPlainText().startsWith('Second') && !rt.text.toPlainText().startsWith('Third'))) {
                  continue;
                }
                if (rt.text.toPlainText().startsWith('Second') && cat != HighlightCategory.rare) continue;
                if (rt.text.toPlainText().startsWith('Third') && cat != HighlightCategory.rare) continue;
                expect(contrastRatio(c, compositeOver(cat.tintArgb, page)), greaterThanOrEqualTo(kReaderMinContrast),
                    reason: '${span.text} on the ${cat.label} tint, $theme');
              }
            }
            return true;
          });
        }
      });

      testWidgets('selecting, the action bar, the panel and edit mode — $s', (tester) async {
        final b = theBook();
        final store = FakeStore([saved('1', b, const ReaderRange(0, 40, 0, 120), HighlightCategory.rare, note: 'n')]);
        await open(tester, store, book: b, scale: scale, theme: theme);
        await longPress(tester, pointAt(tester, 'Third paragraph', 2));
        expect(byKeyName('sel-highlight'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(byKeyName('sel-highlight'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(byKeyName('highlight-cancel'));
        await tester.pumpAndSettle();
        await longPress(tester, pointAt(tester, 'First paragraph', 60));
        expect(byKeyName('edit-save'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(byKeyName('edit-cancel'));
        await settle(tester);
        await tester.tapAt(pointAt(tester, 'First paragraph', 60));
        await tester.pumpAndSettle();
        expect(find.text('RARE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
