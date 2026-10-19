import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BooksHistoryPage.dart';
import 'package:folk_app/pages/BooksNotesPage.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/utils/BookNotes.dart';
import 'package:folk_app/utils/BookReadingLog.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FolkErrorRetry.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/GradientCard.dart';
import 'package:folk_app/widgets/InsightTile.dart';
import 'package:folk_app/widgets/PressScale.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Books -> History (per-day reading, expand / collapse, the 30-day cap) and Books -> Notes (categories -> books -> numbered
// cards -> note dialog, progress). Real fonts, text scale 1.0 / 1.3 / 1.6, light and dark.

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

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: false), child: w!),
      home: home,
    );

// Fails the first [fails] reads, then behaves.
class _Flaky implements FirebaseFirestore {
  _Flaky(this.inner, this.fails);
  final FirebaseFirestore inner;
  int fails;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (fails > 0) {
      fails--;
      throw StateError('offline');
    }
    return inner.collection(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The stamp of 1 Sep 2026 plus [i] days (a real date).
int stampAt(int i) => dayStampOf(DateTime(2026, 9, 1 + i));

Map<String, dynamic> dayDoc(String uid, int stamp, Map<String, int> books) => {
      'uid': uid,
      'dayStamp': stamp,
      'dayKey': '${(stamp % 100).toString().padLeft(2, '0')}-${((stamp ~/ 100) % 100).toString().padLeft(2, '0')}-${stamp ~/ 10000}',
      'totalSeconds': books.values.fold<int>(0, (a, b) => a + b),
      'books': {
        for (final e in books.entries) e.key: {'title': e.key, 'level': 'level-1', 'bookKey': e.key, 'seconds': e.value},
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // ====================================================================================== the reading log (data)
  group('the reading log', () {
    test('minutes: whole minutes, at least one for any real reading', () {
      expect(minutesOf(0), 0);
      expect(minutesOf(40), 1);
      expect(minutesOf(89), 1);
      expect(minutesOf(90), 2);
      expect(minutesOf(3600), 60);
      expect(minutesText(1500), '25 min');
    });

    test('a session too short to count creates nothing; a real one creates the day', () async {
      final fs = FakeFirebaseFirestore();
      final day = DateTime(2026, 10, 19, 9);
      expect(await recordReadingDay(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 20, now: day), isFalse);
      expect((await fs.collection('readingDays').get()).docs, isEmpty, reason: 'days with no (real) reading create nothing');
      expect(await recordReadingDay(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 600, now: day), isTrue);
      final d = (await fs.collection('readingDays').doc('u1_20261019').get()).data()!;
      expect(d['uid'], 'u1');
      expect(d['dayKey'], '19-10-2026');
      expect(d['dayStamp'], 20261019);
      expect(d['totalSeconds'], 600);
      expect((d['books'] as Map)['level-1__book_1']['seconds'], 600);
      expect((d['books'] as Map)['level-1__book_1']['title'], 'Gita');
    });

    test('several sessions the same day add up, per book and in total; the next day is a new document', () async {
      final fs = FakeFirebaseFirestore();
      final day = DateTime(2026, 10, 19, 9);
      await recordReadingDay(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 600, now: day);
      await recordReadingDay(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 300, now: day);
      await recordReadingDay(db: fs, uid: 'u1', level: 'level-2', bookKey: 'book_4', title: 'Nectar', seconds: 900, now: day);
      final d = (await fs.collection('readingDays').doc('u1_20261019').get()).data()!;
      expect(d['totalSeconds'], 1800);
      final books = d['books'] as Map;
      expect(books['level-1__book_1']['seconds'], 900);
      expect(books['level-2__book_4']['seconds'], 900);
      await recordReadingDay(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 120, now: DateTime(2026, 10, 20, 7));
      expect((await fs.collection('readingDays').get()).docs.length, 2);
    });

    test('parse: newest first, never more than 30, damaged documents skipped, books most-read first', () {
      final docs = <Map<String, dynamic>>[
        for (var i = 0; i < 40; i++) dayDoc('u1', stampAt(i), {'A': 600}),
        {'uid': 'u1', 'dayStamp': 20261201, 'totalSeconds': 0},
        {'uid': 'u1', 'totalSeconds': 100},
        dayDoc('u1', 20261105, {'Small': 60, 'Big': 1200}),
      ];
      final days = parseReadingDays(docs);
      expect(days.length, 30);
      expect(days.first.stamp, 20261105);
      expect(days.first.books.map((b) => b.title), ['Big', 'Small']);
      expect(days[1].stamp, stampAt(39), reason: '10 Oct, the newest of the forty');
      for (var i = 1; i < days.length; i++) {
        expect(days[i - 1].stamp, greaterThan(days[i].stamp));
      }
    });
  });

  // ====================================================================================== the History screen
  group('Books -> History', () {
    Future<FakeFirebaseFirestore> seeded() async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('readingDays').doc('u1_20261017').set(dayDoc('u1', 20261017, {'Gita': 1500}));
      await fs.collection('readingDays').doc('u1_20261019').set(dayDoc('u1', 20261019, {'Gita': 1800, 'Nectar': 900}));
      await fs.collection('readingDays').doc('u1_20261018').set(dayDoc('u1', 20261018, {'Isopanisad': 600}));
      await fs.collection('readingDays').doc('u2_20261019').set(dayDoc('u2', 20261019, {'Other': 6000}));
      return fs;
    }

    testWidgets('one row per day, newest first: the date and the total minutes; another student\'s reading is not here', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksHistoryPage(uid: 'u1', firestore: await seeded())));
      await settle(tester);
      expect(find.text('Mon, 19 Oct 2026'), findsOneWidget);
      expect(find.text('Sun, 18 Oct 2026'), findsOneWidget);
      expect(find.text('Sat, 17 Oct 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('day-total-20261019')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('day-total-20261019'))).data, '45 min', reason: '1800 s + 900 s');
      expect(tester.widget<Text>(find.byKey(const ValueKey('day-total-20261018'))).data, '10 min');
      expect(tester.widget<Text>(find.byKey(const ValueKey('day-total-20261017'))).data, '25 min');
      expect(find.text('100 min'), findsNothing, reason: 'u2\'s day is not shown');
      final y = [for (final s in [20261019, 20261018, 20261017]) tester.getTopLeft(find.byKey(ValueKey('day-header-$s'))).dy];
      expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: 'newest first');
    });

    testWidgets('tap opens the day (a smooth dropdown) with each book and its minutes; tap again closes it', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksHistoryPage(uid: 'u1', firestore: await seeded())));
      await settle(tester);
      expect(find.byKey(const ValueKey('day-books-20261019')), findsNothing, reason: 'closed to begin with');
      await tester.tap(find.byKey(const ValueKey('day-header-20261019')));
      await tester.pump(const Duration(milliseconds: 60));
      // mid-way it is still growing (a smooth open, not a jump)
      final during = tester.getSize(find.byKey(const ValueKey('day-books-20261019'))).height;
      await settle(tester);
      final after = tester.getSize(find.byKey(const ValueKey('day-books-20261019'))).height;
      expect(after, greaterThan(0));
      expect(find.text('Gita'), findsOneWidget);
      expect(find.text('Nectar'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget, reason: 'Gita 1800 s');
      expect(find.text('15 min'), findsOneWidget, reason: 'Nectar 900 s');
      final gita = tester.getTopLeft(find.text('Gita')).dy;
      final nectar = tester.getTopLeft(find.text('Nectar')).dy;
      expect(gita, lessThan(nectar), reason: 'most-read first');
      expect(during, lessThanOrEqualTo(after));
      await tester.tap(find.byKey(const ValueKey('day-header-20261019')));
      await settle(tester);
      expect(find.byKey(const ValueKey('day-books-20261019')), findsNothing, reason: 'tap again closes it');
      expect(find.text('Nectar'), findsNothing);
    });

