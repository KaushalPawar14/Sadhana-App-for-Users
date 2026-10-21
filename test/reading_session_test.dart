// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/utils/ReadingSessionStore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_reader_highlights_test.dart' show FakeStore, theBook;
import 'text_scale_test.dart' show scales, loadAppFonts;

// Reading time that pauses when the student is not reading and is never lost (BookReaderPage + ReadingSessionStore):
// the timer stops in the background and under another page, comes back only when the student is back on the reader, the
// running session is kept on the phone (every 12 s and on every pause), and what a killed app left behind is added to its
// day once at the next start - never twice.

const _first = 'run-1';
const _second = 'run-2';

ReadingSession _session({
  String id = 'u1_level-1_book_1_1',
  String uid = 'u1',
  int seconds = 600,
  String run = _first,
  bool closing = false,
  DateTime? when,
}) =>
    ReadingSession(
      id: id,
      uid: uid,
      level: 'level-1',
      bookKey: 'book_1',
      title: 'Gita',
      seconds: seconds,
      when: when ?? DateTime(2026, 10, 20, 8),
      run: run,
      closing: closing,
    );

Future<int> _daySeconds(FakeFirebaseFirestore fs, String path) async {
  final d = (await fs.doc(path).get()).data();
  return (d?['totalSeconds'] ?? d?['secondsToday'] ?? d?['totalReadingSeconds'] ?? 0) as int;
}

// ------------------------------------------------------------------------------------------------ the reader
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

class _Rig {
  _Rig(this.store, {this.rdua = false});

  final ReadingSessionStore store;
  final bool rdua;
  DateTime now = DateTime(2026, 10, 20, 8);
  int? popped;
  bool closed = false;

  /// While set, the book is not loaded until it completes.
  Completer<void>? gate;

  void tick(int seconds) => now = now.add(Duration(seconds: seconds));

