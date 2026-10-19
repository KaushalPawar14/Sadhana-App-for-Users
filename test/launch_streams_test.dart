import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/SeenMarkers.dart';

// The Student app's launch queries (the bottom bar's "new" dots). The live rules show a student only the active trips of
// their own gender and refuse an UNFILTERED read of `expeditions` (that refused read was the unhandled
// "permission-denied" in the device log); the app now asks for exactly what the rules allow, and a stream that fails
// is "no dot", never an unhandled exception.
Timestamp ts(int day) => Timestamp.fromDate(DateTime.utc(2026, 10, day));

Future<FakeFirebaseFirestore> world() async {
  final db = FakeFirebaseFirestore();
  await db.doc('users/boy').set({'name': 'A Boy', 'gender': 'male'});
  await db.doc('users/girl').set({'name': 'A Girl', 'gender': 'female'});
  await db.doc('users/nogender').set({'name': 'No Gender'});
  await db.doc('expeditions/m1').set({'targetGender': 'male', 'archived': false, 'createdAt': ts(2)});
  await db.doc('expeditions/m1b').set({'targetGender': 'male', 'archived': false, 'createdAt': ts(4)});
  await db.doc('expeditions/m2').set({'targetGender': 'male', 'archived': true, 'createdAt': ts(20)}); // archived: not shown
  await db.doc('expeditions/f1').set({'targetGender': 'female', 'archived': false, 'createdAt': ts(9)});
  return db;
}

void main() {
  group('expeditionsLatest: only what the rules allow a student to read', () {
    test('a boy: his own gender\'s active trips only (not the girls\' trip, not the archived one)', () async {
      final db = await world();
      expect(await expeditionsLatest(db, 'boy').first, ts(4));
    });

    test('a girl: only the girls\' trip', () async {
      final db = await world();
      expect(await expeditionsLatest(db, 'girl').first, ts(9));
    });

    test('no gender on file, or no profile at all: male, like the apps and the rules', () async {
      final db = await world();
      expect(await expeditionsLatest(db, 'nogender').first, ts(4));
      expect(await expeditionsLatest(db, 'nobody').first, ts(4));
    });

    test('nothing to show: null (no dot)', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/boy').set({'gender': 'male'});
      expect(await expeditionsLatest(db, 'boy').first, isNull);
    });

    test('it follows a new trip live', () async {
      final db = await world();
      final seen = <Timestamp?>[];
      final sub = expeditionsLatest(db, 'boy').listen(seen.add);
      await pumpEventQueue();
      await db.doc('expeditions/m3').set({'targetGender': 'male', 'archived': false, 'createdAt': ts(25)});
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, ts(4));
      expect(seen.last, ts(25));
    });
  });

  group('a failing stream is "no dot", never an unhandled error', () {
    Stream<bool> failing() => Stream<bool>.error(StateError('permission-denied'));

    test('anyUnseenOf: one source fails, another says unseen -> true', () async {
      final errors = <Object>[];
      final out = <bool>[];
      await runZonedGuarded(() async {
        final sub = anyUnseenOf([failing(), Stream.value(true)]).listen(out.add);
        await pumpEventQueue();
        await sub.cancel();
      }, (e, s) => errors.add(e));
      expect(errors, isEmpty, reason: 'no uncaught error');
      expect(out, isNotEmpty);
      expect(out.last, true);
    });

    test('anyUnseenOf: every source fails -> false', () async {
      final errors = <Object>[];
      final out = <bool>[];
      await runZonedGuarded(() async {
        final sub = anyUnseenOf([failing(), failing()]).listen(out.add);
        await pumpEventQueue();
        await sub.cancel();
      }, (e, s) => errors.add(e));
      expect(errors, isEmpty);
      expect(out.last, false);
    });

    test('SeenMarkers.unseenFrom: a failing "latest" or "seen" input -> no dot, no uncaught error', () async {
      for (final pair in [
        (Stream<Timestamp?>.error(StateError('denied')), Stream<Timestamp?>.value(ts(1))),
        (Stream<Timestamp?>.value(ts(5)), Stream<Timestamp?>.error(StateError('denied'))),
        (Stream<Timestamp?>.error(StateError('denied')), Stream<Timestamp?>.error(StateError('denied'))),
      ]) {
        final errors = <Object>[];
        final out = <bool>[];
        await runZonedGuarded(() async {
          final sub = SeenMarkers.unseenFrom(pair.$1, pair.$2).listen(out.add);
          await pumpEventQueue();
          await sub.cancel();
        }, (e, s) => errors.add(e));
        expect(errors, isEmpty, reason: 'no uncaught error');
        expect(out, isNotEmpty);
      }
    });

    test('SeenMarkers.unseenFrom still works when nothing fails', () async {
      final out = <bool>[];
      final sub = SeenMarkers.unseenFrom(Stream.value(ts(5)), Stream.value(ts(1))).listen(out.add);
      await pumpEventQueue();
      await sub.cancel();
      expect(out.last, true);
      final out2 = <bool>[];
      final sub2 = SeenMarkers.unseenFrom(Stream.value(ts(1)), Stream.value(ts(5))).listen(out2.add);
      await pumpEventQueue();
      await sub2.cancel();
      expect(out2.last, false);
    });
  });
}
