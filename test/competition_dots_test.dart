// ignore_for_file: depend_on_referenced_packages (firebase_core_platform_interface comes with firebase_core)
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/MyCompetitions.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BottomNavBar.dart' show hostNavItems;
import 'package:folk_app/utils/CompetitionDots.dart';
import 'package:folk_app/utils/SeenMarkers.dart';
import 'package:folk_app/utils/UnseenDot.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';

import 'text_scale_test.dart' show loadAppFonts;

// THE DOT TRAIL OF A NEW CHANTING COMPETITION (and of its result): Profile tab -> the "My Competitions" row -> the competition's own card. Per student, per competition; it clears when the
// student has seen that competition; nothing flashes on start (nothing is shown until the competitions and the seen markers are live; a marker still being written is already a marker).
const uid = 'u1';
final now = DateTime(2026, 10, 30, 10);

Timestamp day(int d) => Timestamp.fromDate(DateTime(2026, 10, d));

Future<FakeFirebaseFirestore> world({List<Map<String, dynamic>> challenges = const [], String guide = 'G1', String studentUid = uid}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(studentUid).set({'name': 'Arjun', 'guideId': guide});
  for (final c in challenges) {
    final id = c['id'] as String;
    await db.collection('chantingChallenges').doc(id).set({...c}..remove('id'));
  }
  return db;
}

Map<String, dynamic> active(String id, {String guideId = 'G1', int target = 20}) => {'id': id, 'name': 'Challenge $id', 'status': 'active', 'guideId': guideId, 'targetRounds': 1000, 'currentTotal': 0, 'targetDate': day(target)};
Map<String, dynamic> ended(String id, String status, {int target = 29}) => {'id': id, 'name': 'Challenge $id', 'status': status, 'guideId': 'G1', 'targetRounds': 1000, 'currentTotal': 900, 'targetDate': day(target)};

Future<bool> first(Stream<bool> s) async {
  final c = Completer<bool>();
  final sub = s.listen(c.complete);
  final v = await c.future.timeout(const Duration(seconds: 5));
  await sub.cancel();
  return v;
}

Future<Set<String>> firstKeys(Stream<Set<String>> s) async {
  final c = Completer<Set<String>>();
  final sub = s.listen(c.complete);
  final v = await c.future.timeout(const Duration(seconds: 5));
  await sub.cancel();
  return v;
}

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

