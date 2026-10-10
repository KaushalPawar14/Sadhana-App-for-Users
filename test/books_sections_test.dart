// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookPageList.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BookCurrentBook.dart';
import 'package:folk_app/utils/BookLibrary.dart';
import 'package:folk_app/utils/BookSections.dart';
import 'package:folk_app/widgets/BookLevelSection.dart';
import 'package:folk_app/widgets/CompletedBookTile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The Books screen, final structure: Current books, Levels 1-3 (not started
// only), Completed books (titles only) — each a closed, lazy section; and the
// "Mark as already completed" flow.
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

late SharedPreferences prefs;

BookDocs docs() => {
      'level-1': {
        'book_1': 'CURRENT ONE',
        'book_2': 'DONE BY END DATE',
        'book_3': 'DONE BY BUTTON',
        'book_4': 'DONE BY GUIDE',
        'book_5': 'NOT STARTED FIVE',
      },
      'level-2': {'book_1': 'LEVEL TWO FRESH'},
      'level-3': <String, dynamic>{},
      'level-1_links': {
        for (var i = 1; i <= 5; i++) 'book_$i': 'https://example.invalid/en$i',
      },
      'level-2_links': {'book_1': 'https://example.invalid/l2-1'},
    };

Map<String, dynamic> entry(String level, String key,
        {bool current = false, String? endDate, bool? finishedViaButton, String? endedBy, String? commitment, String? title}) =>
    {
      'uid': 'u1',
      'level': level,
      'bookKey': key,
      if (title != null) 'bookTitle': title,
      'isCurrentBook': current,
      'startDate': '2026-09-01',
      'madeNotes': true,
      if (endDate != null) 'endDate': endDate,
      if (finishedViaButton != null) 'finishedViaButton': finishedViaButton,
      if (endedBy != null) 'endedBy': endedBy,
      if (commitment != null) 'commitmentDate': commitment,
    };

List<Map<String, dynamic>> entries() => [
      entry('level-1', 'book_1', current: true, commitment: '2026-12-01'),
      entry('level-1', 'book_2', current: true, endDate: '2026-08-10'), // the real-data bug combination
      entry('level-1', 'book_3', finishedViaButton: true),
      entry('level-1', 'book_4', endedBy: 'guide'),
      entry('level-1', 'book_5', current: false),
      entry('level-1', 'book_99', current: true, commitment: '2026-12-02', title: 'ORPHAN CURRENT'),
    ];

class Rig {
  Rig({List<Map<String, dynamic>>? entries, BookDocs? books}) {
    library = BookLibrary(
      booksStream: booksController.stream,
      entriesStream: entriesController.stream,
      loadPrefs: () async => prefs,
    );
    if (books != null) booksController.add(books);
    if (entries != null) entriesController.add(entries);
  }
  final booksController = StreamController<BookDocs>();
  final entriesController = StreamController<List<Map<String, dynamic>>>();
  late final BookLibrary library;
}

class Writes {
  final List<Map<String, String>> calls = [];
  bool result = true;
  Future<bool> call({required String uid, required String level, required String bookKey, required String title, required String today}) async {
    calls.add({'uid': uid, 'level': level, 'bookKey': bookKey, 'title': title, 'today': today});
    return result;
  }
}

