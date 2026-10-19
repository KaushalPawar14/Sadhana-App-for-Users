import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/AssistantHistoryScreen.dart';
import 'package:folk_app/pages/AssistantScreen.dart';
import 'package:folk_app/services/DailyMessageService.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/AssistantGreeting.dart';
import 'package:folk_app/widgets/FolkErrorRetry.dart';
import 'package:intl/intl.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The assistant's day: the daily limit, greetings, the four starter cards, and one merged history
// (one list, one entry per day, each day one thread). No network: the chat callable is a stand-in
// that writes what the server writes, into an in-memory Firestore.

const uid = 'u1';
const dailyText = 'You are on a 7-day streak. Keep going, Prabhu!';
const limitLine =
    "You've used today's 9 questions — I'll be here again tomorrow. Meanwhile, chant and read!";

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
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

class _Daily extends DailyMessageService {
  @override
  Future<DailyMessageResult> ensureToday(String uid) =>
      Future.value((isNew: false, failed: false, text: null));
}

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

Timestamp at(int minute) => Timestamp.fromDate(DateTime(2026, 10, 1, 8, minute));

Future<void> msg(FakeFirebaseFirestore fs, String day, int minute, String role, String text,
    {String? entryType, String? category}) async {
  await fs.collection('studentChats').doc(uid).collection('messages').add({
    'role': role,
    'text': text,
    'sessionDate': day,
    'createdAt': at(minute),
    if (entryType != null) 'entryType': entryType,
    if (category != null) 'category': category,
  });
}

Future<void> session(FakeFirebaseFirestore fs, String day, {int? count, String? title}) =>
    fs.collection('studentChats').doc(uid).collection('sessions').doc(day).set({
      if (count != null) 'questionCount': count,
      if (title != null) 'title': title,
    });

Future<FakeFirebaseFirestore> seededToday({int count = 1, bool dailyMessage = true}) async {
  final fs = FakeFirebaseFirestore();
  await fs.collection('users').doc(uid).set({'acknowledgedDisclosure': true});
  if (dailyMessage) await msg(fs, todaySessionKey(), 0, 'assistant', dailyText, entryType: 'daily_message');
  await session(fs, todaySessionKey(), count: count, title: '1 Oct · 7-day streak, keep going');
  return fs;
}

// A stand-in for what `studentChat` does: store the question, the reply, and count it.
Future<Map<String, dynamic>> Function(String, String) fakeServer(FakeFirebaseFirestore fs, List<String> asked) {
  var n = 10;
  return (message, replyId) async {
    asked.add(message);
    final greeting = isGreetingMessage(message);
    await msg(fs, todaySessionKey(), n++, 'student', message, category: greeting ? 'greeting' : 'philosophical');
    await fs.collection('studentChats').doc(uid).collection('messages').doc(replyId).set({
      'role': 'assistant',
      'text': greeting ? 'Hare Krishna Prabhu! How may I serve you?' : 'Here is an answer.',
      'streaming': false,
      'sessionDate': todaySessionKey(),
      'createdAt': at(n++),
    });
    final ref = fs.collection('studentChats').doc(uid).collection('sessions').doc(todaySessionKey());
    final used = ((await ref.get()).data()?['questionCount'] as num?)?.toInt() ?? 0;
    await ref.set({'questionCount': used + 1}, SetOptions(merge: true));
    return {};
  };
}

Widget app(Widget Function() screen, {bool dark = false, String initial = kAssistantRouteName}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      initialRoute: initial,
      // initialRoute '/x' also pushes '/': only the named route gets the screen.
      onGenerateRoute: (s) => MaterialPageRoute(
        settings: s,
        builder: (_) => s.name == initial ? screen() : const SizedBox(),
      ),
    );

Widget chatScreen(FakeFirebaseFirestore fs, List<String> asked, {bool dark = false}) => app(
      () => AssistantScreen(uid: uid, firestore: fs, chatCall: fakeServer(fs, asked), dailyMessage: _Daily()),
      dark: dark,
    );

const cardLabels = ['SPIRITUAL QUESTION', 'HOW THE APP WORKS', 'DAILY PRACTICE', 'HOW AM I DOING'];