Widget host(Widget home) => MaterialApp(
      theme: FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  setUp(() => CompetitionDots.clock = () => now);
  tearDown(() {
    CompetitionDots.override = null;
    CompetitionDots.clock = DateTime.now;
  });

  group('THE RULE: what is new, per student and per competition', () {
    test('an active competition is new until its key is seen; each competition has its own key', () {
      final cs = [active('c1'), active('c2')];
      expect(CompetitionDots.unseenOf(cs, {}, now), {'new_c1', 'new_c2'});
      expect(CompetitionDots.unseenOf(cs, {'new_c1'}, now), {'new_c2'});
      expect(CompetitionDots.unseenOf(cs, {'new_c1', 'new_c2'}, now), isEmpty);
    });

    test('RESULTS published (achieved or missed) inside the window are new; older ones, a closed-by-hand one and a still-active one give no result dot', () {
      final cs = [ended('won', 'achieved'), ended('lost', 'missed'), ended('old', 'achieved', target: 20), ended('manual', 'closed'), active('now')];
      expect(CompetitionDots.unseenOf(cs, {}, now), {'result_won', 'result_lost', 'new_now'}, reason: 'the 20th is more than two days back; "closed" publishes no result');
      expect(CompetitionDots.unseenOf(cs, {'result_won', 'new_now'}, now), {'result_lost'});
    });

    test('a competition without an id or a date is never a dot', () {
      expect(CompetitionDots.unseenOf([{'status': 'active'}, {...ended('x', 'achieved')}..remove('targetDate')], {}, now), isEmpty);
    });
  });

  group('THE DATA: only this student\'s competitions, live, no flash', () {
    test('nothing: no dot; a competition of HIS guide lights it; one of ANOTHER guide does not; a HOD\'s for all students does', () async {
      expect(await first(CompetitionDots(await world(), uid).anyUnseen), false);
      expect(await first(CompetitionDots(await world(challenges: [active('c1')]), uid).anyUnseen), true);
      expect(await first(CompetitionDots(await world(challenges: [active('c1', guideId: 'G2')]), uid).anyUnseen), false, reason: 'another guide\'s competition');
      expect(await first(CompetitionDots(await world(challenges: [{...active('c1', guideId: 'G2'), 'allStudents': true}]), uid).anyUnseen), true);
      expect(await first(CompetitionDots(await world(challenges: [{...active('c1', guideId: 'G2'), 'guideIds': ['G1']}]), uid).anyUnseen), true);
    });

    test('a student with no guide has no competitions and no dot', () async {
      final db = await world(challenges: [active('c1')], guide: '');
      expect(await first(CompetitionDots(db, uid).anyUnseen), false);
    });

    test('SEEING it clears it for THAT student only; a second competition lights the trail again; the other competition keeps its own dot', () async {
      final db = await world(challenges: [active('c1'), active('c2')]);
      final d = CompetitionDots(db, uid);
      expect(await firstKeys(d.unseenKeysStream(clock: () => now)), {'new_c1', 'new_c2'});
      await d.markSeen([CompetitionDots.newKey('c1')]);
      expect(await first(d.unseenFor('new_c1')), false);
      expect(await first(d.unseenFor('new_c2')), true, reason: 'c2 is still new');
      expect(await first(d.anyUnseen), true);
      await d.markSeen([CompetitionDots.newKey('c2')]);
      expect(await first(d.anyUnseen), false);
      // another student of the same guide has seen nothing
      await db.collection('users').doc('u2').set({'name': 'Hari', 'guideId': 'G1'});
      expect(await first(CompetitionDots(db, 'u2').anyUnseen), true, reason: 'per student');
      // a NEW competition after that
      await db.collection('chantingChallenges').doc('c3').set(active('c3')..remove('id'));
      expect(await first(d.anyUnseen), true);
      expect(await first(d.unseenFor('new_c3')), true);
    });

    test('A RESULT: when it ends, the competition he saw has a result dot of its own; seeing the result clears it', () async {
      final db = await world(challenges: [active('c1', target: 29)]);
      final d = CompetitionDots(db, uid);
      await d.markSeen([CompetitionDots.newKey('c1')]);
      expect(await first(d.anyUnseen), false);
      await db.collection('chantingChallenges').doc('c1').set({'status': 'achieved', 'closedAt': Timestamp.fromDate(now)}, SetOptions(merge: true));
      expect(await first(d.unseenFor(CompetitionDots.resultKey('c1'))), true, reason: 'the result is new');
      expect(await first(d.unseenFor(CompetitionDots.newKey('c1'))), false);
      await d.markSeen([CompetitionDots.resultKey('c1')]);
      expect(await first(d.anyUnseen), false);
    });

    test('NO FLASH: the first thing emitted is the live answer; a marker still being written already counts as seen; a stale cache is not shown', () async {
      final d = CompetitionDots(await world(challenges: [active('c1')]), uid);
      final shown = <bool>[];
      final sub = d.anyUnseen.listen(shown.add);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(shown, [true], reason: 'one answer, no "false then true"');
      // his own write is pending: the key is in the map at once, so the dot goes and never comes back
      unawaited(d.markSeen([CompetitionDots.newKey('c1')]));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(shown.last, false);
      expect(shown.skipWhile((v) => v).every((v) => !v), isTrue, reason: 'never lit again: $shown');
      await sub.cancel();
      expect(SeenMarkers.isLive(fromCache: true, hasPendingWrites: false), isFalse, reason: 'a cache alone is not live');
      expect(SeenMarkers.isLive(fromCache: true, hasPendingWrites: true), isTrue);
      expect(SeenMarkers.seenValue(null, pending: true), SeenMarkers.everythingSeen, reason: 'a pending write is "seen", never empty');
      expect(SeenMarkers.seenValue(null, pending: false), isNull);
    });

    test('a failing marker write is swallowed (the dot just stays)', () async {
      final d = CompetitionDots(await world(), uid);
      await d.markSeen(const []);
      await d.markSeen(['']);
      expect(true, isTrue);
    });
  });

  group('THE TRAIL on screen', () {
    testWidgets('the PROFILE TAB of the nav pill has the dot, the others do not', (tester) async {
      phone(tester, 1.0);
      final profile = StreamController<bool>.broadcast();
      addTearDown(profile.close);
      await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
          body: const SizedBox(),
          bottomNavigationBar: FloatingPillNavBar(items: hostNavItems(context, profileUnseen: profile.stream), currentIndex: 0, onTap: (_) {}),
        ),
      )));
      await tester.pump();
      expect(find.byType(UnseenDot), findsNothing, reason: 'nothing until the live answer');
      profile.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(UnseenDot), findsOneWidget);
      final nav = tester.getRect(find.byType(FloatingPillNavBar));
      expect(tester.getRect(find.byType(UnseenDot)).center.dx, greaterThan(nav.left + nav.width * 3 / 4 - 12), reason: 'on the last tab (Profile)');
      profile.add(false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(UnseenDot), findsNothing);
    });

    testWidgets('the Profile ROW "My Competitions" is made of the same stream as the tab, and the page marks what it showed when he leaves', (tester) async {
      final profile = File('lib/pages/Profile.dart').readAsStringSync();
      expect(profile, contains("ValueKey('my-competitions-dot')"));
      expect(profile, contains('CompetitionDots.forCurrentUser()?.anyUnseen'));
      final nav = File('lib/utils/BottomNavBar.dart').readAsStringSync();
      expect(nav, contains('CompetitionDots.forCurrentUser()?.anyUnseen'), reason: 'the tab and the row read the one definition');
      final page = File('lib/pages/MyCompetitions.dart').readAsStringSync();
      expect(page, contains('_dots?.markSeen(_shown)'));
    });

    testWidgets('THE COMPETITION\'S OWN CARD: its dot is on while he is on "My Competitions" (he sees which one is new); when he leaves the page it is seen and every dot of the trail is gone', (tester) async {
      phone(tester, 1.0);
      final db = await world(challenges: [active('c1')]);
      final dots = CompetitionDots(db, uid);
      CompetitionDots.override = dots;
      await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MyCompetitionsPage(
                    chantingSection: const CompetitionDot(dotKey: 'new_c1', child: SizedBox(height: 120, width: 300, child: Card(child: Text('CHALLENGE C1')))),
                    badgesLoader: () async => {'gold_badge': 0, 'silver_badge': 0, 'bronze_badge': 0, 'weekly_winner': 0},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump();
        }
      }

      expect(await tester.runAsync(() => first(dots.anyUnseen)), true, reason: 'the trail is lit before he opens it');
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await settle();
      expect(find.text('CHALLENGE C1'), findsOneWidget);
      expect(find.byKey(const ValueKey('competition-dot-new_c1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('competition-dot-new_c1')), matching: find.byType(UnseenDot)), findsOneWidget, reason: 'the card shows its dot on the page');
      // while he is on the page nothing has been marked yet
      expect(await tester.runAsync(() => first(dots.anyUnseen)), true);
      // he leaves: it is seen
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await settle();
      expect(await tester.runAsync(() => first(dots.anyUnseen)), false, reason: 'seen: the tab, the row and the card are clear');
      final marker = (await db.doc('seenMarkers/$uid').get()).data()!;
      expect((marker['chantingSeen'] as Map).keys, ['new_c1']);
    });

    testWidgets('a competition card without anything new has no dot, at text scale 1.6 too', (tester) async {
      phone(tester, 1.6);
      CompetitionDots.override = CompetitionDots(await world(), uid);
      await tester.pumpWidget(host(const Scaffold(body: CompetitionDot(dotKey: 'new_c9', child: SizedBox(height: 80, width: 300, child: Card(child: Text('QUIET')))))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.byType(UnseenDot), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