  Widget app({bool dark = false}) => MaterialApp(
        theme: dark ? FolkTheme.dark : FolkTheme.light,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                popped = await Navigator.push<int>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookReaderPage(
                      dropboxUrl: 'https://example.invalid/book.docx?dl=0',
                      bookTitle: 'Test Book',
                      bookKey: 'book_1',
                      level: 'level-1',
                      uid: 'u1',
                      isRdua: rdua,
                      loader: (u, t) async* {
                        await gate?.future;
                        yield BookLoadUpdate(theBook(), complete: true);
                      },
                      extras: () async => <Object?>[<String, int>{'chapter': 0, 'paragraph': 0}, <String, Object?>{'theme': 'light'}, false], // a bookmark: Back leaves at once
                      highlightStore: FakeStore(),
                      clock: () => now,
                      readingStore: store,
                    ),
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, {double scale = 1.0, bool dark = false}) async {
    phone(tester, scale);
    await tester.pumpWidget(app(dark: dark));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  BuildContext readerContext(WidgetTester tester) => tester.element(find.byType(BookReaderPage));

  /// Another page on top of the reader (what the assistant, or any other screen, is).
  Future<void> pushPage(WidgetTester tester, {String name = '/assistant'}) async {
    unawaited(Navigator.of(readerContext(tester)).push<void>(MaterialPageRoute(
      settings: RouteSettings(name: name),
      builder: (_) => Scaffold(body: Center(child: Text('page $name'))),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> popPage(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  }
}

/// Awaits [f] inside a widget test: those run on fake time, where a plain await never gets its microtasks, so frames are
/// pumped (no time passes) until it is done. Bounded, so a future that never completes fails instead of hanging.
Future<T> got<T>(WidgetTester tester, Future<T> f) async {
  T? value;
  Object? error;
  var done = false;
  f.then((v) {
    value = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 400 && !done; i++) {
    await tester.pump();
  }
  if (!done) fail('the future did not complete');
  if (error != null) throw error!;
  return value as T;
}

/// Moves the app to [s] through the states the platform really passes (resumed - inactive - hidden - paused).
void lifecycle(WidgetTester tester, AppLifecycleState s) {
  const order = [AppLifecycleState.resumed, AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
  final binding = WidgetsBinding.instance;
  var at = order.indexOf(binding.lifecycleState ?? AppLifecycleState.resumed);
  if (s == AppLifecycleState.detached) {
    while (at >= 0 && at < order.length - 1) {
      binding.handleAppLifecycleStateChanged(order[++at]);
    }
    binding.handleAppLifecycleStateChanged(s);
    return;
  }
  if (binding.lifecycleState == AppLifecycleState.detached) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    at = 0;
  }
  final to = order.indexOf(s);
  while (at != to) {
    at += to > at ? 1 : -1;
    binding.handleAppLifecycleStateChanged(order[at]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReadingSessionStore.currentRun = _first;
    debugResetRecoveryStarted();
    ReadingSessionStore.debugResetQueue();
  });
  tearDown(() => ReadingSessionStore.currentRun = _first);

  // ---------------------------------------------------------------------------------------------- the timer
  group('ReadingTimer adds up a monotonic clock', () {
    test('only the stretches between start and pause count', () {
      var t = Duration.zero;
      final timer = ReadingTimer(() => t);
      expect(timer.seconds, 0);
      timer.start();
      t += const Duration(seconds: 20);
      expect(timer.seconds, 20, reason: 'the running stretch is included');
      timer.pause();
      t += const Duration(seconds: 500); // away
      expect(timer.seconds, 20);
      timer.start();
      t += const Duration(seconds: 15);
      timer.pause();
      expect(timer.seconds, 35);
      timer.pause(); // a second pause changes nothing
      expect(timer.seconds, 35);
    });

    test('a clock that steps backwards never makes time negative or lost', () {
      var t = const Duration(seconds: 100);
      final timer = ReadingTimer(() => t);
      timer.start();
      t += const Duration(seconds: 10);
      timer.pause();
      timer.start();
      t -= const Duration(seconds: 50); // wall clock moved back
      timer.pause();
      expect(timer.seconds, 10);
    });
  });

  // ---------------------------------------------------------------------------------------------- pause / resume
  for (final scale in scales) {
    for (final dark in [false, true]) {
      final label = 'text $scale, ${dark ? 'dark' : 'light'}';
      group('the reader pauses and resumes ($label)', () {
        testWidgets('background pauses at once; back in the app resumes it', (tester) async {
          final rig = _Rig(ReadingSessionStore());
          await rig.open(tester, scale: scale, dark: dark);
          rig.tick(20); // reading
          lifecycle(tester, AppLifecycleState.paused);
          await tester.pump();
          rig.tick(300); // phone locked / another app on top
          lifecycle(tester, AppLifecycleState.resumed);
          await tester.pump();
          rig.tick(15); // reading again
          await rig.back(tester);
          expect(rig.popped, 35, reason: 'the 300 s in the background are not counted');
          expect(tester.takeException(), isNull);
        });

        testWidgets('another page on top pauses it; closing that page resumes it', (tester) async {
          final rig = _Rig(ReadingSessionStore());
          await rig.open(tester, scale: scale, dark: dark);
          rig.tick(25);
          await rig.pushPage(tester); // the assistant, say
          rig.tick(200);
          await rig.popPage(tester);
          rig.tick(10);
          await rig.back(tester);
          expect(rig.popped, 35);
        });
      });
    }
  }

  group('the reader pauses and resumes (rules)', () {
    testWidgets('inactive, hidden, paused and detached all pause the timer', (tester) async {
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused, AppLifecycleState.detached]) {
        final rig = _Rig(ReadingSessionStore());
        await rig.open(tester);
        rig.tick(10);
        lifecycle(tester, state);
        await tester.pump();
        rig.tick(100);
        lifecycle(tester, AppLifecycleState.resumed);
        await tester.pump();
        rig.tick(5);
        await rig.back(tester);
        expect(rig.popped, 15, reason: '$state pauses');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('it resumes only when the app is back AND the reader is the visible page', (tester) async {
      final rig = _Rig(ReadingSessionStore());
      await rig.open(tester);
      rig.tick(10);
      await rig.pushPage(tester);
      rig.tick(100);
      lifecycle(tester, AppLifecycleState.paused); // minimised while the other page is on top
      await tester.pump();
      rig.tick(100);
      lifecycle(tester, AppLifecycleState.resumed); // the app is back, the reader is NOT
      await tester.pump();
      rig.tick(100);
      await rig.popPage(tester); // the reader is back
      rig.tick(5);
      lifecycle(tester, AppLifecycleState.paused); // and away again before ...
      await tester.pump();
      rig.tick(100);
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      rig.tick(7);
      await rig.back(tester);
      expect(rig.popped, 10 + 5 + 7);
    });

    testWidgets('closing the covering page while the app is in the background does not resume until the app is back', (tester) async {
      final rig = _Rig(ReadingSessionStore());
      await rig.open(tester);
      rig.tick(10);
      await rig.pushPage(tester);
      lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      // the covering page closes while the app is away (no frames are drawn in the background; the page is gone on return)
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump();
      rig.tick(100);
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      rig.tick(3);
      await rig.back(tester);
      expect(rig.popped, 13);
    });

    testWidgets('a dialog on the reader is still reading; a dialog on the covering page is not', (tester) async {
      final rig = _Rig(ReadingSessionStore());
      await rig.open(tester);
      rig.tick(10);
      unawaited(showDialog<void>(context: rig.readerContext(tester), builder: (_) => const AlertDialog(title: Text('a dialog'))));
      await tester.pumpAndSettle();
      rig.tick(20); // still counts
      Navigator.of(tester.element(find.text('a dialog'))).pop();
      await tester.pumpAndSettle();
      // a bottom sheet is reading too
      unawaited(showModalBottomSheet<void>(context: rig.readerContext(tester), builder: (_) => const SizedBox(height: 100, child: Text('a sheet'))));
      await tester.pumpAndSettle();
      rig.tick(5);
      Navigator.of(tester.element(find.text('a sheet'))).pop();
      await tester.pumpAndSettle();

      await rig.pushPage(tester);
      unawaited(showDialog<void>(context: tester.element(find.text('page /assistant')), builder: (_) => const AlertDialog(title: Text('on the page'))));
      await tester.pumpAndSettle();
      rig.tick(200); // the student is on the other page
      Navigator.of(tester.element(find.text('on the page'))).pop();
      await tester.pumpAndSettle();
      rig.tick(100);
      await rig.popPage(tester);
      rig.tick(2);
      await rig.back(tester);
      expect(rig.popped, 10 + 20 + 5 + 2);
    });

    testWidgets('nothing is counted before the book is on screen', (tester) async {
      final rig = _Rig(ReadingSessionStore())..gate = Completer<void>();
      phone(tester, 1.0);
      await tester.pumpWidget(rig.app());
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 400)); // route pushed, still loading
      rig.tick(100);
      rig.gate!.complete(); // the book appears
      await tester.pumpAndSettle();
      rig.tick(8);
      await rig.back(tester);
      expect(rig.popped, 8);
    });
  });

  // ---------------------------------------------------------------------------------------------- the phone's copy
  group('the running session is kept on the phone', () {
    testWidgets('about every 12 s while running; nothing before the first one', (tester) async {
      final store = ReadingSessionStore();
      final rig = _Rig(store);
      await rig.open(tester);
      rig.tick(5);
      await tester.pump(const Duration(seconds: 5));
      expect(await got(tester, store.pending()), isEmpty, reason: 'first save is at 12 s');
      rig.tick(7);
      await tester.pump(const Duration(seconds: 7));
      var s = (await got(tester, store.pending())).single;
      expect(s.seconds, 12);
      expect((s.uid, s.level, s.bookKey, s.title, s.closing, s.run), ('u1', 'level-1', 'book_1', 'Test Book', false, _first));
      rig.tick(12);
      await tester.pump(const Duration(seconds: 12));
      s = (await got(tester, store.pending())).single;
      expect(s.seconds, 24, reason: 'the same session, refreshed');
      expect((await got(tester, store.pending())).length, 1);
    });

    testWidgets('no periodic save while paused', (tester) async {
      final store = ReadingSessionStore();
      final rig = _Rig(store);
      await rig.open(tester);
      rig.tick(30);
      lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      expect((await got(tester, store.pending())).single.seconds, 30);
      rig.tick(500);
      await tester.pump(const Duration(seconds: 60)); // five periods in the background
      expect((await got(tester, store.pending())).single.seconds, 30, reason: 'unchanged');
    });

    testWidgets('saved on every pause (background, and another page on top)', (tester) async {
      final store = ReadingSessionStore();
      final rig = _Rig(store);
      await rig.open(tester);
      rig.tick(8);
      lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      expect((await got(tester, store.pending())).single.seconds, 8, reason: 'saved the moment the app went away');
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      rig.tick(9);
      await rig.pushPage(tester);
      expect((await got(tester, store.pending())).single.seconds, 17, reason: 'saved the moment another page covered the reader');
    });

    testWidgets('a normal close marks the session closing with the final seconds', (tester) async {
      final store = ReadingSessionStore();
      final rig = _Rig(store);
      await rig.open(tester);
      rig.tick(44);
      await rig.back(tester);
      expect(rig.popped, 44);
      final s = (await got(tester, store.pending())).single;
      expect((s.seconds, s.closing), (44, true));
    });

    testWidgets('a reader that is removed without handing over keeps its seconds; nothing is saved after a hand-over', (tester) async {
      final store = ReadingSessionStore();
      final rig = _Rig(store);
      await rig.open(tester);
      rig.tick(33);
      await tester.pumpWidget(const SizedBox()); // torn down, no pop value
      expect((await got(tester, store.pending())).single.seconds, 33);
    });

    testWidgets('RDUA chapters keep nothing (their time is not counted anywhere)', (tester) async {
      final store = ReadingSessionStore();
      final rig = _Rig(store, rdua: true);
      await rig.open(tester);
      rig.tick(40);
      await tester.pump(const Duration(seconds: 40));
      lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      await rig.back(tester);
      expect(await got(tester, store.pending()), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------- the store
  group('ReadingSessionStore', () {
    test('keeps, refreshes and lists sessions; survives a new instance (the phone)', () async {
      final a = ReadingSessionStore();
      await a.save(_session(seconds: 10));
      await a.save(_session(seconds: 25));
      await a.save(_session(id: 'other', seconds: 5));
      final b = ReadingSessionStore();
      final all = await b.pending();
      expect(all.map((s) => (s.id, s.seconds)), [('u1_level-1_book_1_1', 25), ('other', 5)]);
    });

    test('damaged storage is ignored, never thrown', () async {
      SharedPreferences.setMockInitialValues({'readingSessions': 'not json', 'readingSavedIds': <String>['x']});
      final store = ReadingSessionStore();
      expect(await store.pending(), isEmpty);
      expect(await store.save(_session()), isTrue);
      SharedPreferences.setMockInitialValues({'readingSessions': '[{"id": 5}, 3, {"id":"a"}]'});
      expect(await ReadingSessionStore().pending(), isEmpty);
    });

    test('a saved id is remembered and a saved session can never be stored again', () async {
      final store = ReadingSessionStore();
      await store.save(_session());
      await store.markSaved('u1_level-1_book_1_1');
      expect(await store.pending(), isEmpty);
      expect(await store.isSaved('u1_level-1_book_1_1'), isTrue);
      expect(await store.save(_session(seconds: 999)), isFalse, reason: 'a late refresh from a reader that already handed over');
      expect(await store.pending(), isEmpty);
    });

    test('only the last saved ids are remembered', () async {
      final store = ReadingSessionStore();
      for (var i = 0; i < kReadingSavedIdsKept + 5; i++) {
        await store.markSaved('id$i');
      }
      expect(await store.isSaved('id0'), isFalse);
      expect(await store.isSaved('id${kReadingSavedIdsKept + 4}'), isTrue);
    });

    test('settleClosing takes off only the closed session of that book', () async {
      final store = ReadingSessionStore();
      await store.markClosing(_session(id: 'closed'));
      await store.save(_session(id: 'leftover', seconds: 90));
      await store.markClosing(_session(id: 'otherBook').copyWith(seconds: 70));
      await store.settleClosing(uid: 'u1', level: 'level-1', bookKey: 'book_1');
      expect((await store.pending()).map((s) => s.id), ['leftover']);
      expect(await store.isSaved('closed'), isTrue);
      expect(await store.isSaved('leftover'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------------------------- the writes
  group('issueReadingWrites (the one write path)', () {
    test('adds to the lifetime total, the day bucket and the history row - and to NOTHING else', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('users').doc('u1').set({'totalReadingSeconds': 100});
      await fs.collection('users').doc('u1').collection('dailyReading').doc('20-10-2026').set({'secondsToday': 50});
      await fs.collection('sadhana-reports').doc('Asha').collection('dates').doc('20-10-2026').set({'bookReading': 5});
      final ok = await issueReadingWrites(
        db: fs,
        uid: 'u1',
        level: 'level-1',
        bookKey: 'book_1',
        title: 'Gita',
        seconds: 130,
        when: DateTime(2026, 10, 20, 9),
      );
      expect(ok, isTrue);
      expect((await fs.doc('users/u1').get()).data()!['totalReadingSeconds'], 230);
      expect(await _daySeconds(fs, 'users/u1/dailyReading/20-10-2026'), 180);
      final day = (await fs.doc('readingDays/u1_20261020').get()).data()!;
      expect(day['totalSeconds'], 130);
      expect((day['books'] as Map)['level-1__book_1']['seconds'], 130);
      // the student's typed report is exactly as it was: the timer's minutes are NOT added (a typed 5 stays 5)
      expect((await fs.doc('sadhana-reports/Asha/dates/20-10-2026').get()).data(), {'bookReading': 5});
    });

    test('a session under 30 s still adds to the totals as before, but makes no history row', () async {
      final fs = FakeFirebaseFirestore();
      await issueReadingWrites(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 20, when: DateTime(2026, 10, 20));
      expect((await fs.doc('users/u1').get()).data()!['totalReadingSeconds'], 20);
      expect((await fs.collection('readingDays').get()).docs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------- the recovery
  group('recovery of what a killed app left behind', () {
    test('a leftover session is added once to its own day and the stored session is cleared', () async {
      final fs = FakeFirebaseFirestore();
      final store = ReadingSessionStore();
      await store.save(_session(seconds: 600, when: DateTime(2026, 10, 19, 21)));
      ReadingSessionStore.currentRun = _second; // the app started again
      Future<void> write(ReadingSession s) async {
        await issueReadingWrites(db: fs, uid: s.uid, level: s.level, bookKey: s.bookKey, title: s.title, seconds: s.seconds, when: s.when);
      }

      expect(await recoverReadingSessions(uid: 'u1', store: store, write: write), 1);
      expect(await store.pending(), isEmpty, reason: 'reset to zero');
      expect(await _daySeconds(fs, 'readingDays/u1_20261019'), 600, reason: 'the day it was read, not today');
      expect(await _daySeconds(fs, 'users/u1'), 600);

      // a second start finds nothing
      expect(await recoverReadingSessions(uid: 'u1', store: ReadingSessionStore(), write: write), 0);
      expect(await _daySeconds(fs, 'readingDays/u1_20261019'), 600);
    });

    test('the very run that owns a session never recovers it (its reader is alive)', () async {
      final store = ReadingSessionStore();
      await store.save(_session(run: _second));
      ReadingSessionStore.currentRun = _second;
      var calls = 0;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async => calls++), 0);
      expect(calls, 0);
      expect(await store.pending(), hasLength(1));
    });

    test('another student\'s session is left alone', () async {
      final store = ReadingSessionStore();
      await store.save(_session(uid: 'u2'));
      var calls = 0;
      ReadingSessionStore.currentRun = _second;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async => calls++), 0);
      expect(calls, 0);
      expect(await store.pending(), hasLength(1));
    });

    test('a session under 30 s is ignored (dropped, nothing written)', () async {
      final store = ReadingSessionStore();
      await store.save(_session(seconds: kReadingLogMinSecondsForTest - 1));
      await store.save(_session(id: 'exactly', seconds: kReadingLogMinSecondsForTest));
      final written = <String>[];
      ReadingSessionStore.currentRun = _second;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (s) async => written.add(s.id)), 1);
      expect(written, ['exactly'], reason: '30 s counts, 29 s does not');
      expect(await store.pending(), isEmpty);
    });

    test('several leftovers (two books) are all written once', () async {
      final store = ReadingSessionStore();
      await store.save(_session(id: 'a', seconds: 100));
      await store.save(_session(id: 'b', seconds: 200));
      final written = <String>[];
      ReadingSessionStore.currentRun = _second;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (s) async => written.add(s.id)), 2);
      expect(written, ['a', 'b']);
    });

    // --- no double count
    test('normal close, then the next start: nothing is added again', () async {
      final fs = FakeFirebaseFirestore();
      final store = ReadingSessionStore();
      // the reader hands over ...
      await store.markClosing(_session(seconds: 300));
      // ... and the book list issues the writes, then settles
      await issueReadingWrites(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 300, when: DateTime(2026, 10, 20, 8));
      await store.settleClosing(uid: 'u1', level: 'level-1', bookKey: 'book_1');
      // a reader that flushes late (dispose after the pop) is refused
      expect(await store.save(_session(seconds: 300)), isFalse);

      ReadingSessionStore.currentRun = _second;
      var calls = 0;
      expect(await recoverReadingSessions(uid: 'u1', store: ReadingSessionStore(), write: (_) async => calls++), 0);
      expect(calls, 0);
      expect(await _daySeconds(fs, 'readingDays/u1_20261020'), 300);
    });

    test('killed between the hand-over and the writes: the next start writes it, once', () async {
      final fs = FakeFirebaseFirestore();
      final store = ReadingSessionStore();
      await store.markClosing(_session(seconds: 300)); // never settled
      ReadingSessionStore.currentRun = _second;
      Future<void> write(ReadingSession s) async =>
          issueReadingWrites(db: fs, uid: s.uid, level: s.level, bookKey: s.bookKey, title: s.title, seconds: s.seconds, when: s.when).then((_) {});
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: write), 1);
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: write), 0);
      expect(await _daySeconds(fs, 'readingDays/u1_20261020'), 300);
    });

    test('two starts racing on the same leftover write it once', () async {
      final store = ReadingSessionStore();
      await store.save(_session());
      ReadingSessionStore.currentRun = _second;
      final written = <String>[];
      final a = recoverReadingSessions(uid: 'u1', store: store, write: (s) async => written.add(s.id));
      final b = recoverReadingSessions(uid: 'u1', store: store, write: (s) async => written.add(s.id));
      expect(await Future.wait([a, b]), [1, 0]);
      expect(written, ['u1_level-1_book_1_1']);
      expect(await store.isSaved('u1_level-1_book_1_1'), isTrue);
    });

    test('an id that is already saved is never written again, even if a copy is still on the phone', () async {
      SharedPreferences.setMockInitialValues({
        'readingSavedIds': <String>['u1_level-1_book_1_1'],
        'readingSessions': '[{"id":"u1_level-1_book_1_1","uid":"u1","level":"level-1","bookKey":"book_1","title":"Gita","seconds":600,"when":1,"run":"$_first","closing":false}]',
      });
      final store = ReadingSessionStore();
      ReadingSessionStore.currentRun = _second;
      var calls = 0;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async => calls++), 0);
      expect(calls, 0);
      expect(await store.pending(), isEmpty, reason: 'cleaned up');
    });

    test('startup recovery of a session that is the reader\'s kill: reader refresh, kill, recovery, late flush of the dead reader refused', () async {
      final store = ReadingSessionStore();
      await store.save(_session(seconds: 40)); // the reader's 12-second refresh
      ReadingSessionStore.currentRun = _second;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async {}), 1);
      expect(await store.save(_session(seconds: 55)), isFalse);
      expect(await store.pending(), isEmpty);
    });

    // --- offline-safe
    test('the session is still on the phone (not yet saved) while the writes are being issued, and cleared after', () async {
      final store = ReadingSessionStore();
      await store.save(_session());
      ReadingSessionStore.currentRun = _second;
      final seen = <String>[];
      expect(
        await recoverReadingSessions(
          uid: 'u1',
          store: store,
          write: (s) async {
            seen.add('write called');
            seen.add((await store.pending()).isEmpty ? 'already cleared' : 'still stored');
            seen.add(await store.isSaved(s.id) ? 'already marked' : 'not marked');
          },
        ),
        1,
      );
      expect(seen, ['write called', 'still stored', 'not marked']);
      expect(await store.pending(), isEmpty);
    });

    test('a write that cannot be issued leaves the session for the next start, which then writes it once', () async {
      final store = ReadingSessionStore();
      await store.save(_session());
      ReadingSessionStore.currentRun = _second;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async => throw StateError('no Firebase yet')), 0);
      expect(await store.pending(), hasLength(1));
      expect(await store.isSaved('u1_level-1_book_1_1'), isFalse);
      var calls = 0;
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async => calls++), 1);
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async => calls++), 0);
      expect(calls, 1);
    });