// Scrolls the chat to the end, then says whether the four cards are all there.
Future<bool> cardsShown(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 4; i++) {
    await tester.drag(list, const Offset(0, -700));
    await tester.pump(const Duration(milliseconds: 100));
  }
  return cardLabels.every((l) => find.text(l).evaluate().isNotEmpty);
}

Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('the app tells a greeting from a real question (same answer as the server)', () {
    test('greetings, in four languages', () {
      for (final g in [
        'hi', 'Hello!', 'hey', 'heyyyy', 'Hare Krishna', 'hare krishna prabhu', 'Hare Krishna Mataji!',
        'jai shri krishna', 'Jai Sri Krishna', 'namaste', 'Pranam', 'dandavat pranam', 'Dandavat Prabhu',
        'नमस्ते', 'हरे कृष्ण', 'जय श्री कृष्ण', 'નમસ્તે', 'હરે કૃષ્ણ', 'જય શ્રી કૃષ્ણ', 'నమస్తే', 'హరే కృష్ణ', 'good morning',
      ]) {
        expect(isGreetingMessage(g), isTrue, reason: g);
      }
    });

    test('anything with real content is not a greeting', () {
      for (final q in [
        'What is karma?', 'Hare Krishna, what is karma?', 'hi, how do I chant better',
        'How do I mark a book as read?', 'I feel low today', '', '   ', '?!', 'Who am I if I am not this body?',
      ]) {
        expect(isGreetingMessage(q), isFalse, reason: q);
      }
    });
  });

  group('the chat screen', () {
    testWidgets("today's message does not hide the four cards; they sit below it", (tester) async {
      phone(tester, 1.0);
      final fs = await seededToday(count: 2);
      await tester.pumpWidget(chatScreen(fs, []));
      await settle(tester);
      expect(find.text(dailyText), findsOneWidget);
      // before any scrolling: the cards' heading is built, and it is below today's message
      expect(find.text('Ask about the teachings'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Ask about the teachings')).dy, greaterThan(tester.getBottomLeft(find.text(dailyText)).dy));
      expect(await cardsShown(tester), isTrue);
    });

    testWidgets('a greeting alone does not hide the cards; the first real question does', (tester) async {
      phone(tester, 1.0);
      final fs = await seededToday(count: 0);
      final asked = <String>[];
      await tester.pumpWidget(chatScreen(fs, asked));
      await settle(tester);

      await send(tester, 'Hare Krishna Prabhu!');
      expect(asked, ['Hare Krishna Prabhu!']);
      expect(find.textContaining('How may I serve you?'), findsOneWidget);
      expect(await cardsShown(tester), isTrue, reason: 'a greeting does not hide the cards');
      expect(find.text('8 questions left today'), findsOneWidget);

      await send(tester, 'What is karma?');
      expect(asked.length, 2);
      expect(find.text('SPIRITUAL QUESTION'), findsNothing, reason: 'the first real question hides them');
      expect(find.text('7 questions left today'), findsOneWidget);
    });

    testWidgets('tapping a card is a real question: the cards go', (tester) async {
      phone(tester, 1.0);
      final fs = await seededToday(count: 0);
      final asked = <String>[];
      await tester.pumpWidget(chatScreen(fs, asked));
      await settle(tester);
      expect(await cardsShown(tester), isTrue);
      await tester.tap(find.text('DAILY PRACTICE'), warnIfMissed: false);
      await settle(tester);
      expect(asked.length, 1);
      expect(find.text('DAILY PRACTICE'), findsNothing);
    });

    testWidgets('reopening later the same day: cards back after a greeting only, gone after a real question', (tester) async {
      phone(tester, 1.0);
      var fs = await seededToday(count: 1);
      await msg(fs, todaySessionKey(), 5, 'student', 'hello', category: 'greeting');
      await msg(fs, todaySessionKey(), 6, 'assistant', 'Hare Krishna Prabhu! How may I serve you?');
      await tester.pumpWidget(chatScreen(fs, []));
      await settle(tester);
      expect(await cardsShown(tester), isTrue);

      fs = await seededToday(count: 2);
      await msg(fs, todaySessionKey(), 5, 'student', 'What is the soul?', category: 'philosophical');
      await msg(fs, todaySessionKey(), 6, 'assistant', 'The soul is...');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(chatScreen(fs, []));
      await settle(tester);
      expect(find.text('SPIRITUAL QUESTION'), findsNothing);
    });

    testWidgets('the remaining line: plural, singular', (tester) async {
      phone(tester, 1.0);
      for (final c in [(0, '9 questions left today'), (2, '7 questions left today'), (8, '1 question left today')]) {
        final fs = await seededToday(count: c.$1);
        await tester.pumpWidget(chatScreen(fs, []));
        await settle(tester);
        expect(find.byKey(const ValueKey('remaining-line')), findsOneWidget);
        expect(find.text(c.$2), findsOneWidget);
        expect(find.byKey(const ValueKey('limit-line')), findsNothing);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('at the limit: the friendly line, the composer off, nothing sent', (tester) async {
      phone(tester, 1.0);
      final fs = await seededToday(count: 9);
      final asked = <String>[];
      await tester.pumpWidget(chatScreen(fs, asked));
      await settle(tester);
      expect(find.byKey(const ValueKey('limit-line')), findsOneWidget);
      expect(find.text(limitLine), findsOneWidget);
      expect(find.byKey(const ValueKey('remaining-line')), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      // even a card, if one were tapped, sends nothing
      await cardsShown(tester);
      if (find.text('DAILY PRACTICE').evaluate().isNotEmpty) {
        await tester.tap(find.text('DAILY PRACTICE'), warnIfMissed: false);
        await settle(tester);
      }
      expect(asked, isEmpty);
    });

    testWidgets('the ninth question uses the day up, live', (tester) async {
      phone(tester, 1.0);
      final fs = await seededToday(count: 8);
      final asked = <String>[];
      await tester.pumpWidget(chatScreen(fs, asked));
      await settle(tester);
      expect(find.text('1 question left today'), findsOneWidget);
      await send(tester, 'One more question about japa?');
      expect(find.text(limitLine), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });

  group('the merged history', () {
    Future<FakeFirebaseFirestore> history() async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('users').doc(uid).set({'acknowledgedDisclosure': true});
      // 5 Oct: daily message + a chat, titled
      await msg(fs, '05-10-2026', 0, 'assistant', 'Daily one for the fifth.', entryType: 'daily_message');
      await msg(fs, '05-10-2026', 10, 'student', 'What is the soul?', category: 'philosophical');
      await msg(fs, '05-10-2026', 11, 'assistant', 'The soul is eternal.');
      await session(fs, '05-10-2026', count: 1, title: '5 Oct · The soul, and better chanting');
      // 3 Oct: only a daily message, no title (older day)
      await msg(fs, '03-10-2026', 0, 'assistant', 'Daily one for the third.', entryType: 'daily_message');
      // 1 Oct: a chat but no daily message, no title
      await msg(fs, '01-10-2026', 10, 'student', 'How do I chant better?', category: 'practice');
      await msg(fs, '01-10-2026', 11, 'assistant', 'Chant with attention.');
      // today: titled, with its live chat
      await msg(fs, todaySessionKey(), 0, 'assistant', dailyText, entryType: 'daily_message');
      await session(fs, todaySessionKey(), count: 0, title: '19 Oct · 7-day streak, keep going');
      return fs;
    }

    Widget list(FirebaseFirestore fs, {bool dark = false}) => app(
          () => AssistantHistoryListPage(uid: uid, firestore: fs),
          dark: dark,
          initial: '/history',
        );

    testWidgets('one list, one entry per day, newest first, no tabs', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(list(await history()));
      await settle(tester);
      expect(find.text('Conversations'), findsNothing);
      expect(find.text('Daily messages'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      final titles = [
        '19 Oct · 7-day streak, keep going',
        '5 Oct · The soul, and better chanting',
        DateFormat('EEEE, dd MMM yyyy').format(DateTime(2026, 10, 3)),
        DateFormat('EEEE, dd MMM yyyy').format(DateTime(2026, 10, 1)),
      ];
      double last = -1;
      for (final t in titles) {
        expect(find.text(t), findsOneWidget, reason: t);
        final y = tester.getTopLeft(find.text(t)).dy;
        expect(y, greaterThan(last), reason: 'newest first: $t');
        last = y;
      }
      expect(find.text('Daily one for the third.'), findsOneWidget, reason: 'a day with only the daily message previews it');
    });

    testWidgets('a past day opens as one thread: the daily message first, then the whole chat, read only', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(list(await history()));
      await settle(tester);
      await tester.tap(find.text('5 Oct · The soul, and better chanting'));
      await settle(tester);
      final a = tester.getTopLeft(find.text('Daily one for the fifth.')).dy;
      final b = tester.getTopLeft(find.text('What is the soul?')).dy;
      final c = tester.getTopLeft(find.text('The soul is eternal.')).dy;
      expect(a < b && b < c, isTrue, reason: 'daily message, question, answer');
      expect(find.text('Viewing a past conversation — read only.'), findsOneWidget);
      expect(find.text("Go to today's chat"), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no composer on a past day');
    });

    testWidgets("today's entry goes back to the live chat", (tester) async {
      phone(tester, 1.0);
      final fs = await history();
      await tester.pumpWidget(app(
        () => AssistantScreen(uid: uid, firestore: fs, chatCall: fakeServer(fs, []), dailyMessage: _Daily()),
      ));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.history_rounded));
      await settle(tester);
      expect(find.text('History'), findsOneWidget);
      await tester.tap(find.text('19 Oct · 7-day streak, keep going'));
      await settle(tester);
      expect(find.text('History'), findsNothing);
      expect(find.text('Ask a Question'), findsOneWidget);
    });

    testWidgets('"Go to today\'s chat" from a past day', (tester) async {
      phone(tester, 1.0);
      final fs = await history();
      await tester.pumpWidget(app(
        () => AssistantScreen(uid: uid, firestore: fs, chatCall: fakeServer(fs, []), dailyMessage: _Daily()),
      ));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.history_rounded));
      await settle(tester);
      await tester.tap(find.text('5 Oct · The soul, and better chanting'));
      await settle(tester);
      await tester.tap(find.text("Go to today's chat"));
      await settle(tester);
      expect(find.text('Ask a Question'), findsOneWidget);
      expect(find.text('History'), findsNothing);
    });

    testWidgets('a load that fails says so, with Retry, and Retry works', (tester) async {
      phone(tester, 1.0);
      final fs = _Flaky(await history(), 1);
      await tester.pumpWidget(list(fs));
      await settle(tester);
      expect(find.byType(FolkErrorRetry), findsOneWidget);
      expect(find.text("Couldn't load your history just now."), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.byType(FolkErrorRetry), findsNothing);
      expect(find.text('5 Oct · The soul, and better chanting'), findsOneWidget);
    });

    testWidgets('no history at all', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(list(FakeFirebaseFirestore()));
      await settle(tester);
      expect(find.text('No conversations yet.'), findsOneWidget);
    });
  });

  // Text size 1.0 / 1.3 / 1.6, light and dark, the app's real fonts: nothing overflows or breaks.
  for (final scale in scales) {
    for (final dark in [false, true]) {
      final s = 'text scale $scale, ${dark ? 'dark' : 'light'}';

      testWidgets('chat screen: message, cards, remaining line — $s', (tester) async {
        phone(tester, scale);
        final fs = await seededToday(count: 2);
        await tester.pumpWidget(chatScreen(fs, [], dark: dark));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(await cardsShown(tester), isTrue);
        expect(find.text('7 questions left today'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('chat screen at the limit — $s', (tester) async {
        phone(tester, scale);
        final fs = await seededToday(count: 9);
        await tester.pumpWidget(chatScreen(fs, [], dark: dark));
        await settle(tester);
        expect(find.text(limitLine), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('history list and a day thread — $s', (tester) async {
        phone(tester, scale);
        final fs = FakeFirebaseFirestore();
        await msg(fs, '05-10-2026', 0, 'assistant', 'Daily one for the fifth. Keep going, Prabhu, you are doing well.', entryType: 'daily_message');
        await msg(fs, '05-10-2026', 10, 'student', 'What is the soul and how is it different from the body?', category: 'philosophical');
        await msg(fs, '05-10-2026', 11, 'assistant', 'The soul is eternal, full of knowledge and bliss.');
        await session(fs, '05-10-2026', count: 1, title: '5 Oct · The soul, and better chanting');
        await tester.pumpWidget(app(
          () => AssistantHistoryListPage(uid: uid, firestore: fs),
          dark: dark,
          initial: '/history',
        ));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.textContaining('The soul, and better chanting'));
        await settle(tester);
        expect(find.textContaining('Daily one for the fifth'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
