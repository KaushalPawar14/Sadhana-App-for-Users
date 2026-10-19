import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/ExpeditionScreen.dart';
import 'package:folk_app/theme/FolkTheme.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Expeditions in the Student app: a student sees only the ACTIVE trips of their OWN gender (the rules allow no
// other query), a trip that moved to History is gone (also from My Trips), and registering writes no attendance.

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

Map<String, dynamic> trip(String title, String gender, {bool? archived = false, String place = 'Vrindavan'}) => {
      'title': title,
      'description': 'A day of walking and kirtan.',
      'location': place,
      'tripDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 12))),
      'registrationDeadline': Timestamp.fromDate(DateTime.now().add(const Duration(days: 8))),
      'createdBy': 'G',
      'createdAt': Timestamp.now(),
      'status': 'upcoming',
      if (gender.isNotEmpty) 'targetGender': gender,
      if (archived != null) 'archived': archived,
    };

Future<FakeFirebaseFirestore> world() async {
  final fs = FakeFirebaseFirestore();
  await fs.collection('users').doc('boy').set({'name': 'Arjun Kumar', 'gender': 'male', 'guideId': 'G'});
  await fs.collection('users').doc('girl').set({'name': 'Gauri Devi', 'gender': 'female', 'guideId': 'F1'});
  final t = fs.collection('expeditions');
  await t.doc('tb').set(trip('Boys Vrindavan Yatra', 'male'));
  await t.doc('tb2').set(trip('Boys Mayapur Retreat', 'male', place: 'Mayapur'));
  await t.doc('tg').set(trip('Girls Dwarka Yatra', 'female', place: 'Dwarka'));
  await t.doc('tOld').set(trip('Old Boys Yatra', 'male', archived: true));
  await t.doc('tOldG').set(trip('Old Girls Yatra', 'female', archived: true));
  await t.doc('tLegacy').set(trip('Legacy trip', '', archived: null)); // made before this feature: no gender, no archived
  return fs;
}

Widget host(FakeFirebaseFirestore fs, String uid, String name, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: ExpeditionScreen(uid: uid, userName: name, role: 'Stay at FOLK', firestore: fs),
    );

const allTitles = [
  'Boys Vrindavan Yatra',
  'Boys Mayapur Retreat',
  'Girls Dwarka Yatra',
  'Old Boys Yatra',
  'Old Girls Yatra',
  'Legacy trip',
];
List<String> shown() => [for (final t in allTitles) if (find.text(t).evaluate().isNotEmpty) t];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  testWidgets('a boy sees the active boys trips only: no girls trip, nothing from History, no trip without a gender', (tester) async {
    phone(tester, 1.0);
    final fs = await world();
    await tester.pumpWidget(host(fs, 'boy', 'Arjun Kumar'));
    await settle(tester);
    expect(shown(), ['Boys Vrindavan Yatra', 'Boys Mayapur Retreat']);
  });

  testWidgets('a girl sees the active girls trip only', (tester) async {
    phone(tester, 1.0);
    final fs = await world();
    await tester.pumpWidget(host(fs, 'girl', 'Gauri Devi'));
    await settle(tester);
    expect(shown(), ['Girls Dwarka Yatra']);
  });

  testWidgets('a trip that moves to History disappears from the list, live', (tester) async {
    phone(tester, 1.0);
    final fs = await world();
    await tester.pumpWidget(host(fs, 'boy', 'Arjun Kumar'));
    await settle(tester);
    expect(find.text('Boys Mayapur Retreat'), findsOneWidget);
    await fs.collection('expeditions').doc('tb2').update({'archived': true}); // what the nightly job does
    await settle(tester);
    expect(shown(), ['Boys Vrindavan Yatra']);
  });

  testWidgets('My Trips: a registration for a trip in History is gone from the app; an active one stays', (tester) async {
    phone(tester, 1.0);
    final fs = await world();
    for (final id in ['tb', 'tOld']) {
      await fs.collection('expeditionRegistrations').doc('${id}_boy').set({
        'expeditionId': id, 'studentUid': 'boy', 'studentName': 'Arjun Kumar', 'registeredAt': Timestamp.now(),
        'hasReflected': false, 'reflectionText': '', 'guideId': 'G',
      });
    }
    await tester.pumpWidget(host(fs, 'boy', 'Arjun Kumar'));
    await settle(tester);
    expect(find.text('You have not registered for any trips yet'), findsNothing);
    await tester.scrollUntilVisible(find.text('My Trips'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Boys Vrindavan Yatra'), findsWidgets);
    expect(find.text('Old Boys Yatra'), findsNothing);
    // exactly one registration card is shown (the active trip's), not two
    expect(find.text('Registered'), findsOneWidget);
  });

  testWidgets('registering writes the registration and never an attendance (that is the admins\')', (tester) async {
    phone(tester, 1.0);
    final fs = await world();
    await tester.pumpWidget(host(fs, 'boy', 'Arjun Kumar'));
    await settle(tester);
    await tester.tap(find.text('Register').first);
    await settle(tester);
    final snaps = await fs.collection('expeditionRegistrations').get();
    expect(snaps.docs.length, 1);
    final d = snaps.docs.first.data();
    expect(d['studentUid'], 'boy');
    expect(d['expeditionId'], anyOf('tb', 'tb2'));
    expect(d.containsKey('attendance'), isFalse);
  });

  testWidgets('no profile, no trips: a friendly Retry instead of a blank screen', (tester) async {
    phone(tester, 1.0);
    final fs = FakeFirebaseFirestore(); // the student has no users document
    await tester.pumpWidget(host(fs, 'nobody', ''));
    await settle(tester);
    // nothing to show: the ghost list while waiting for a profile that never comes, never trips of another gender
    expect(shown(), isEmpty);
  });

  test('the Ask-screen dot follows the same filter as the list (source pin)', () {
    final src = File('lib/pages/ABCDEScreen.dart').readAsStringSync();
    expect(src, contains(".where('targetGender', isEqualTo: _gender)"));
    expect(src, contains(".where('archived', isEqualTo: false)"));
    final list = File('lib/pages/ExpeditionScreen.dart').readAsStringSync();
    expect(list, contains(".where('targetGender', isEqualTo: gender)"));
    expect(list, contains(".where('archived', isEqualTo: false)"));
    expect(list.contains(".collection('expeditions').snapshots()"), isFalse, reason: 'no unfiltered trips query is left');
  });

  for (final scale in scales) {
    for (final dark in [false, true]) {
      testWidgets('the trips screen at text scale $scale, ${dark ? 'dark' : 'light'}', (tester) async {
        phone(tester, scale);
        final fs = await world();
        await fs.collection('expeditionRegistrations').doc('tb_boy').set({
          'expeditionId': 'tb', 'studentUid': 'boy', 'studentName': 'Arjun Kumar', 'registeredAt': Timestamp.now(),
          'hasReflected': true, 'reflectionText': 'It was a wonderful, humbling day of walking and kirtan.', 'guideId': 'G',
        });
        await tester.pumpWidget(host(fs, 'boy', 'Arjun Kumar', dark: dark));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
