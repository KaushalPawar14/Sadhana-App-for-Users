import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/ExpeditionExperienceForm.dart';
import 'package:folk_app/pages/ExpeditionScreen.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/ExpeditionExperience.dart';
import 'package:folk_app/utils/TripDates.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

/// Master 2 B — sharing what a trip meant, in the Student app.
///
/// The server asks the morning after a trip ends, and only the students the
/// guide marked Fully or Partially completed. It writes the stub; the student
/// fills in three questions and a note, and can edit for seven days. It is
/// written for the guides: the student sees it only while filling it in, and
/// it is not shown on their profile.

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

Timestamp inDays(int n) =>
    Timestamp.fromDate(DateTime.now().add(Duration(days: n)));

Map<String, dynamic> stub({
  String uid = 'boy',
  String tripId = 't1',
  String tripName = 'Vrindavan Dham Yatra',
  String status = 'requested',
  int editableDays = 6,
  Map<String, String> answers = const {},
}) =>
    {
      'tripId': tripId,
      'tripName': tripName,
      'studentUid': uid,
      'studentName': 'Arjun Kumar',
      'attendance': 'full',
      'status': status,
      'editableUntil': inDays(editableDays),
      'requestedAt': inDays(-1),
      ...answers,
    };

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // -------------------------------------------------------------------------
  // the trip's dates
  // -------------------------------------------------------------------------
  group('a trip with an end date', () {
    Timestamp d(int y, int m, int day) => Timestamp.fromDate(DateTime(y, m, day));

    test('a one-day trip reads as it always did', () {
      expect(tripDatesText({'tripDate': d(2026, 8, 25)}), '25 Aug 2026');
      expect(tripDatesText({'tripDate': d(2026, 8, 25), 'endDate': d(2026, 8, 25)}),
          '25 Aug 2026');
    });

    test('a longer one reads from-to', () {
      expect(tripDatesText({'tripDate': d(2026, 10, 18), 'endDate': d(2026, 10, 20)}),
          '18 Oct – 20 Oct 2026');
      expect(tripDatesText({'tripDate': d(2026, 12, 30), 'endDate': d(2027, 1, 2)}),
          '30 Dec 2026 – 02 Jan 2027');
    });

    test('an end before the start is ignored, as the server does', () {
      final t = {'tripDate': d(2026, 10, 20), 'endDate': d(2026, 10, 10)};
      expect(tripEndOf(t)!.day, 20);
      expect(tripDatesText(t), '20 Oct 2026');
    });

    test('no date says so, and does not throw', () {
      expect(tripDatesText(<String, dynamic>{}), 'Not set');
      expect(tripEndOf(<String, dynamic>{}), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // the request
  // -------------------------------------------------------------------------
  group('a request', () {
    test('open while the server-set window is, closed after it', () {
      final r = ExperienceRequest.from('t1_boy', stub(editableDays: 3))!;
      expect(r.isOpen(), isTrue);
      expect(r.isOpen(DateTime.now().add(const Duration(days: 4))), isFalse);
    });

    test('no window at all is not open — never assume one', () {
      final data = stub()..remove('editableUntil');
      expect(ExperienceRequest.from('x', data)!.isOpen(), isFalse);
    });

    test('says until when, differently once it has been shared', () {
      final asked = ExperienceRequest.from('x', stub())!;
      final shared = ExperienceRequest.from('x', stub(status: 'submitted'))!;
      expect(asked.untilLine, startsWith('Open until '));
      expect(shared.untilLine, startsWith('You can edit this until '));
    });

    test('a document with no trip is dropped', () {
      expect(ExperienceRequest.from('x', null), isNull);
      expect(ExperienceRequest.from('x', {'studentUid': 'boy'}), isNull);
    });

    test('only open ones are offered, soonest to close first', () {
      final list = openRequests([
        MapEntry('a', stub(tripId: 'a', editableDays: 6)),
        MapEntry('b', stub(tripId: 'b', editableDays: 2)),
        MapEntry('c', stub(tripId: 'c', editableDays: -1)),
      ]);
      expect(list.map((r) => r.tripId), ['b', 'a'],
          reason: 'c has closed and is no longer something to show');
    });

    test('an empty form is not an experience', () {
      expect(hasAnyAnswer({'learned': '', 'touched': '  ', 'change': '\n'}), isFalse);
      expect(hasAnyAnswer({'learned': '', 'notes': 'Thank you'}), isTrue);
    });

    test('the three questions are the ones the guide reads', () {
      expect(kExperienceQuestions.map((q) => q.question), [
        'What did you learn?',
        'What touched you most?',
        'What will you change in your life?',
      ]);
    });
  });

  // -------------------------------------------------------------------------
  // the form
  // -------------------------------------------------------------------------
  Future<FakeFirebaseFirestore> world({Map<String, dynamic>? doc}) async {
    final fs = FakeFirebaseFirestore();
    await fs.collection('expeditionExperiences').doc('t1_boy').set(doc ?? stub());
    return fs;
  }

  Future<void> openForm(WidgetTester tester, FakeFirebaseFirestore fs,
      {String uid = 'boy', double scale = 1.0, bool dark = false}) async {
    phone(tester, scale);
    await tester.pumpWidget(host(
      ExpeditionExperienceForm(uid: uid, tripId: 't1', firestore: fs),
      dark: dark,
    ));
    await settle(tester);
  }

  testWidgets('it asks the three questions and gives a place for anything else',
      (tester) async {
    await openForm(tester, await world());
    expect(find.text('Your experience of Vrindavan Dham Yatra'), findsOneWidget);
    for (final q in kExperienceQuestions) {
      expect(find.text(q.question), findsOneWidget);
    }
    expect(find.text('Anything else you would like to say?'), findsOneWidget);
    expect(find.textContaining('not shown on your profile'), findsOneWidget);
  });

  testWidgets('sharing writes the answers and marks it submitted', (tester) async {
    final fs = await world();
    await openForm(tester, fs);

    await tester.enterText(find.byKey(const ValueKey('experience-learned')),
        'That service is the real yatra.');
    await tester.enterText(find.byKey(const ValueKey('experience-touched')),
        'The kirtan at dawn.');
    await tester.enterText(find.byKey(const ValueKey('experience-change')),
        'I will chant before I sleep.');
    await tester.enterText(find.byKey(const ValueKey('experience-notes')), 'Thank you.');
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await settle(tester);

    final doc = (await fs.collection('expeditionExperiences').doc('t1_boy').get()).data()!;
    expect(doc['status'], 'submitted');
    expect(doc['learned'], 'That service is the real yatra.');
    expect(doc['touched'], 'The kirtan at dawn.');
    expect(doc['change'], 'I will chant before I sleep.');
    expect(doc['notes'], 'Thank you.');
    expect(doc['submittedAt'], isNotNull);
    expect(doc['updatedAt'], isNotNull);
  });

  testWidgets('it touches nothing but the answers', (tester) async {
    // The rules allow only these keys; sending any other would be refused.
    final fs = await world();
    await openForm(tester, fs);
    await tester.enterText(find.byKey(const ValueKey('experience-learned')), 'Patience');
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await settle(tester);

    final before = stub();
    final after = (await fs.collection('expeditionExperiences').doc('t1_boy').get()).data()!;
    for (final k in ['tripId', 'tripName', 'studentUid', 'attendance']) {
      expect(after[k], before[k], reason: '$k must be exactly as the server wrote it');
    }
    expect(after['editableUntil'], isA<Timestamp>());
  });

  testWidgets('an empty form is refused and nothing is written', (tester) async {
    final fs = await world();
    await openForm(tester, fs);
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await settle(tester);

    expect(find.byKey(const ValueKey('experience-problem')), findsOneWidget);
    expect(find.text('Please write something before you share it'), findsOneWidget);
    final doc = (await fs.collection('expeditionExperiences').doc('t1_boy').get()).data()!;
    expect(doc['status'], 'requested');
  });

  testWidgets('the message clears as soon as they start writing', (tester) async {
    await openForm(tester, await world());
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await settle(tester);
    expect(find.byKey(const ValueKey('experience-problem')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('experience-learned')), 'x');
    await settle(tester);
    expect(find.byKey(const ValueKey('experience-problem')), findsNothing);
  });

  testWidgets('what was shared is shown again, and can be edited', (tester) async {
    final fs = await world(
        doc: stub(status: 'submitted', answers: {'learned': 'Patience', 'notes': 'Hare Krishna'}));
    await openForm(tester, fs);

    expect(find.text('Patience'), findsOneWidget);
    expect(find.text('Hare Krishna'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.textContaining('You can edit this until'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('experience-learned')), 'More patience');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await settle(tester);

    final doc = (await fs.collection('expeditionExperiences').doc('t1_boy').get()).data()!;
    expect(doc['learned'], 'More patience');
    expect(doc['status'], 'submitted');
  });

  testWidgets('editing does not move the day it was first shared', (tester) async {
    final first = Timestamp.fromDate(DateTime(2026, 10, 22));
    final fs = await world(
        doc: {...stub(status: 'submitted', answers: {'learned': 'Patience'}), 'submittedAt': first});
    await openForm(tester, fs);
    await tester.enterText(find.byKey(const ValueKey('experience-learned')), 'More');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await settle(tester);

    final doc = (await fs.collection('expeditionExperiences').doc('t1_boy').get()).data()!;
    expect(doc['submittedAt'], first);
  });

  testWidgets('once the window has closed it shows nothing of what was written',
      (tester) async {
    final fs = await world(
        doc: stub(status: 'submitted', editableDays: -1, answers: {'learned': 'SECRET-ANSWER'}));
    await openForm(tester, fs);

    expect(find.textContaining('The time to share this has passed'), findsOneWidget);
    expect(find.text('SECRET-ANSWER'), findsNothing,
        reason: 'it is written for the guides — not shown back after the window');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets("another student's request is nothing to share here", (tester) async {
    final fs = await world(doc: stub(uid: 'someone-else'));
    await openForm(tester, fs);
    expect(find.text("There's nothing to share here right now."), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a trip they were never asked about is nothing to share either',
      (tester) async {
    final fs = FakeFirebaseFirestore();
    await openForm(tester, fs);
    expect(find.text("There's nothing to share here right now."), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // the way in, from Expeditions
  // -------------------------------------------------------------------------
  Future<FakeFirebaseFirestore> expeditionsWorld() async {
    final fs = FakeFirebaseFirestore();
    await fs.collection('users').doc('boy').set(
        {'name': 'Arjun Kumar', 'gender': 'male', 'guideId': 'G'});
    return fs;
  }

  Future<void> openExpeditions(WidgetTester tester, FakeFirebaseFirestore fs,
      {double scale = 1.0, bool dark = false}) async {
    phone(tester, scale);
    await tester.pumpWidget(host(
      ExpeditionScreen(uid: 'boy', userName: 'Arjun Kumar', role: 'Stay at FOLK', firestore: fs),
      dark: dark,
    ));
    await settle(tester);
  }

  testWidgets('an open request appears at the top of Expeditions', (tester) async {
    final fs = await expeditionsWorld();
    await fs.collection('expeditionExperiences').doc('t1_boy').set(stub());
    await openExpeditions(tester, fs);

    expect(find.text('Share your experience'), findsOneWidget);
    expect(find.text('Share your experience of Vrindavan Dham Yatra'), findsOneWidget);
    expect(find.byKey(const ValueKey('experience-card-t1_boy')), findsOneWidget);
  });

  testWidgets('tapping it opens the form', (tester) async {
    final fs = await expeditionsWorld();
    await fs.collection('expeditionExperiences').doc('t1_boy').set(stub());
    await openExpeditions(tester, fs);

    await tester.tap(find.text('Share'));
    await settle(tester);
    expect(find.text('What did you learn?'), findsOneWidget);
  });

  testWidgets('a shared one offers Edit, not Share', (tester) async {
    final fs = await expeditionsWorld();
    await fs.collection('expeditionExperiences').doc('t1_boy').set(
        stub(status: 'submitted', answers: {'learned': 'x'}));
    await openExpeditions(tester, fs);
    expect(find.text('Your experience of Vrindavan Dham Yatra'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('a closed window leaves no trace in Expeditions', (tester) async {
    final fs = await expeditionsWorld();
    await fs.collection('expeditionExperiences').doc('t1_boy').set(
        stub(status: 'submitted', editableDays: -1, answers: {'learned': 'x'}));
    await openExpeditions(tester, fs);
    expect(find.text('Share your experience'), findsNothing);
    expect(find.textContaining('Vrindavan Dham Yatra'), findsNothing);
  });

  testWidgets('with nothing asked, Expeditions looks exactly as it did',
      (tester) async {
    await openExpeditions(tester, await expeditionsWorld());
    expect(find.text('Share your experience'), findsNothing);
    expect(find.text('Upcoming Trips'), findsOneWidget);
  });

  testWidgets("another student's request never shows here", (tester) async {
    final fs = await expeditionsWorld();
    await fs.collection('expeditionExperiences').doc('t1_other').set(stub(uid: 'other'));
    await openExpeditions(tester, fs);
    expect(find.text('Share your experience'), findsNothing);
  });

  rulesAgreementTest();

  // -------------------------------------------------------------------------
  // at every text size, light and dark
  // -------------------------------------------------------------------------
  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text $scale, 360 dp';

      testWidgets('the form fits ($s)', (tester) async {
        await openForm(
            tester,
            await world(
                doc: stub(
                    tripName: 'The Grand Parikrama of the Holy Dham of Sri Vrindavan and Surrounding Forests')),
            scale: scale,
            dark: dark);
        expect(tester.takeException(), isNull, reason: s);
        await tester.enterText(find.byKey(const ValueKey('experience-learned')),
            'A long answer that wraps over several lines. ' * 8);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: s);
      });

      testWidgets('the card in Expeditions fits ($s)', (tester) async {
        final fs = await expeditionsWorld();
        await fs.collection('expeditionExperiences').doc('t1_boy').set(stub(
            tripName: 'The Grand Parikrama of the Holy Dham of Sri Vrindavan and Surrounding Forests'));
        await openExpeditions(tester, fs, scale: scale, dark: dark);
        expect(tester.takeException(), isNull, reason: s);
        expect(find.textContaining('Grand Parikrama'), findsOneWidget);
      });
    }
  }
}

// The form and the rules are written apart, so nothing but this test ties them
// together: if the form ever wrote a field the rules do not allow, every save
// would be refused in production while every other test here stayed green.
// `firestore.rules` (expeditionExperiences) allows exactly these keys.
const _keysTheRulesAllow = {
  'learned', 'touched', 'change', 'notes', 'status', 'submittedAt', 'updatedAt',
};

void rulesAgreementTest() {
  testWidgets('the form changes only fields the rules allow a student to change',
      (tester) async {
    final fs = FakeFirebaseFirestore();
    final before = stub();
    await fs.collection('expeditionExperiences').doc('t1_boy').set(before);
    phone(tester, 1.0);
    await tester.pumpWidget(host(
        ExpeditionExperienceForm(uid: 'boy', tripId: 't1', firestore: fs)));
    await settle(tester);

    for (final f in ['learned', 'touched', 'change', 'notes']) {
      await tester.enterText(find.byKey(ValueKey('experience-$f')), 'answer $f');
    }
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await settle(tester);

    final after = (await fs.collection('expeditionExperiences').doc('t1_boy').get()).data()!;
    final changed = <String>{
      for (final k in {...before.keys, ...after.keys})
        if ('${before[k]}' != '${after[k]}') k,
    };
    expect(changed, isNotEmpty);
    expect(changed.difference(_keysTheRulesAllow), isEmpty,
        reason: 'a field the rules would refuse: ${changed.difference(_keysTheRulesAllow)}');
  });
}
