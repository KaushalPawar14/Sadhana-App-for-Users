// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookPageList.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/BookCurrentBook.dart';
import 'package:folk_app/utils/BookLibrary.dart';
import 'package:folk_app/utils/ReadingLanguages.dart';
import 'package:folk_app/widgets/BookLevelSection.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/LanguageButton.dart';
import 'package:folk_app/widgets/PodcastLoadingGhost.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Master fix 2, parts 3-5: the language button, the Podcast loading state, the
// Books list (current books strip, closed lazy sections, fast open) and the
// "Current Book" rule.
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
      'level-1': {'book_1': 'ON THE WAY TO KRSNA', 'book_2': 'BEYOND BIRTH AND DEATH', 'book_3': 'THE SCIENCE OF SELF REALIZATION'},
      'level-2': {'book_1': 'BASICS OF BHAGAVAD GITA'},
      'level-3': <String, dynamic>{},
      'level-1_links': {'book_1': 'https://example.invalid/en1', 'book_2': 'https://example.invalid/en2', 'book_3': 'https://example.invalid/en3'},
      'level-2_links': {'book_1': 'https://example.invalid/en-l2-1'},
      'level-1_links_hi': {'book_1': 'https://example.invalid/hi1'},
    };

Map<String, dynamic> entry(String level, String key, {bool current = false, String? endDate, bool? finishedViaButton, String? endedBy, String? commitment = '2026-12-01', String? title}) => {
      'uid': 'u1',
      'level': level,
      'bookKey': key,
      if (title != null) 'bookTitle': title,
      'isCurrentBook': current,
      if (endDate != null) 'endDate': endDate,
      if (finishedViaButton != null) 'finishedViaButton': finishedViaButton,
      if (endedBy != null) 'endedBy': endedBy,
      if (commitment != null) 'commitmentDate': commitment,
    };

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

