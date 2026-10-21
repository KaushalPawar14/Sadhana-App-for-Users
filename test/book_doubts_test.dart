// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/AssistantScreen.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/pages/BooksNotesPage.dart';
import 'package:folk_app/services/DailyMessageService.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BookDoubts.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/utils/ReaderContrast.dart';

import 'book_reader_highlights_test.dart' as hl show FakeStore, byKeyName, host, longPress, pointAt, settle, theBook;
import 'text_scale_test.dart' show scales, loadAppFonts;

// DOUBTS: the reader's fourth category (gray). Choosing it opens a dialog (a required question, Ask AI / Ask guide); the
// doubt is stored in `bookDoubts` (the guide sees it), the AI's answer comes back through the assistant, and Notes shows
// Doubts as the fourth tile with each doubt's passage, question and "View answer".
const uid = 'u1';

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

// ------------------------------------------------------------------------------------------------ a fake doubt store
class FakeDoubts implements DoubtStore {
  final Map<String, Doubt> items = {};
  final Map<String, StreamController<Doubt?>> _streams = {};
  final List<String> log = [];
  Map<String, Object?>? lastCreate;
  bool failCreate = false;

  StreamController<Doubt?> _c(String id) => _streams.putIfAbsent(id, () => StreamController<Doubt?>.broadcast());

  void put(Doubt d) {
    items[d.id] = d;
    _c(d.id).add(d);
  }

  @override
  Future<void> create({
    required String id,
    required String uid,
    required String studentName,
    required String bookKey,
    required String level,
    required String bookTitle,
    required int chapterIndex,
    required String text,
    required String paragraph,
    required String question,
    required String mode,
  }) async {
    if (failCreate) throw StateError('offline');
    lastCreate = {'id': id, 'uid': uid, 'studentName': studentName, 'bookKey': bookKey, 'level': level, 'bookTitle': bookTitle, 'chapterIndex': chapterIndex, 'text': text, 'paragraph': paragraph, 'question': question, 'mode': mode};
    log.add('create:$id:$mode');
    put(Doubt(id: id, question: question, mode: mode, status: 'pending', text: text, paragraph: paragraph, bookTitle: bookTitle));
  }

  @override
  Future<void> editQuestion(String id, String question) async {
    log.add('edit:$id:$question');
    final d = items[id]!;
    put(Doubt(id: id, question: question, mode: d.mode, status: d.status, askRound: d.askRound, text: d.text, answer: d.answer, answeredBy: d.answeredBy, answeredByName: d.answeredByName));
  }

  @override
  Future<void> askAgain(String id, String mode) async {
    log.add('again:$id:$mode');
    final d = items[id]!;
    put(Doubt(id: id, question: d.question, mode: mode, status: 'pending', askRound: d.askRound + 1, text: d.text, answer: d.answer, answeredBy: d.answeredBy, answeredByName: d.answeredByName));
  }

  @override
  Future<void> delete(String id) async {
    log.add('delete:$id');
    items.remove(id);
  }

  @override
  Future<Map<String, Doubt>> loadMine(String uid) async => {...items};

  @override
  Stream<Doubt?> watch(String id) async* {
    yield items[id];
    yield* _c(id).stream;
  }
}

BookReaderPage reader(hl.FakeStore store, FakeDoubts doubts, {List<AssistantDoubt>? opened, String theme = 'light'}) => BookReaderPage(
      dropboxUrl: 'https://example.invalid/book.docx?dl=0',
      bookTitle: 'Test Book',
      bookKey: 'book_1',
      level: 'level-1',
      uid: uid,
      loader: (u, t) => Stream.value(BookLoadUpdate(hl.theBook(), complete: true)),
      extras: () async => <Object?>[null, <String, Object?>{'theme': theme}, false],
      highlightStore: store,
      doubtStore: doubts,
      studentName: 'Arjun Das',
      assistantBuilder: (d) {
        opened?.add(d);
        return const Scaffold(body: Center(child: Text('the assistant is open')));
      },
    );