Future<(Rig, Writes)> pump(WidgetTester tester, {List<Map<String, dynamic>>? data, double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  final rig = Rig(entries: data ?? entries(), books: docs());
  final writes = Writes();
  await tester.pumpWidget(host(BooksSelectionScreen(library: rig.library, uid: 'u1', markCompleted: writes.call), dark: dark));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return (rig, writes);
}

// A section's header (its first InkWell); the level name also appears as a badge on book cards.
Finder section(String title) => find.byWidgetPredicate((w) => w is BookLevelSection && w.title == title);
Finder header(String title) => find.descendant(of: section(title), matching: find.byType(InkWell)).first;

Future<void> open(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(section(title), 200, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(header(title));
  await tester.pump();
  await tester.tap(header(title));
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('classification: a book is in exactly one section', () {
    test('every book lands in exactly one; current and completed never appear in a level', () {
      final titles = {
        'level-1': [for (var i = 1; i <= 5; i++) MapEntry('book_$i', docs()['level-1']!['book_$i'] as String)],
        'level-2': [const MapEntry('book_1', 'LEVEL TWO FRESH')],
        'level-3': <MapEntry<String, String>>[],
      };
      final s = classifyBooks(levels: ['level-1', 'level-2', 'level-3'], titlesByLevel: titles, entries: entries());
      String id(BookRow r) => '${r.level}:${r.bookKey}';
      final current = s.current.map(id).toList();
      final completed = s.completed.map(id).toList();
      final notStarted = [for (final l in s.notStartedByLevel.values) ...l.map(id)];
      expect(current, ['level-1:book_1', 'level-1:book_99']);
      expect(completed, ['level-1:book_2', 'level-1:book_3', 'level-1:book_4'], reason: 'end date, finishedViaButton and endedBy all count; end date beats isCurrentBook');
      expect(notStarted..sort(), ['level-1:book_5', 'level-2:book_1']);
      final all = [...current, ...completed, ...notStarted];
      expect(all.toSet().length, all.length, reason: 'no book twice');
      expect(all.length, 7);
      expect(s.bookCountByLevel, {'level-1': 5, 'level-2': 1, 'level-3': 0});
      for (final r in s.current) {
        expect(isBookCompleted(r.entry), isFalse);
      }
    });

    test('a record that is neither current nor completed is not started; a stray record with no title is ignored', () {
      final s = classifyBooks(
        levels: ['level-1'],
        titlesByLevel: {'level-1': [const MapEntry('book_1', 'A')]},
        entries: [entry('level-1', 'book_1', current: false), entry('level-1', 'book_7', current: true)],
      );
      expect(s.notStartedByLevel['level-1']!.map((r) => r.bookKey), ['book_1']);
      expect(s.current, isEmpty, reason: 'book_7 is not offered and has no stored title');
    });
  });

  group('screen structure', () {
    testWidgets('top to bottom: Current books, Levels 1-3, Completed books · N; all start CLOSED and build nothing', (tester) async {
      await pump(tester);
      final titles = tester.widgetList<BookLevelSection>(find.byType(BookLevelSection)).map((w) => w.title).toList();
      expect(titles, ['Current books', 'Level 1', 'Level 2', 'Level 3', 'Completed books · 3']);
      expect(find.text('2 books'), findsOneWidget, reason: 'Current books header count');
      expect(find.text('1 book'), findsNWidgets(2), reason: 'Level 1 and Level 2 each have one book to start');
      expect(find.text('0 books'), findsOneWidget, reason: 'Level 3');
      // closed: not one book card, title or button is built
      for (final t in ['CURRENT ONE', 'ORPHAN CURRENT', 'NOT STARTED FIVE', 'LEVEL TWO FRESH', 'DONE BY END DATE', 'DONE BY BUTTON', 'DONE BY GUIDE']) {
        expect(find.text(t), findsNothing, reason: '$t is not built while closed');
      }
      expect(find.text('Read'), findsNothing);
      expect(find.text('Update'), findsNothing);
      expect(find.byType(CompletedBookTile), findsNothing);
    });

    testWidgets('empty Current and Completed sections are not there at all', (tester) async {
      await pump(tester, data: [entry('level-1', 'book_5')]);
      final titles = tester.widgetList<BookLevelSection>(find.byType(BookLevelSection)).map((w) => w.title).toList();
      expect(titles, ['Level 1', 'Level 2', 'Level 3']);
    });

    testWidgets('Level sections list ONLY books that are neither current nor completed', (tester) async {
      await pump(tester);
      await open(tester, 'Level 1');
      expect(find.text('NOT STARTED FIVE'), findsOneWidget);
      for (final t in ['CURRENT ONE', 'DONE BY END DATE', 'DONE BY BUTTON', 'DONE BY GUIDE']) {
        expect(find.text(t), findsNothing, reason: '$t belongs to another section');
      }
      expect(find.text('Not Started'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      await open(tester, 'Level 3');
      expect(find.text('No books found for this level'), findsOneWidget);
    });

    testWidgets('a level whose books are all started or completed says so', (tester) async {
      await pump(tester, data: [entry('level-2', 'book_1', current: true, commitment: '2026-12-01')]);
      await open(tester, 'Level 2');
      expect(find.text('Every book in this level is current or completed'), findsOneWidget);
    });

    testWidgets('Current books: the FULL existing card for each current book (status, dates, commitment, notes, Read, Update)', (tester) async {
      await pump(tester);
      await open(tester, 'Current books');
      expect(find.text('CURRENT ONE'), findsOneWidget);
      expect(find.text('ORPHAN CURRENT'), findsOneWidget, reason: 'a current book the level list no longer offers is still shown');
      expect(find.text('DONE BY END DATE'), findsNothing, reason: 'completed wins over isCurrentBook');
      expect(find.text('Current Book'), findsNWidgets(2));
      expect(find.text('Committed to finish by 2026-12-01'), findsOneWidget);
      expect(find.text('Notes made'), findsNWidgets(2));
      expect(find.text('Started 2026-09-01'), findsNWidgets(2));
      expect(find.text('Read'), findsNWidgets(2));
      expect(find.text('Update'), findsNWidgets(2));
    });

    testWidgets('Current books: tapping the title opens the reader with the same arguments as Read; no dialog', (tester) async {
      await pump(tester);
      await open(tester, 'Current books');
      await tester.tap(find.text('CURRENT ONE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      final page = tester.widget<BookReaderPage>(find.byType(BookReaderPage));
      expect(page.dropboxUrl, 'https://example.invalid/en1');
      expect(page.bookTitle, 'CURRENT ONE');
      expect(page.bookKey, 'book_1');
      expect(page.level, 'level-1');
      expect(page.uid, 'u1');
    });

    testWidgets('Completed books: TITLES ONLY (no status, dates, Read, Update, mark-completed control); header shows the count', (tester) async {
      await pump(tester);
      expect(section('Completed books · 3'), findsOneWidget);
      await open(tester, 'Completed books · 3');
      expect(find.byType(CompletedBookTile), findsNWidgets(3));
      for (final t in ['DONE BY END DATE', 'DONE BY BUTTON', 'DONE BY GUIDE']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('Read'), findsNothing);
      expect(find.text('Update'), findsNothing);
      expect(find.text('Completed'), findsNothing, reason: 'no status chip');
      expect(find.textContaining('Started'), findsNothing, reason: 'no dates');
      expect(find.byTooltip('Mark as already completed'), findsNothing);
    });

    testWidgets('Completed books: tapping a title opens that book in the reader; no commitment-date dialog', (tester) async {
      await pump(tester);
      await open(tester, 'Completed books · 3');
      await tester.tap(find.text('DONE BY BUTTON'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing, reason: 'no prompt for a completed book');
      final page = tester.widget<BookReaderPage>(find.byType(BookReaderPage));
      expect(page.dropboxUrl, 'https://example.invalid/en3');
      expect(page.bookTitle, 'DONE BY BUTTON');
      expect(page.bookKey, 'book_3');
      expect(page.level, 'level-1');
      expect(page.uid, 'u1');
    });

    testWidgets('the control is on every card in Current books and the Levels, and not on Completed', (tester) async {
      await pump(tester);
      await open(tester, 'Current books');
      expect(find.byTooltip('Mark as already completed'), findsNWidgets(2));
      await open(tester, 'Level 1');
      expect(find.byTooltip('Mark as already completed'), findsNWidgets(3));
      for (final b in tester.widgetList<IconButton>(find.byType(IconButton))) {
        if (b.tooltip == 'Mark as already completed') {
          expect(b.constraints!.minWidth, greaterThanOrEqualTo(48));
          expect(b.constraints!.minHeight, greaterThanOrEqualTo(48));
        }
      }
    });
  });

  group('Mark as already completed', () {
    testWidgets('asks first; Cancel writes nothing', (tester) async {
      final (_, writes) = await pump(tester);
      await open(tester, 'Level 1');
      await tester.tap(find.byTooltip('Mark as already completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Mark 'NOT STARTED FIVE' as completed? Today's date will be saved as the end date."), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Mark completed'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(writes.calls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('NOT STARTED FIVE'), findsOneWidget, reason: 'still where it was');
    });

    testWidgets('Mark completed: ONE write with today as the end date; the book moves to Completed at once', (tester) async {
      final (rig, writes) = await pump(tester);
      await open(tester, 'Level 1');
      await tester.tap(find.byTooltip('Mark as already completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Mark completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(writes.calls.length, 1, reason: 'one write');
      final c = writes.calls.single;
      expect(c['uid'], 'u1');
      expect(c['level'], 'level-1');
      expect(c['bookKey'], 'book_5');
      expect(c['title'], 'NOT STARTED FIVE');
      expect(c['today'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')), reason: 'same yyyy-MM-dd as every other end date');
      expect(c['today'], DateTime.now().toIso8601String().split('T')[0]);
      expect(find.text('Marked as completed'), findsOneWidget);
      addTearDown(() {});

      // Firestore now reports the new record: the book leaves Level 1 and joins Completed.
      rig.entriesController.add([
        ...entries().where((e) => e['bookKey'] != 'book_5'),
        {
          'uid': 'u1', 'level': 'level-1', 'bookKey': 'book_5', 'bookTitle': 'NOT STARTED FIVE',
          'endDate': c['today'], 'isCurrentBook': false, 'startDate': c['today'],
        },
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('NOT STARTED FIVE'), findsNothing, reason: 'gone from Level 1');
      expect(section('Completed books · 4'), findsOneWidget);
      expect(find.text('0 books'), findsNWidgets(2), reason: 'Level 1 (all started or done) and Level 3');
      await open(tester, 'Completed books · 4');
      expect(find.text('NOT STARTED FIVE'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a book with no record yet (never started) can be marked too', (tester) async {
      final (_, writes) = await pump(tester);
      await open(tester, 'Level 2');
      await tester.tap(find.byTooltip('Mark as already completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Mark completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(writes.calls.single['bookKey'], 'book_1');
      expect(writes.calls.single['level'], 'level-2');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('an already-completed book is left alone: told so, nothing overwritten', (tester) async {
      final (_, writes) = await pump(tester);
      writes.result = false; // the write found a completion already on record
      await open(tester, 'Level 1');
      await tester.tap(find.byTooltip('Mark as already completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Mark completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('This book is already completed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    group('the write itself (alreadyCompletedFields)', () {
      const today = '2026-10-10';
      Map<String, Object?>? f(Map<String, dynamic>? latest) => alreadyCompletedFields(
            latest: latest, uid: 'u1', level: 'level-1', bookKey: 'book_5', title: 'T', today: today);

      test('a book with no record: identifying fields + endDate + isCurrentBook false + startDate today', () {
        expect(f(null), {'uid': 'u1', 'level': 'level-1', 'bookKey': 'book_5', 'bookTitle': 'T', 'endDate': today, 'isCurrentBook': false, 'startDate': today});
      });

      test('an existing start date is kept (not written); a current book becomes not current in the same write', () {
        final w = f({'isCurrentBook': true, 'startDate': '2026-09-01', 'commitmentDate': '2026-12-01'})!;
        expect(w['endDate'], today);
        expect(w['isCurrentBook'], false);
        expect(w.containsKey('startDate'), isFalse);
        expect(w.containsKey('commitmentDate'), isFalse, reason: 'nothing else is touched');
      });

      test('never overwrites an existing end date or completion mark', () {
        expect(f({'endDate': '2026-08-10'}), isNull);
        expect(f({'finishedViaButton': true}), isNull);
        expect(f({'endedBy': 'guide'}), isNull);
        expect(f({'endDate': '  ', 'isCurrentBook': true}), isNotNull, reason: 'a blank end date is not an end date');
      });
    });
  });

  group('end date sources set isCurrentBook false in the same write (source check)', () {
    test('reader Finish, Guide Mark finished, update sheet, already-completed', () {
      final reader = File('lib/pages/BookReaderPage.dart').readAsStringSync();
      final r = reader.substring(reader.indexOf("'endDate': today,"), reader.indexOf("'endDate': today,") + 300);
      expect(r, contains("'isCurrentBook': false"));
      final guide = File('../../Guides/Sadhana-App-for-Admin/lib/Home/FolkBoysWorkspace.dart').readAsStringSync();
      final g = guide.substring(guide.indexOf("'endDate': today,"), guide.indexOf("'endDate': today,") + 200);
      expect(g, contains("'isCurrentBook': false"));
      final books = File('lib/pages/BookPageList.dart').readAsStringSync();
      expect(books, contains("'isCurrentBook': resolvedCurrent"));
      expect(File('lib/utils/BookCurrentBook.dart').readAsStringSync(), contains("'isCurrentBook': false"));
    });

    test('Firestore write sites in BookPageList: before and after', () {
      int count(String src) {
        final code = src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
        return RegExp(r'\.set\(|\.update\(|tx\.set\(|\.delete\(').allMatches(code).length;
      }

      final after = count(File('lib/pages/BookPageList.dart').readAsStringSync());
      final beforeFile = File('D:/tmp-fl/g9before/BookPageList.before_restructure.dart');
      if (beforeFile.existsSync()) {
        final before = count(beforeFile.readAsStringSync());
        // ignore: avoid_print
        print('WRITE SITES in BookPageList.dart: before $before, after $after (the one new write is the already-completed transaction)');
        expect(after, before + 1);
      }
    });
  });

  group('every section at every text size', () {
    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: all five sections open, no overflow', (tester) async {
          await pump(tester, scale: scale, dark: dark);
          for (final t in ['Current books', 'Level 1', 'Level 2', 'Level 3', 'Completed books · 3']) {
            await open(tester, t);
            expect(tester.takeException(), isNull, reason: '$t dark=$dark scale=$scale');
          }
          expect(find.text('Read'), findsWidgets);
          expect(find.byType(CompletedBookTile), findsNWidgets(3));
          // the control stays a full touch target at any size
          for (final b in tester.widgetList<IconButton>(find.byType(IconButton))) {
            if (b.tooltip == 'Mark as already completed') {
              expect(tester.getSize(find.byWidget(b)).height, greaterThanOrEqualTo(48));
            }
          }
        });
      }
    }
  });
}