Future<Rig> pumpBooks(WidgetTester tester, {List<Map<String, dynamic>>? entries, double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  final rig = Rig(entries: entries ?? [], books: docs());
  await tester.pumpWidget(host(BooksSelectionScreen(library: rig.library, uid: 'u1'), dark: dark));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return rig;
}

// A section's header title (the level name also appears as a label on book rows).
Finder section(String title) => find.byWidgetPredicate((w) => w is BookLevelSection && w.title == title);
Finder header(String level) => find.descendant(of: section(level), matching: find.byType(InkWell)).first;

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

  // ============================================================ language button
  group('Language button', () {
    test('cycles English, Hindi, Gujarati, Telugu, English (kSupportedLanguages order)', () {
      expect(kReadingLanguages.keys.toList(), ['en', 'hi', 'gu', 'te']);
      for (final path in ['lib/pages/BookPageList.dart', 'lib/pages/PodcastModulesScreen.dart']) {
        expect(File(path).readAsStringSync(), contains('kSupportedLanguages = kReadingLanguages'), reason: '$path uses the one shared list');
      }
      var c = 'en';
      final seen = <String>[];
      for (var i = 0; i < 5; i++) {
        c = nextReadingLanguage(c);
        seen.add(c);
      }
      expect(seen, ['hi', 'gu', 'te', 'en', 'hi']);
      expect(nextReadingLanguage('xx'), 'en', reason: 'unknown starts again from English');
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: shows the mark, is 48 dp, never overflows, names the language', (tester) async {
          phone(tester, scale);
          final changes = <String>[];
          var lang = 'en';
          late StateSetter set;
          await tester.pumpWidget(host(
            Scaffold(
              body: Center(
                child: StatefulBuilder(builder: (context, setState) {
                  set = setState;
                  return LanguageButton(language: lang, onChanged: (v) => changes.add(v));
                }),
              ),
            ),
            dark: dark,
          ));
          for (final code in ['en', 'hi', 'gu', 'te']) {
            set(() => lang = code);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(find.text(kReadingLanguageMarks[code]!), findsOneWidget);
            final box = tester.getSize(find.byType(LanguageButton));
            expect(box.width, greaterThanOrEqualTo(48));
            expect(box.height, greaterThanOrEqualTo(48));
            // the mark stays inside the 44 dp circle
            final mark = tester.getRect(find.text(kReadingLanguageMarks[code]!));
            expect(mark.width, lessThanOrEqualTo(44));
            expect(mark.height, lessThanOrEqualTo(44));
            final name = kReadingLanguages[code]!;
            expect(find.byTooltip(name), findsOneWidget, reason: 'tooltip with the full name');
            final next = kReadingLanguages[nextReadingLanguage(code)]!;
            expect(find.bySemanticsLabel('Language: $name. Tap to change to $next'), findsOneWidget);
          }
          set(() => lang = 'en');
          await tester.pump();
          await tester.tap(find.byType(LanguageButton));
          expect(changes, ['hi']);
        });
      }
    }

    testWidgets('Books: one button in the top bar, no language box; a tap moves to the next language', (tester) async {
      await pumpBooks(tester);
      expect(find.byType(LanguageButton), findsOneWidget);
      expect(find.text('Reading language'), findsNothing, reason: 'the big selector box is gone');
      expect(find.text('English'), findsNothing);
      expect(find.text('EN'), findsOneWidget);
      await tester.tap(find.byType(LanguageButton));
      await tester.pump();
      expect(find.text('हि'), findsOneWidget);
      await tester.tap(find.byType(LanguageButton));
      await tester.pump();
      expect(find.text('ગુ'), findsOneWidget);
      await tester.tap(find.byType(LanguageButton));
      await tester.pump();
      expect(find.text('తె'), findsOneWidget);
      await tester.tap(find.byType(LanguageButton));
      await tester.pump();
      expect(find.text('EN'), findsOneWidget);
    });

    test('the standing-preference write is unchanged: one `readingPrefs.language` write on each screen, same field', () {
      for (final path in ['lib/pages/BookPageList.dart', 'lib/pages/PodcastModulesScreen.dart']) {
        final src = File(path).readAsStringSync();
        expect(RegExp(r"'readingPrefs': \{'language': language\}").allMatches(src).length, 1, reason: path);
      }
      // before this change both screens had exactly one such write too
      for (final path in ['D:/tmp-fl/g9before/BookPageList.dart', 'D:/tmp-fl/g9before/PodcastModulesScreen.dart']) {
        if (File(path).existsSync()) {
          expect(RegExp(r"'readingPrefs': \{'language': language\}").allMatches(File(path).readAsStringSync()).length, 1, reason: path);
        }
      }
    });
  });

  // ============================================================ podcast loading
  group('Podcast loading state', () {
    test('the Podcast top bar has the language button and the big selector box is gone', () {
      final src = File('lib/pages/PodcastModulesScreen.dart').readAsStringSync();
      expect(src, contains('LanguageButton(language: _language, onChanged: _setLanguage)'));
      expect(src.contains('_languageSelector'), isFalse);
      expect(src.contains('Listening language'), isFalse);
      expect(src, contains('PodcastLoadingGhost()'));
      final books = File('lib/pages/BookPageList.dart').readAsStringSync();
      expect(books, contains('LanguageButton(language: _language, onChanged: _setLanguage)'));
      expect(books.contains('_languageSelector'), isFalse);
      expect(books.contains('Reading language'), isFalse);
    });

    testWidgets('ROOT CAUSE: the old ghost row (four 84 dp chips + three 8 dp gaps = 360 dp) overflowed the 320 dp of room at 360 dp', (tester) async {
      phone(tester, 1.0);
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);
      await tester.pumpWidget(host(Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FolkSpace.pagePadding),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: FolkSpace.sm),
                const GhostPlaceholder(width: 84, height: FolkShape.chipHeight, radius: 20, showBars: false),
              ],
            ],
          ),
        ),
      )));
      await tester.pump();
      expect(errors.any((e) => e.exceptionAsString().contains('overflowed by 40')), isTrue,
          reason: 'RenderFlex overflowed by 40 px on the right');
      FlutterError.onError = old;
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: the loading state fits 360 dp with no overflow', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host(const Scaffold(body: PodcastLoadingGhost()), dark: dark, reduce: false));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: 'dark=$dark scale=$scale');
          expect(find.byType(GhostPlaceholder), findsWidgets);
          for (final r in tester.widgetList<GhostPlaceholder>(find.byType(GhostPlaceholder))) {
            final rect = tester.getRect(find.byWidget(r));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(360));
          }
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        });
      }
    }
  });

  // ============================================================ current book rule
  group('"Current Book" means current AND not completed', () {
    test('isBookCompleted / isCurrentBookEntry truth table', () {
      expect(isCurrentBookEntry(entry('level-1', 'book_1', current: true)), isTrue);
      expect(isCurrentBookEntry(entry('level-1', 'book_1', current: true, endDate: '2026-09-30')), isFalse, reason: 'end date');
      expect(isCurrentBookEntry(entry('level-1', 'book_1', current: true, endDate: '  ')), isTrue, reason: 'a blank end date is not an end date');
      expect(isCurrentBookEntry(entry('level-1', 'book_1', current: true, finishedViaButton: true)), isFalse, reason: 'student marked it finished');
      expect(isCurrentBookEntry(entry('level-1', 'book_1', current: true, endedBy: 'guide')), isFalse, reason: 'guide marked it finished');
      expect(isCurrentBookEntry(entry('level-1', 'book_1', current: false)), isFalse);
      expect(isCurrentBookEntry(null), isFalse);
      expect(isBookCompleted(entry('level-1', 'book_1', endDate: '2026-09-30')), isTrue);
      expect(isBookCompleted(entry('level-1', 'book_1')), isFalse);
    });
  });

  // ============================================================ sections
  group('Level sections', () {
    testWidgets('all three start CLOSED and build no book cards', (tester) async {
      await pumpBooks(tester);
      expect(find.byType(BookLevelSection), findsNWidgets(3));
      expect(section('Level 1'), findsOneWidget);
      expect(find.text('3 books'), findsOneWidget);
      expect(find.text('Read'), findsNothing);
      expect(find.text('Update'), findsNothing);
      expect(find.text('ON THE WAY TO KRSNA'), findsNothing);
    });

    testWidgets('a section builds its book cards only while open', (tester) async {
      var builds = 0;
      phone(tester, 1.0);
      await tester.pumpWidget(host(
        Scaffold(
          body: BookLevelSection(
            title: 'Level 1',
            subtitle: '3 books',
            bodyBuilder: (context) {
              builds++;
              return const SizedBox(height: 300, child: Text('cards'));
            },
          ),
        ),
        reduce: false,
      ));
      expect(builds, 0, reason: 'closed: nothing built');
      expect(find.text('cards'), findsNothing);
      await tester.tap(find.text('Level 1'));
      await tester.pump();
      expect(builds, greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.text('cards'), findsOneWidget);
      await tester.tap(find.text('Level 1'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('cards'), findsNothing, reason: 'closed again: contents dropped');
      final after = builds;
      await tester.pump(const Duration(seconds: 1));
      expect(builds, after, reason: 'a closed section is not rebuilt');
    });

    testWidgets('opens and closes smoothly: the height moves in steps, not in one jump', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(
        const Scaffold(body: Align(alignment: Alignment.topCenter, child: BookLevelSection(title: 'Level 1', subtitle: '3 books', bodyBuilder: _tall))),
        reduce: false,
      ));
      final closed = tester.getSize(find.byType(BookLevelSection)).height;
      await tester.tap(find.text('Level 1'));
      final heights = <double>[];
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        heights.add(tester.getSize(find.byType(BookLevelSection)).height);
      }
      await tester.pumpAndSettle();
      final open = tester.getSize(find.byType(BookLevelSection)).height;
      expect(open, greaterThan(closed + 250));
      expect(heights[1], greaterThan(closed));
      expect(heights[1], lessThan(open));
      for (var i = 1; i < heights.length; i++) {
        expect(heights[i], greaterThanOrEqualTo(heights[i - 1]), reason: 'opening only grows');
      }
      expect(heights.toSet().length, greaterThan(3), reason: 'many distinct in-between heights');
      await tester.tap(find.text('Level 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getSize(find.byType(BookLevelSection)).height;
      expect(mid, lessThan(open));
      expect(mid, greaterThan(closed));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(BookLevelSection)).height, closed);
    });

    testWidgets('a section that is open stays open when the Current books section appears above it', (tester) async {
      phone(tester, 1.0);
      final rig = Rig(books: docs(), entries: const []); // progress read: nothing current yet
      await tester.pumpWidget(host(BooksSelectionScreen(library: rig.library, uid: 'u1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(header('Level 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Read'), findsWidgets);
      rig.entriesController.add([entry('level-1', 'book_1', current: true)]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Current books'), findsOneWidget);
      expect(find.text('Read'), findsWidgets, reason: 'Level 1 is still open');
      rig.entriesController.add(const []); // and when it goes away again
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Current books'), findsNothing);
      expect(find.text('Read'), findsWidgets, reason: 'still open');
    });

    testWidgets('reduce motion: open and close are instant', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const Scaffold(body: BookLevelSection(title: 'Level 1', subtitle: 's', bodyBuilder: _tall))));
      await tester.tap(find.text('Level 1'));
      await tester.pump();
      expect(find.text('cards'), findsOneWidget);
      await tester.tap(find.text('Level 1'));
      await tester.pump();
      expect(find.text('cards'), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, scale $scale: sections open with book cards, no overflow', (tester) async {
          await pumpBooks(tester, entries: [entry('level-1', 'book_1', current: true)], scale: scale, dark: dark);
          for (final level in ['Level 1', 'Level 2', 'Level 3']) {
            await tester.scrollUntilVisible(section(level), 200, scrollable: find.byType(Scrollable).first);
            await tester.ensureVisible(header(level));
            await tester.pump();
            await tester.tap(header(level));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(tester.takeException(), isNull, reason: 'dark=$dark scale=$scale');
          expect(find.text('Read'), findsWidgets);
          await tester.scrollUntilVisible(find.text('No books found for this level'), 200, scrollable: find.byType(Scrollable).first);
          expect(find.text('No books found for this level'), findsOneWidget);
        });
      }
    }
  });

  // ============================================================ speed
  group('Books list speed', () {
    test('TIMING: both reads at once (new) vs one after the other (old), at 300 ms each; and the cached copy', () async {
      const latency = Duration(milliseconds: 300);
      Stream<T> slow<T>(T value) async* {
        await Future<void>.delayed(latency);
        yield value;
      }

      // OLD: the second read only began once the screen had been built from the first.
      final oldWatch = Stopwatch()..start();
      await slow<BookDocs>(docs()).first;
      await slow<List<Map<String, dynamic>>>([entry('level-1', 'book_1', current: true)]).first;
      final oldMs = oldWatch.elapsedMilliseconds;

      // NEW: both listened to at once; the titles are shown the moment they arrive.
      final newWatch = Stopwatch()..start();
      final lib = BookLibrary(
        booksStream: slow<BookDocs>(docs()),
        entriesStream: slow<List<Map<String, dynamic>>>([entry('level-1', 'book_1', current: true)]),
        loadPrefs: () async => prefs,
      );
      final firstContent = Completer<int>();
      final allContent = Completer<int>();
      lib.addListener(() {
        if (lib.books != null && !firstContent.isCompleted) firstContent.complete(newWatch.elapsedMilliseconds);
        if (lib.books != null && lib.entriesLoaded && !allContent.isCompleted) allContent.complete(newWatch.elapsedMilliseconds);
      });
      final firstMs = await firstContent.future;
      final allMs = await allContent.future;

      // NEXT VISIT: the cached copy of the titles is there before either read answers.
      await Future<void>.delayed(const Duration(milliseconds: 20)); // cache write
      final again = Stopwatch()..start();
      final lib2 = BookLibrary(
        booksStream: slow<BookDocs>(docs()),
        entriesStream: slow<List<Map<String, dynamic>>>(const []),
        loadPrefs: () async => prefs,
      );
      final cached = Completer<int>();
      lib2.addListener(() {
        if (lib2.books != null && !cached.isCompleted) cached.complete(again.elapsedMilliseconds);
      });
      final cachedMs = await cached.future;
      expect(lib2.booksFromCache, isTrue);

      // ignore: avoid_print
      print('TIMING (each Firestore read simulated at 300 ms): old, one after the other: titles+progress at $oldMs ms; '
          'new, at once: titles at $firstMs ms, progress at $allMs ms; next visit with the cached titles: $cachedMs ms');
      expect(firstMs, lessThan(oldMs - 200), reason: 'the list is drawn after one read, not two');
      expect(allMs, lessThan(oldMs - 200), reason: 'and the two reads overlap');
      expect(cachedMs, lessThan(100), reason: 'cached titles: drawn at once');
      lib.dispose();
      lib2.dispose();
    });

    test('only strings are cached (titles and links); the student\'s progress is never cached', () async {
      final lib = BookLibrary(
        booksStream: Stream.value({'level-1': {'book_1': 'T', 'n': 5}}),
        entriesStream: Stream.value([entry('level-1', 'book_1', current: true)]),
        loadPrefs: () async => prefs,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final raw = prefs.getString('bookLibrary.docs.v1')!;
      expect(raw, contains('"book_1":"T"'));
      expect(raw.contains('"n"'), isFalse);
      expect(prefs.getKeys().where((k) => k.toLowerCase().contains('entr') || k.toLowerCase().contains('progress')), isEmpty);
      lib.dispose();
    });

    testWidgets('titles show as soon as they arrive; progress fills in after (level bodies are ghosts until then)', (tester) async {
      phone(tester, 1.0);
      final rig = Rig(books: docs()); // no entries yet
      await tester.pumpWidget(host(BooksSelectionScreen(library: rig.library, uid: 'u1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(section('Level 1'), findsOneWidget, reason: 'sections are drawn without the progress');
      expect(find.text('Current books'), findsNothing);
      await tester.tap(header('Level 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Read'), findsNothing, reason: 'never a guess about which books are started');
      expect(find.byType(GhostPlaceholder), findsWidgets);
      rig.entriesController.add([entry('level-1', 'book_1', current: true)]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Current books'), findsOneWidget);
      expect(find.text('Not Started'), findsNWidgets(2), reason: 'Level 1 now lists its two not-started books');
    });

    testWidgets('while nothing has arrived yet a ghost is shown; an error is shown as an error', (tester) async {
      phone(tester, 1.0);
      final rig = Rig();
      await tester.pumpWidget(host(BooksSelectionScreen(library: rig.library, uid: 'u1')));
      await tester.pump();
      expect(find.byType(GhostPlaceholder), findsWidgets);
      rig.booksController.addError(StateError('offline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Error:'), findsOneWidget);
    });
  });
}

Widget _tall(BuildContext context) => const SizedBox(height: 300, child: Text('cards'));