Future<void> openReader(WidgetTester tester, hl.FakeStore store, FakeDoubts doubts, {double scale = 1.0, List<AssistantDoubt>? opened, String theme = 'light'}) async {
  phone(tester, scale);
  await tester.pumpWidget(hl.host(reader(store, doubts, opened: opened, theme: theme)));
  await hl.settle(tester);
}

/// Select the word "First" and open the category panel.
Future<void> openPanel(WidgetTester tester) async {
  await hl.longPress(tester, hl.pointAt(tester, 'First paragraph', 2));
  await tester.tap(hl.byKeyName('sel-highlight'));
  await tester.pumpAndSettle();
}

Future<void> chooseDoubt(WidgetTester tester) async {
  await openPanel(tester);
  await tester.tap(find.byKey(const ValueKey('highlight-category-doubt')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  // ------------------------------------------------------------------------------------------------ the data
  group('the doubt and its store', () {
    test('a doubt reads from its fields: who answered, pending / answered, the AI default', () {
      final pending = Doubt.fromFields('h1', {'question': 'Why?', 'mode': 'guide', 'status': 'pending', 'askRound': 2});
      expect(pending!.toGuide, isTrue);
      expect(pending.answered, isFalse);
      expect(pending.askRound, 2);
      final ai = Doubt.fromFields('h2', {'question': 'Why?', 'mode': 'ai', 'status': 'answered', 'answer': 'Because.', 'answeredBy': 'ai', 'answeredByName': 'AI assistant'})!;
      expect(ai.answered, isTrue);
      expect(ai.answeredByLabel, 'AI assistant');
      final guide = Doubt.fromFields('h3', {'question': 'Why?', 'mode': 'guide', 'status': 'answered', 'answer': 'Because.', 'answeredBy': 'guide', 'answeredByName': 'SBSD'})!;
      expect(guide.answeredByLabel, 'SBSD', reason: 'the guide\'s name');
      expect(Doubt.fromFields('h4', {'question': 'Why?', 'status': 'answered', 'answer': 'x', 'answeredBy': 'guide'})!.answeredByLabel, 'Your guide');
      expect(Doubt.fromFields('h5', {'question': 'Why?', 'status': 'answered', 'answer': '  '})!.answered, isFalse, reason: 'an empty answer is no answer');
      expect(Doubt.fromFields('h6', {'question': '  '}), isNull, reason: 'no question: not a doubt');
      expect(Doubt.fromFields('h7', null), isNull);
    });

    test('the message for the AI carries the passage as its context, the book and the question', () {
      final m = doubtMessageForAi(bookTitle: 'Bhagavad-gita As It Is', passage: 'The soul\n is   eternal.', question: ' What does eternal mean? ');
      expect(m, contains('"Bhagavad-gita As It Is"'));
      expect(m, contains('“The soul is eternal.”'));
      expect(m, endsWith('My doubt: What does eternal mean?'));
      expect(doubtMessageForAi(bookTitle: '', passage: 'x' * 900, question: 'q'), contains('…'), reason: 'a long passage is cut');
      expect(kDoubtNoQuestionsLeft, "You've used today's questions — you can ask tomorrow");
    });

    test('Firestore store: creates (pending, round 1), edits the question, asks again, deletes, loads mine, watches live', () async {
      final fs = FakeFirebaseFirestore();
      final store = FirestoreDoubtStore(fs);
      await store.create(id: 'h1', uid: uid, studentName: 'Arjun Das', bookKey: 'book_1', level: 'level-1', bookTitle: 'Gita', chapterIndex: 2, text: 'passage', paragraph: 'the paragraph', question: ' Why? ', mode: 'guide');
      final raw = (await fs.doc('bookDoubts/h1').get()).data()!;
      expect(raw['uid'], uid);
      expect(raw['status'], 'pending');
      expect(raw['askRound'], 1);
      expect(raw['mode'], 'guide');
      expect(raw['question'], 'Why?', reason: 'trimmed');
      expect(raw.keys.toSet(), {'uid', 'studentName', 'bookKey', 'level', 'bookTitle', 'chapterIndex', 'text', 'paragraph', 'question', 'mode', 'status', 'askRound', 'askedAt', 'createdAt'},
          reason: 'exactly the fields the rules allow on create');
      await store.create(id: 'h2', uid: 'u2', studentName: 'Other', bookKey: 'b', level: 'l', bookTitle: 'B', chapterIndex: 0, text: 't', paragraph: 'p', question: 'Q', mode: 'ai');
      final mine = await store.loadMine(uid);
      expect(mine.keys, ['h1'], reason: 'only this student\'s doubts');
      final seen = <String?>[];
      final sub = store.watch('h1').listen((d) => seen.add(d?.question));
      await Future<void>.delayed(Duration.zero);
      await store.editQuestion('h1', 'A clearer question');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, 'A clearer question');
      await fs.doc('bookDoubts/h1').update({'status': 'answered', 'answer': 'Done', 'answeredBy': 'guide'});
      await store.askAgain('h1', 'ai');
      final again = (await fs.doc('bookDoubts/h1').get()).data()!;
      expect(again['status'], 'pending');
      expect(again['mode'], 'ai');
      expect(again['askRound'], 2);
      await store.delete('h1');
      expect((await fs.doc('bookDoubts/h1').get()).exists, isFalse);
      await sub.cancel();
    });
  });

  // ------------------------------------------------------------------------------------------------ the colour
  test('the Doubt gray: a balanced mid gray with the soft tint; the label is "Doubt", the tile "Doubts"', () {
    final c = HighlightCategory.doubt;
    final r = (c.argb >> 16) & 0xFF, g = (c.argb >> 8) & 0xFF, b = c.argb & 0xFF;
    expect((r - g).abs(), lessThan(24));
    expect(b, greaterThanOrEqualTo(r), reason: 'a touch cool');
    expect(r, inInclusiveRange(90, 150), reason: 'mid gray');
    expect(c.label, 'Doubt');
    expect(c.tileTitle, 'Doubts');
    expect(c.glows, isFalse);
    expect(HighlightCategoryX.fromKey('doubt'), HighlightCategory.doubt);
    for (final mode in ['light', 'dark', 'sepia']) {
      final page = backgroundFor(mode);
      expect(contrastRatio(c.argb, page), greaterThanOrEqualTo(2.3), reason: '$mode: the border is clearly visible');
      final tint = compositeOver(c.tintArgb, page);
      expect(contrastRatio(tint, page), greaterThan(1.07), reason: '$mode: the tint is visible');
      for (final run in <int?>[null, 0xFF000000, 0xFFFFFFFF, 0xFF808080]) {
        final text = readableOnHighlights(run, mode, [c]);
        expect(contrastRatio(text, page), greaterThanOrEqualTo(4.5), reason: '$mode text on the page');
        expect(contrastRatio(text, tint), greaterThanOrEqualTo(4.5), reason: '$mode text on the gray tint');
      }
    }
  });

  // ------------------------------------------------------------------------------------------------ the panel and the dialog
  group('the reader: the category panel and the doubt dialog', () {
    testWidgets('the panel is a 2 x 2: Good, Excellent / Rare, Doubt', (tester) async {
      await openReader(tester, hl.FakeStore(), FakeDoubts());
      await openPanel(tester);
      Rect r(String k) => tester.getRect(find.byKey(ValueKey('highlight-category-$k')));
      expect(r('good').top, closeTo(r('excellent').top, 1));
      expect(r('rare').top, closeTo(r('doubt').top, 1));
      expect(r('rare').top, greaterThan(r('good').bottom - 1));
      expect(r('good').left, lessThan(r('excellent').left));
      expect(r('rare').left, closeTo(r('good').left, 1));
      expect(find.text('DOUBT'), findsOneWidget);
    });

    for (final scale in scales) {
      testWidgets('text $scale: the panel and the dialog fit, nothing overflows', (tester) async {
        await openReader(tester, hl.FakeStore(), FakeDoubts(), scale: scale);
        await chooseDoubt(tester);
        expect(find.byKey(const ValueKey('ask-doubt-dialog')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final box = tester.getRect(find.byKey(const ValueKey('ask-doubt-dialog')));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(360));
        for (final k in ['doubt-ask-ai', 'doubt-ask-guide', 'doubt-cancel']) {
          expect(tester.getRect(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48 - .5), reason: k);
        }
      });
    }

    testWidgets('choosing Doubt opens the dialog: the passage, the required question, Ask AI, Ask guide, Cancel', (tester) async {
      await openReader(tester, hl.FakeStore(), FakeDoubts());
      await chooseDoubt(tester);
      expect(find.byKey(const ValueKey('ask-doubt-dialog')), findsOneWidget);
      expect(find.text('What is your doubt about this passage?'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('ask-doubt-passage')), matching: find.text('First')), findsOneWidget);
      expect(find.text('Ask AI'), findsOneWidget);
      expect(find.text('Ask guide'), findsOneWidget);
    });

    testWidgets('the question is required: an empty one shows a message and nothing is saved', (tester) async {
      final store = hl.FakeStore();
      final doubts = FakeDoubts();
      await openReader(tester, store, doubts);
      await chooseDoubt(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-ask-ai')));
      await tester.pump();
      expect(find.text('Please write your doubt first'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doubt-ask-guide')));
      await tester.pump();
      expect(store.items, isEmpty);
      expect(doubts.items, isEmpty);
      expect(find.byKey(const ValueKey('ask-doubt-dialog')), findsOneWidget, reason: 'the dialog stays');
    });

    testWidgets('Cancel saves nothing and brings the bars back', (tester) async {
      final store = hl.FakeStore();
      final doubts = FakeDoubts();
      await openReader(tester, store, doubts);
      await chooseDoubt(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-cancel')));
      await tester.pumpAndSettle();
      expect(store.items, isEmpty);
      expect(doubts.items, isEmpty);
      expect(find.byKey(const ValueKey('ask-doubt-dialog')), findsNothing);
    });

    testWidgets('Ask guide: the highlight (category doubt) and the doubt are saved, addressed to the guide; the student is told', (tester) async {
      final store = hl.FakeStore();
      final doubts = FakeDoubts();
      final opened = <AssistantDoubt>[];
      await openReader(tester, store, doubts, opened: opened);
      await chooseDoubt(tester);
      await tester.enterText(find.byKey(const ValueKey('doubt-question')), '  What does First mean here?  ');
      await tester.tap(find.byKey(const ValueKey('doubt-ask-guide')));
      await tester.pumpAndSettle();
      expect(store.items.single.category, HighlightCategory.doubt);
      expect(store.items.single.text, 'First');
      final c = doubts.lastCreate!;
      expect(c['id'], store.items.single.id, reason: 'the doubt has the highlight\'s id');
      expect(c['mode'], 'guide');
      expect(c['uid'], uid);
      expect(c['studentName'], 'Arjun Das');
      expect(c['bookTitle'], 'Test Book');
      expect(c['question'], 'What does First mean here?', reason: 'trimmed by the dialog');
      expect((c['paragraph'] as String).startsWith('First paragraph.'), isTrue, reason: 'the whole paragraph is kept for the guide');
      expect(find.text('Your doubt was sent to your guide'), findsOneWidget);
      expect(opened, isEmpty, reason: 'the assistant is not opened for a guide doubt');
    });

    testWidgets('Ask AI: saved the same way, and the assistant opens with the question and the passage as context', (tester) async {
      final store = hl.FakeStore();
      final doubts = FakeDoubts();
      final opened = <AssistantDoubt>[];
      await openReader(tester, store, doubts, opened: opened);
      await chooseDoubt(tester);
      await tester.enterText(find.byKey(const ValueKey('doubt-question')), 'What does First mean here?');
      await tester.tap(find.byKey(const ValueKey('doubt-ask-ai')));
      await tester.pumpAndSettle();
      expect(doubts.lastCreate!['mode'], 'ai');
      expect(opened.length, 1);
      expect(opened.single.doubtId, store.items.single.id);
      expect(opened.single.message, contains('“First”'));
      expect(opened.single.message, contains('"Test Book"'));
      expect(opened.single.message, endsWith('My doubt: What does First mean here?'));
      expect(find.text('the assistant is open'), findsOneWidget);
    });

    testWidgets('if the doubt cannot be sent, nothing is half-saved: the highlight is taken back and the student told', (tester) async {
      final store = hl.FakeStore();
      final doubts = FakeDoubts()..failCreate = true;
      await openReader(tester, store, doubts);
      await chooseDoubt(tester);
      await tester.enterText(find.byKey(const ValueKey('doubt-question')), 'A question');
      await tester.tap(find.byKey(const ValueKey('doubt-ask-guide')));
      await tester.pumpAndSettle();
      expect(store.items, isEmpty, reason: 'the highlight was taken back');
      expect(find.textContaining('Could not send your doubt'), findsOneWidget);
    });

    testWidgets('changing an existing highlight\'s category does not offer Doubt', (tester) async {
      final store = hl.FakeStore();
      await openReader(tester, store, FakeDoubts());
      // make a Good highlight first
      await hl.longPress(tester, hl.pointAt(tester, 'First paragraph', 2));
      await tester.tap(hl.byKeyName('sel-highlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('highlight-category-good')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('highlight-submit')));
      await tester.pumpAndSettle();
      expect(store.items.single.category, HighlightCategory.good);
      // tap it -> Change category
      await tester.tapAt(hl.pointAt(tester, 'First paragraph', 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('highlight-change-category')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('highlight-category-doubt')), findsNothing);
      expect(find.byKey(const ValueKey('highlight-category-rare')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ a doubt highlight
  group('a doubt highlight behaves like the others, with its own dialog', () {
    Future<(hl.FakeStore, FakeDoubts, List<AssistantDoubt>)> withDoubt(WidgetTester tester, {String mode = 'guide', double scale = 1.0}) async {
      final store = hl.FakeStore();
      final doubts = FakeDoubts();
      final opened = <AssistantDoubt>[];
      await openReader(tester, store, doubts, opened: opened, scale: scale);
      await chooseDoubt(tester);
      await tester.enterText(find.byKey(const ValueKey('doubt-question')), 'What does First mean?');
      await tester.tap(find.byKey(ValueKey(mode == 'guide' ? 'doubt-ask-guide' : 'doubt-ask-ai')));
      await tester.pumpAndSettle();
      if (mode == 'ai') {
        // the stand-in assistant is open: go back to the reader
        Navigator.of(tester.element(find.text('the assistant is open'))).pop();
        await tester.pumpAndSettle();
      }
      opened.clear();
      return (store, doubts, opened);
    }

    Future<void> tapDoubt(WidgetTester tester) async {
      await tester.tapAt(hl.pointAt(tester, 'First paragraph', 2));
      await tester.pumpAndSettle();
    }

    testWidgets('tap: the question, and "waiting for your guide" until it is answered; the answer then appears live with who gave it', (tester) async {
      final (store, doubts, _) = await withDoubt(tester);
      await tapDoubt(tester);
      expect(find.byKey(const ValueKey('doubt-info-dialog')), findsOneWidget);
      expect(find.byKey(const ValueKey('doubt-info-question')), findsOneWidget);
      expect(find.text('What does First mean?'), findsOneWidget);
      expect(find.text('Waiting for your guide to answer.'), findsOneWidget);
      final id = store.items.single.id;
      doubts.put(Doubt(id: id, question: 'What does First mean?', mode: 'guide', status: 'answered', answer: 'It means the first one.', answeredBy: 'guide', answeredByName: 'SBSD'));
      await tester.pumpAndSettle();
      expect(find.text('Answered by SBSD'), findsOneWidget);
      expect(find.text('It means the first one.'), findsOneWidget);
      expect(find.text('Waiting for your guide to answer.'), findsNothing);
    });

    testWidgets('an AI answer says "Answered by AI assistant"', (tester) async {
      final (store, doubts, _) = await withDoubt(tester, mode: 'ai');
      doubts.put(Doubt(id: store.items.single.id, question: 'What does First mean?', mode: 'ai', status: 'answered', answer: 'AI answer.', answeredBy: 'ai', answeredByName: 'AI assistant'));
      await tapDoubt(tester);
      expect(find.text('Answered by AI assistant'), findsOneWidget);
      expect(find.text('AI answer.'), findsOneWidget);
    });

    testWidgets('Edit question saves the new question', (tester) async {
      final (store, doubts, _) = await withDoubt(tester);
      await tapDoubt(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-edit-question')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('edit-question-field')), 'A better question');
      await tester.tap(find.byKey(const ValueKey('edit-question-save')));
      await tester.pumpAndSettle();
      expect(doubts.log, contains('edit:${store.items.single.id}:A better question'));
    });

    testWidgets('Edit question: an empty question is refused', (tester) async {
      final (_, doubts, _) = await withDoubt(tester);
      await tapDoubt(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-edit-question')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('edit-question-field')), '   ');
      await tester.tap(find.byKey(const ValueKey('edit-question-save')));
      await tester.pump();
      expect(find.text('Please write your doubt first'), findsOneWidget);
      expect(doubts.log.where((l) => l.startsWith('edit:')), isEmpty);
    });

    testWidgets('Ask AI again asks again and opens the assistant; Ask guide again sends it to the guide', (tester) async {
      final (store, doubts, opened) = await withDoubt(tester);
      final id = store.items.single.id;
      await tapDoubt(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-ask-ai-again')));
      await tester.pumpAndSettle();
      expect(doubts.log, contains('again:$id:ai'));
      expect(opened.single.doubtId, id);
      Navigator.of(tester.element(find.text('the assistant is open'))).pop();
      await tester.pumpAndSettle();
      await tapDoubt(tester);
      await tester.tap(find.byKey(const ValueKey('doubt-ask-guide-again')));
      await tester.pumpAndSettle();
      expect(doubts.log, contains('again:$id:guide'));
      expect(find.text('Your doubt was sent to your guide'), findsOneWidget);
    });

    testWidgets('notes can be added later (Edit note)', (tester) async {
      final (store, _, _) = await withDoubt(tester);
      await tapDoubt(tester);
      await tester.tap(find.byKey(const ValueKey('highlight-edit-note')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('highlight-note')), 'my private thought');
      await tester.tap(find.byKey(const ValueKey('highlight-submit')));
      await tester.pumpAndSettle();
      expect(store.items.single.note, 'my private thought');
      expect(store.items.single.category, HighlightCategory.doubt, reason: 'still a doubt');
    });

    testWidgets('long-press resizes / deletes like the others; deleting the highlight deletes its doubt', (tester) async {
      final (store, doubts, _) = await withDoubt(tester);
      final id = store.items.single.id;
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
      await tester.pumpAndSettle();
      await hl.longPress(tester, hl.pointAt(tester, 'First paragraph', 2));
      expect(hl.byKeyName('handle-start'), findsOneWidget, reason: 'edit mode with handles');
      await tester.tap(hl.byKeyName('edit-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(store.items, isEmpty);
      expect(doubts.log, contains('delete:$id'));
    });

    for (final scale in scales) {
      testWidgets('the doubt dialog at text $scale: fits, buttons reachable, no overflow', (tester) async {
        await withDoubt(tester, scale: scale);
        await tapDoubt(tester);
        expect(find.byKey(const ValueKey('doubt-info-dialog')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final box = tester.getRect(find.byKey(const ValueKey('doubt-info-dialog')));
        expect(box.right, lessThanOrEqualTo(360));
        expect(box.bottom, lessThanOrEqualTo(800));
        for (final k in ['doubt-edit-question', 'doubt-ask-ai-again', 'doubt-ask-guide-again', 'highlight-edit-note']) {
          expect(tester.getRect(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48 - .5), reason: k);
        }
      });
    }
  });

  // ------------------------------------------------------------------------------------------------ the Notes screens
  group('Notes: the Doubts tile, books and numbered cards', () {
    Future<FakeFirebaseFirestore> notesDb() async {
      final fs = FakeFirebaseFirestore();
      Future<void> h(String id, String book, String title, String category, int ch, int p, String text) => fs.collection('bookHighlights').doc(id).set({
            'uid': uid, 'bookKey': book, 'level': 'level-1', 'bookTitle': title, 'chapterIndex': ch, 'startParagraph': p, 'startOffset': 0,
            'endParagraph': p, 'endOffset': text.length, 'text': text, 'textLength': text.length, 'snippetStart': text, 'snippetEnd': text, 'category': category, 'note': '',
          });
      await h('d1', 'book_1', 'Bhagavad-gita As It Is', 'doubt', 1, 0, 'The soul is eternal.');
      await h('d2', 'book_1', 'Bhagavad-gita As It Is', 'doubt', 3, 2, 'Work without attachment.');
      await h('d3', 'book_2', 'Sri Isopanisad', 'doubt', 0, 0, 'Everything belongs to the Lord.');
      await h('g1', 'book_1', 'Bhagavad-gita As It Is', 'good', 0, 0, 'A good one.');
      return fs;
    }

    DoubtStore store() => FakeDoubts()
      ..put(const Doubt(id: 'd1', question: 'What does eternal mean?', mode: 'guide', status: 'answered', answer: 'Without beginning or end.', answeredBy: 'guide', answeredByName: 'SBSD'))
      ..put(const Doubt(id: 'd2', question: 'How to work without attachment?', mode: 'ai', status: 'pending'))
      ..put(const Doubt(id: 'd3', question: 'Who is the Lord?', mode: 'ai', status: 'answered', answer: 'The Supreme Person.', answeredBy: 'ai', answeredByName: 'AI assistant'));

    Future<void> openNotes(WidgetTester tester, FakeFirebaseFirestore fs, {String? openDoubtId, double scale = 1.0}) async {
      phone(tester, scale);
      await tester.pumpWidget(hl.host(BooksNotesPage(uid: uid, firestore: fs, doubtStore: store(), openDoubtId: openDoubtId)));
      await hl.settle(tester);
    }

    testWidgets('the Doubts tile counts doubts and books; the others are unchanged', (tester) async {
      await openNotes(tester, await notesDb());
      expect(find.text('Doubts'), findsOneWidget);
      expect(find.text('3 doubts in 2 books'), findsOneWidget);
      expect(find.text('1 highlight in 1 book'), findsOneWidget, reason: 'Good');
    });

    testWidgets('Doubts -> books (names only) -> numbered cards with the passage, the question and View answer', (tester) async {
      await openNotes(tester, await notesDb());
      await tester.tap(find.byKey(const ValueKey('notes-doubt')));
      await hl.settle(tester);
      expect(find.text('Bhagavad-gita As It Is'), findsOneWidget);
      expect(find.text('Sri Isopanisad'), findsOneWidget);
      expect(find.text('Sri Isopanisad', skipOffstage: false), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notes-book-level-1__book_1')));
      await hl.settle(tester);
      expect(find.byKey(const ValueKey('note-number-1')), findsOneWidget);
      expect(find.text('The soul is eternal.'), findsOneWidget, reason: 'the passage');
      expect(find.text('What does eternal mean?'), findsOneWidget, reason: 'the question');
      expect(find.text('Your doubt'), findsOneWidget);
      expect(find.byKey(const ValueKey('view-answer-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('view-answer-1')));
      await hl.settle(tester);
      expect(find.text('Answered by SBSD'), findsOneWidget);
      expect(find.text('Without beginning or end.'), findsOneWidget);
    });

    testWidgets('an unanswered doubt says "Not answered yet" in the answer dialog', (tester) async {
      await openNotes(tester, await notesDb());
      await tester.tap(find.byKey(const ValueKey('notes-doubt')));
      await hl.settle(tester);
      await tester.tap(find.byKey(const ValueKey('notes-book-level-1__book_1')));
      await hl.settle(tester);
      // swipe to the second card (d2: pending, to the AI)
      await tester.drag(find.byKey(const ValueKey('note-card-1')), const Offset(-400, 0));
      await hl.settle(tester);
      await tester.tap(find.byKey(const ValueKey('view-answer-2')));
      await hl.settle(tester);
      expect(find.text('Not answered yet'), findsOneWidget);
      expect(find.text('The AI has your doubt.'), findsOneWidget);
    });

    testWidgets('a notification about one doubt opens its card directly', (tester) async {
      await openNotes(tester, await notesDb(), openDoubtId: 'd2');
      await hl.settle(tester);
      expect(find.text('How to work without attachment?'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-number-2')), findsOneWidget, reason: 'the second doubt of the book');
    });

    testWidgets('no doubts yet: the tile says so and the page explains how', (tester) async {
      await openNotes(tester, FakeFirebaseFirestore());
      expect(find.text('No doubts yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notes-doubt')));
      await hl.settle(tester);
      expect(find.text('No doubts yet'), findsWidgets);
      expect(find.textContaining('choose Doubt'), findsOneWidget);
    });

    for (final scale in scales) {
      testWidgets('text $scale: the four tiles and a doubt card fit', (tester) async {
        await openNotes(tester, await notesDb(), scale: scale);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('notes-doubt')));
        await hl.settle(tester);
        await tester.tap(find.byKey(const ValueKey('notes-book-level-1__book_1')));
        await hl.settle(tester);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.byKey(const ValueKey('view-answer-1'))).height, greaterThanOrEqualTo(48));
      });
    }
  });

  // ------------------------------------------------------------------------------------------------ the assistant
  group('the assistant for a doubt: counts toward the limit; none left -> the message', () {
    const dailyText = 'You are on a 7-day streak.';

    Future<FakeFirebaseFirestore> seeded({int used = 1}) async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('users').doc(uid).set({'acknowledgedDisclosure': true});
      await fs.collection('studentChats').doc(uid).collection('messages').add({
        'role': 'assistant', 'text': dailyText, 'sessionDate': todaySessionKey(), 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1, 8)), 'entryType': 'daily_message',
      });
      await fs.collection('studentChats').doc(uid).collection('sessions').doc(todaySessionKey()).set({'questionCount': used, 'title': 'A day'});
      return fs;
    }

    Widget screen(FakeFirebaseFirestore fs, AssistantDoubt doubt, List<String> sent) => MaterialApp(
          theme: FolkTheme.light,
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
          home: AssistantScreen(
            uid: uid,
            firestore: fs,
            doubt: doubt,
            dailyMessage: _Daily(),
            chatCall: (m, r) async => <String, dynamic>{},
            doubtChatCall: (m, r, d) async {
              sent.add('$d|$m');
              await fs.collection('studentChats').doc(uid).collection('messages').doc(r).set({
                'role': 'assistant', 'text': 'Here is the answer.', 'streaming': false, 'sessionDate': todaySessionKey(), 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1, 9)),
              });
              return <String, dynamic>{};
            },
          ),
        );

    const doubt = AssistantDoubt(doubtId: 'h1', message: 'I have a doubt about this passage from "Test Book": “First”\n\nMy doubt: Why?');

    testWidgets('a question is left: the doubt is sent as the first question, with its id (the server saves the answer on it)', (tester) async {
      phone(tester, 1.0);
      final sent = <String>[];
      await tester.pumpWidget(screen(await seeded(used: 3), doubt, sent));
      await hl.settle(tester);
      await hl.settle(tester);
      expect(sent, ['h1|${doubt.message}']);
      expect(find.textContaining('My doubt: Why?'), findsOneWidget, reason: 'it is in the conversation');
      expect(find.text('Here is the answer.'), findsOneWidget);
    });

    testWidgets('no questions left: nothing is sent, and the student is told they can ask tomorrow (the doubt stays saved)', (tester) async {
      phone(tester, 1.0);
      final sent = <String>[];
      await tester.pumpWidget(screen(await seeded(used: 9), doubt, sent));
      await hl.settle(tester);
      await hl.settle(tester);
      expect(sent, isEmpty);
      expect(find.text("You've used today's questions — you can ask tomorrow"), findsOneWidget);
    });
  });
}

class _Daily extends DailyMessageService {
  @override
  Future<DailyMessageResult> ensureToday(String uid) => Future.value((isNew: false, failed: false, text: null));
}