    test('offline: a write that never answers is queued by Firestore, so it counts as issued and is not written again', () async {
      final store = ReadingSessionStore();
      await store.save(_session());
      ReadingSessionStore.currentRun = _second;
      var calls = 0;
      final never = Completer<void>();
      expect(
        await recoverReadingSessions(
          uid: 'u1',
          store: store,
          writeWait: const Duration(milliseconds: 30),
          write: (_) {
            calls++;
            return never.future;
          },
        ),
        1,
      );
      expect(await store.pending(), isEmpty);
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async => calls++), 0);
      expect(calls, 1);
    });

    test('recovery never throws, whatever the writer or the storage does', () async {
      final store = ReadingSessionStore(prefs: () async => throw StateError('disk'));
      expect(await recoverReadingSessions(uid: 'u1', store: store, write: (_) async {}), 0);
    });
  });

  // ---------------------------------------------------------------------------------------------- end to end
  group('end to end: a kill in the middle of reading', () {
    testWidgets('the reader keeps the seconds; the next start adds them once; the dead reader cannot add them again', (tester) async {
      final fs = FakeFirebaseFirestore();
      final store = ReadingSessionStore();
      final rig = _Rig(store);
      await rig.open(tester);
      rig.tick(50);
      await tester.pump(const Duration(seconds: 12)); // the periodic save at 50 s read
      expect((await got(tester, store.pending())).single.seconds, 50);
      rig.tick(10); // 10 more seconds that were never saved: lost at most one period
      // "kill": the app start below runs while this reader is still the old process's state
      ReadingSessionStore.currentRun = _second;
      Future<void> write(ReadingSession s) async =>
          issueReadingWrites(db: fs, uid: s.uid, level: s.level, bookKey: s.bookKey, title: s.title, seconds: s.seconds, when: s.when).then((_) {});
      expect(await got(tester, recoverReadingSessions(uid: 'u1', store: ReadingSessionStore(), write: write)), 1);
      expect(await got(tester, _daySeconds(fs, 'readingDays/u1_20261020')), 50);
      expect(await got(tester, _daySeconds(fs, 'users/u1')), 50);
      // the old reader is torn down and tries to flush: refused
      await tester.pumpWidget(const SizedBox());
      expect(await got(tester, store.pending()), isEmpty);
      expect(await got(tester, recoverReadingSessions(uid: 'u1', store: ReadingSessionStore(), write: write)), 0);
      expect(await got(tester, _daySeconds(fs, 'readingDays/u1_20261020')), 50);
    });

    testWidgets('a session under 30 s is ignored end to end', (tester) async {
      final fs = FakeFirebaseFirestore();
      final store = ReadingSessionStore();
      final rig = _Rig(store);
      await rig.open(tester);
      rig.tick(20);
      lifecycle(tester, AppLifecycleState.paused); // saved on pause: 20 s
      await tester.pump();
      expect((await got(tester, store.pending())).single.seconds, 20);
      ReadingSessionStore.currentRun = _second;
      final recovered = await got(
        tester,
        recoverReadingSessions(
          uid: 'u1',
          store: ReadingSessionStore(),
          write: (s) async {
            await issueReadingWrites(db: fs, uid: s.uid, level: s.level, bookKey: s.bookKey, title: s.title, seconds: s.seconds, when: s.when);
          },
        ),
      );
      expect(recovered, 0);
      expect((await got(tester, fs.collection('readingDays').get())).docs, isEmpty);
      expect((await got(tester, fs.collection('users').get())).docs, isEmpty);
    });
  });
}

/// The same threshold the reading log uses (kept here so a change of it is noticed by this test).
const int kReadingLogMinSecondsForTest = 30;