    testWidgets('days open independently', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksHistoryPage(uid: 'u1', firestore: await seeded())));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('day-header-20261019')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('day-header-20261018')));
      await settle(tester);
      expect(find.text('Nectar'), findsOneWidget);
      expect(find.text('Isopanisad'), findsOneWidget);
    });

    testWidgets('at most 30 days are shown, the newest', (tester) async {
      phone(tester, 1.0);
      final fs = FakeFirebaseFirestore();
      for (var i = 0; i < 35; i++) {
        final stamp = stampAt(i); // 1 Sep .. 5 Oct
        await fs.collection('readingDays').doc('u1_$stamp').set(dayDoc('u1', stamp, {'Gita': 600}));
      }
      await tester.pumpWidget(host(BooksHistoryPage(uid: 'u1', firestore: fs)));
      await settle(tester);
      expect(find.byKey(const ValueKey('day-header-20261005')), findsOneWidget, reason: 'the newest');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('day-header-20260906')), 300, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const ValueKey('day-header-20260906')), findsOneWidget, reason: 'the 30th newest');
      expect(find.byKey(const ValueKey('day-header-20260905')), findsNothing, reason: 'older than the 30 newest: not shown');
    });

    testWidgets('no reading yet: a friendly empty state', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksHistoryPage(uid: 'u1', firestore: FakeFirebaseFirestore())));
      await settle(tester);
      expect(find.byKey(const ValueKey('history-empty')), findsOneWidget);
    });

    testWidgets('a load that fails says so with Retry, and Retry works', (tester) async {
      phone(tester, 1.0);
      final fs = _Flaky(await seeded(), 1);
      await tester.pumpWidget(host(BooksHistoryPage(uid: 'u1', firestore: fs)));
      await settle(tester);
      expect(find.byType(FolkErrorRetry), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text('Mon, 19 Oct 2026'), findsOneWidget);
    });
  });

  // ====================================================================================== the Notes screens (data)
  group('notes: grouping', () {
    NoteEntry n(String id, String book, String title, HighlightCategory c, int ch, int p, int o, {String note = ''}) => NoteEntry(
          id: id, level: 'level-1', bookKey: book, bookTitle: title, category: c, text: 'text $id', note: note, chapter: ch, paragraph: p, offset: o, truncated: false);

    test('the books of a category: alphabetical names, each with its highlights in reading order', () {
      final all = [
        n('a', 'b2', 'Nectar', HighlightCategory.good, 3, 0, 0),
        n('b', 'b1', 'Gita', HighlightCategory.good, 5, 2, 10),
        n('c', 'b1', 'Gita', HighlightCategory.good, 5, 2, 4),
        n('d', 'b1', 'Gita', HighlightCategory.good, 1, 9, 0),
        n('e', 'b1', 'Gita', HighlightCategory.rare, 1, 0, 0),
      ];
      final good = booksIn(HighlightCategory.good, all);
      expect(good.map((b) => b.title), ['Gita', 'Nectar']);
      expect(good.first.entries.map((e) => e.id), ['d', 'c', 'b'], reason: 'chapter, then paragraph, then offset');
      expect(booksIn(HighlightCategory.excellent, all), isEmpty);
      expect(countIn(HighlightCategory.good, all), 4);
      expect(countIn(HighlightCategory.rare, all), 1);
    });

    test('the same title in two levels is two books', () {
      final all = [
        NoteEntry(id: '1', level: 'level-1', bookKey: 'book_1', bookTitle: 'Gita', category: HighlightCategory.good, text: 'x', note: '', chapter: 0, paragraph: 0, offset: 0, truncated: false),
        NoteEntry(id: '2', level: 'level-2', bookKey: 'book_1', bookTitle: 'Gita', category: HighlightCategory.good, text: 'y', note: '', chapter: 0, paragraph: 0, offset: 0, truncated: false),
      ];
      expect(booksIn(HighlightCategory.good, all).length, 2);
    });

    test('progress: "3 of 12 · 25%"', () {
      expect(progressLabel(2, 12), '3 of 12 · 25%');
      expect(progressLabel(0, 3), '1 of 3 · 33%');
      expect(progressLabel(1, 3), '2 of 3 · 67%');
      expect(progressLabel(11, 12), '12 of 12 · 100%');
      expect(progressLabel(0, 1), '1 of 1 · 100%');
      expect(progressLabel(0, 0), '');
      expect(progressFraction(2, 12), closeTo(0.25, 1e-9));
    });

    test('a damaged highlight document is skipped', () {
      final out = parseNotes([
        (id: 'ok', data: {'category': 'good', 'chapterIndex': 0, 'startParagraph': 0, 'startOffset': 0, 'text': 'hello', 'bookTitle': 'T', 'bookKey': 'b', 'level': 'l'}),
        (id: 'bad1', data: {'category': 'epic', 'chapterIndex': 0, 'startParagraph': 0, 'startOffset': 0, 'text': 'x'}),
        (id: 'bad2', data: {'category': 'good', 'text': 'x'}),
        (id: 'bad3', data: {'category': 'good', 'chapterIndex': 0, 'startParagraph': 0, 'startOffset': 0, 'text': '  '}),
      ]);
      expect(out.map((e) => e.id), ['ok']);
    });
  });

  // ====================================================================================== the Notes screens (UI)
  Future<FakeFirebaseFirestore> notesDb() async {
    final fs = FakeFirebaseFirestore();
    Future<void> hl(String id, String uid, String book, String title, HighlightCategory c, int ch, int p, int o, String text, {String note = ''}) =>
        fs.collection('bookHighlights').doc(id).set({
          'uid': uid, 'bookKey': book, 'level': 'level-1', 'bookTitle': title,
          'chapterIndex': ch, 'startParagraph': p, 'startOffset': o, 'endParagraph': p, 'endOffset': o + text.length,
          'text': text, 'textLength': text.length, 'snippetStart': text, 'snippetEnd': text,
          'category': c.key, 'note': note,
        });
    // GOOD: Gita has three (stored out of reading order), Nectar one
    await hl('g3', 'u1', 'book_1', 'Bhagavad-gita As It Is', HighlightCategory.good, 4, 1, 0, 'Third in the book.', note: 'My third note.');
    await hl('g1', 'u1', 'book_1', 'Bhagavad-gita As It Is', HighlightCategory.good, 0, 2, 5, 'First in the book.', note: List.generate(80, (i) => 'Long note line $i.').join('\n'));
    await hl('g2', 'u1', 'book_1', 'Bhagavad-gita As It Is', HighlightCategory.good, 2, 0, 0, 'Second in the book, no note.');
    await hl('n1', 'u1', 'book_4', 'Nectar of Instruction', HighlightCategory.good, 1, 0, 0, 'A line from the Nectar.');
    // EXCELLENT: one book
    await hl('e1', 'u1', 'book_2', 'Sri Isopanisad', HighlightCategory.excellent, 0, 0, 0, 'Excellent line.', note: 'Excellent note.');
    // somebody else's: never shown
    await hl('x1', 'u2', 'book_9', 'Another Student Book', HighlightCategory.rare, 0, 0, 0, 'Not mine.', note: 'private');
    return fs;
  }

  group('Books -> Notes', () {
    testWidgets('a 2 x 2 area: GOOD and EXCELLENT squares on top, RARE a wide rectangle under them, in the highlight colours', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      final good = tester.getRect(find.byKey(const ValueKey('notes-good')));
      final excellent = tester.getRect(find.byKey(const ValueKey('notes-excellent')));
      final rare = tester.getRect(find.byKey(const ValueKey('notes-rare')));
      expect((good.width - good.height).abs(), lessThan(1), reason: 'GOOD is square');
      expect((excellent.width - excellent.height).abs(), lessThan(1), reason: 'EXCELLENT is square');
      expect((good.width - excellent.width).abs(), lessThan(1));
      expect(good.left, lessThan(excellent.left), reason: 'GOOD top-left, EXCELLENT top-right');
      expect((good.top - excellent.top).abs(), lessThan(1));
      expect(rare.top, greaterThan(good.bottom), reason: 'RARE across the bottom');
      expect(rare.width, closeTo(good.width + excellent.width + 12, 14), reason: 'as wide as both squares together');
      expect(rare.height, lessThan(rare.width / 2), reason: 'a wide rectangle');
      expect(good.height, closeTo(good.width, 1), reason: 'a square at the normal text size');
      expect(rare.height, lessThan(rare.width / 2));
    });

    testWidgets('the app\'s tile style: gradient + pattern, frosted icon circle, arrow, title, count line, ink text', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      final expected = {
        'notes-good': (FolkGradientStyle.saffron, 'Good', '4 highlights in 2 books', Icons.star_outline_rounded),
        'notes-excellent': (FolkGradientStyle.green, 'Excellent', '1 highlight in 1 book', Icons.workspace_premium_outlined),
        'notes-rare': (FolkGradientStyle.violet, 'Rare', 'No highlights yet', Icons.auto_awesome_outlined),
      };
      for (final e in expected.entries) {
        final tile = find.byKey(ValueKey(e.key));
        expect(tile, findsOneWidget);
        final card = tester.widget<GradientCard>(find.descendant(of: tile, matching: find.byType(GradientCard)));
        expect(card.style, e.value.$1, reason: '${e.key}: gold + dots / green + leaves / violet + sparkle');
        expect(card.decorate, isTrue, reason: '${e.key}: the soft pattern is on');
        expect(find.descendant(of: tile, matching: find.byType(CustomPaint)), findsWidgets, reason: '${e.key}: the pattern is painted');
        // the frosted icon circle (top-left) with the category icon, and the small arrow circle (top-right)
        final circles = find.descendant(
            of: tile,
            matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == FolkColors.onGradientIconTile));
        expect(circles, findsNWidgets(2), reason: '${e.key}: icon circle + arrow circle');
        expect(find.descendant(of: tile, matching: find.byIcon(e.value.$4)), findsWidgets);
        expect(find.descendant(of: tile, matching: find.byIcon(Icons.north_east)), findsOneWidget);
        final tileRect = tester.getRect(tile);
        expect(tester.getTopLeft(circles.first).dx, lessThan(tileRect.left + 24), reason: '${e.key}: the icon circle is top-left');
        expect(tester.getTopRight(circles.last).dx, greaterThan(tileRect.right - 24), reason: '${e.key}: the arrow is top-right');
        // title and count, in the ink colour #1E1B2E
        final title = tester.widget<Text>(find.descendant(of: tile, matching: find.text(e.value.$2)));
        expect(title.style!.color, FolkColors.onGradient);
        final count = tester.widget<Text>(find.descendant(of: tile, matching: find.text(e.value.$3)));
        expect(count.style!.color, isNotNull);
        expect(FolkColors.onGradient, const Color(0xFF1E1B2E));
      }
      expect(find.byType(EntryAnimation), findsNWidgets(3), reason: 'the tiles come in like the other tiles');
      expect(notesCountLine(12, 3), '12 highlights in 3 books');
      expect(notesCountLine(1, 1), '1 highlight in 1 book');
      expect(notesCountLine(2, 1), '2 highlights in 1 book');
      expect(notesCountLine(0, 0), 'No highlights yet');
    });

    for (final scale in scales) {
      for (final dark in [false, true]) {
        testWidgets('tiles at text scale $scale (${dark ? 'dark' : 'light'}): both squares equal, nothing cut off, no overflow', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb()), dark: dark));
          await settle(tester);
          final good = tester.getRect(find.byKey(const ValueKey('notes-good')));
          final excellent = tester.getRect(find.byKey(const ValueKey('notes-excellent')));
          final rare = tester.getRect(find.byKey(const ValueKey('notes-rare')));
          expect(good.height, closeTo(excellent.height, .5), reason: 'the pair is as tall as the taller one');
          expect(good.height, greaterThanOrEqualTo(good.width - 1), reason: 'at least a square');
          expect(rare.top, greaterThan(good.bottom));
          for (final r in [good, excellent, rare]) {
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(360));
          }
          for (final t in ['Good', 'Excellent', 'Rare', '4 highlights in 2 books', '1 highlight in 1 book', 'No highlights yet']) {
            expect(find.text(t), findsOneWidget, reason: t);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a tap opens the category (press feedback and the tap target are the whole tile)', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('notes-rare')), matching: find.byType(PressScale)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notes-rare')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notes-empty-category')), findsOneWidget);
    });

    testWidgets('while loading: a ghost with the tiles\' own shape (two squares and a wide one), then the tiles', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      expect(find.byType(GhostPlaceholder), findsNWidgets(3));
      final ghosts = tester.widgetList<GhostPlaceholder>(find.byType(GhostPlaceholder)).toList();
      expect(ghosts[0].width, ghosts[0].height, reason: 'a square ghost');
      expect(ghosts[1].width, ghosts[1].height);
      expect(ghosts[2].width, greaterThan(ghosts[0].width! * 1.9), reason: 'the wide one');
      expect(find.byType(InsightTile), findsNothing);
      await settle(tester);
      expect(find.byType(GhostPlaceholder), findsNothing);
      expect(find.byType(InsightTile), findsNWidgets(3));
    });

    testWidgets('tap a category: only the NAMES of the books that have highlights in it, alphabetical', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notes-good')));
      await settle(tester);
      expect(find.descendant(of: find.byType(NotesBooksPage), matching: find.text('Good')), findsOneWidget, reason: 'the screen title');
      final names = [for (final t in ['Bhagavad-gita As It Is', 'Nectar of Instruction']) tester.getTopLeft(find.text(t)).dy];
      expect(names[0], lessThan(names[1]));
      expect(find.text('Sri Isopanisad'), findsNothing, reason: 'that book has no GOOD highlight');
      expect(find.text('Another Student Book'), findsNothing);
      // nothing else on this screen: no highlighted text, no note, no counts
      final here = find.byType(NotesBooksPage);
      for (final word in ['book.', 'note', 'highlight']) {
        expect(find.descendant(of: here, matching: find.textContaining(word)), findsNothing, reason: word);
      }
    });

    testWidgets('a category with nothing: an empty state', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notes-rare')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notes-empty-category')), findsOneWidget);
      expect(find.text('Another Student Book'), findsNothing);
    });

    testWidgets('tap a book: numbered cards in reading order, with the progress', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notes-good')));
      await settle(tester);
      await tester.tap(find.text('Bhagavad-gita As It Is'));
      await settle(tester);
      expect(find.text('of 3 · 33%'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('note-jump-box'))).controller!.text, '1');
      expect(tester.widget<Text>(find.byKey(const ValueKey('note-number-1'))).data, '1');
      expect(find.text('First in the book.'), findsOneWidget, reason: 'card 1 is the first passage in the book');
      expect(find.text('Third in the book.'), findsNothing, reason: 'not on screen until swiped to');
      // swipe: card 2 then card 3
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(find.text('of 3 · 67%'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('note-jump-box'))).controller!.text, '2', reason: 'the box follows the swipe');
      expect(find.text('Second in the book, no note.'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('note-number-2'))).data, '2');
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(find.text('of 3 · 100%'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('note-jump-box'))).controller!.text, '3', reason: 'the box follows the swipe');
      expect(find.text('Third in the book.'), findsOneWidget);
      // and back
      await tester.drag(find.byType(PageView), const Offset(320, 0));
      await tester.pumpAndSettle();
      expect(find.text('of 3 · 67%'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('note-jump-box'))).controller!.text, '2', reason: 'the box follows the swipe');
      final bar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('notes-progress-bar')));
      expect(bar.value, closeTo(2 / 3, 1e-9));
    });

    testWidgets('a card with a note: "View notes" opens it in a dialog; a long note scrolls; tap outside closes', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notes-good')));
      await settle(tester);
      await tester.tap(find.text('Bhagavad-gita As It Is'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('view-note-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-dialog-text')), findsOneWidget);
      expect(find.textContaining('Long note line 0.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final scroll = find.ancestor(of: find.byKey(const ValueKey('note-dialog-text')), matching: find.byType(SingleChildScrollView));
      expect(scroll, findsOneWidget);
      await tester.drag(scroll, const Offset(0, -600));
      await tester.pump();
      expect(find.textContaining('Long note line 79.'), findsOneWidget, reason: 'scrolled to the end of a long note');
      await tester.tapAt(const Offset(4, 790));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-dialog-text')), findsNothing);
      expect(find.text('of 3 · 33%'), findsOneWidget, reason: 'back on the card');
    });

    testWidgets('a short note shows in the dialog; a card without a note says "No note added" and has no button', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb())));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notes-good')));
      await settle(tester);
      await tester.tap(find.text('Bhagavad-gita As It Is'));
      await settle(tester);
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-none-2')), findsOneWidget);
      expect(find.text('No note added'), findsOneWidget);
      expect(find.byKey(const ValueKey('view-note-2')), findsNothing);
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('view-note-3')));
      await tester.pumpAndSettle();
      expect(find.text('My third note.'), findsOneWidget);
    });

    testWidgets('no notes in a book: an empty state', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const NotesCardsPage(category: HighlightCategory.good, book: NoteBook(bookId: 'x', title: 'Empty Book', entries: []))));
      await settle(tester);
      expect(find.byKey(const ValueKey('notes-empty-book')), findsOneWidget);
    });

    testWidgets('no highlights at all: every tile says 0 and each category is empty', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: FakeFirebaseFirestore())));
      await settle(tester);
      expect(find.text('No highlights yet'), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('notes-excellent')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notes-empty-category')), findsOneWidget);
    });

    testWidgets('a load that fails says so with Retry', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: _Flaky(await notesDb(), 1))));
      await settle(tester);
      expect(find.byType(FolkErrorRetry), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.byKey(const ValueKey('notes-good')), findsOneWidget);
    });
  });

  // ====================================================================================== text size, light / dark, real fonts
  for (final scale in scales) {
    for (final dark in [false, true]) {
      final s = 'text scale $scale, ${dark ? 'dark' : 'light'}';

      testWidgets('History: rows, an open day — $s', (tester) async {
        phone(tester, scale);
        final fs = FakeFirebaseFirestore();
        await fs.collection('readingDays').doc('u1_20261019').set(dayDoc('u1', 20261019, {'A very long book title that has to wrap onto more than one line on a small phone': 1800, 'Nectar': 900}));
        await fs.collection('readingDays').doc('u1_20261018').set(dayDoc('u1', 20261018, {'Gita': 600}));
        await tester.pumpWidget(host(BooksHistoryPage(uid: 'u1', firestore: fs), dark: dark));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('day-header-20261019')));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Notes: tiles, books, cards, dialog — $s', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: await notesDb()), dark: dark));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('notes-good')));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Bhagavad-gita As It Is'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('view-note-1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
