import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Scorecard.dart';
import 'package:folk_app/scores/BhagavatamClass.dart';
import 'package:folk_app/scores/BookReading.dart';
import 'package:folk_app/scores/Chanting.dart';
import 'package:folk_app/services/StudentApi.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SameGender.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Hostel and Localite students compete TOGETHER (one category), separate from
// FOLK; every ranking is split by gender too: four independent rankings.

GenderDirectory dir(String category, String mine) => GenderDirectory(
      category: category,
      mine: mine,
      femaleNames: {'Gopi', 'Gita', 'Radha'},
      femaleUids: {'g1'},
    );

// scorecard documents, stamped by the server with category + gender
Map<String, Map<String, dynamic>> scorecardDocs() => {
      'Arjun': {'category': 'folk', 'gender': 'male', 'totalChantRounds': 90},
      'Radha': {'category': 'folk', 'gender': 'female', 'totalChantRounds': 80},
      'Hari': {'category': 'hostel_localite', 'gender': 'male', 'totalChantRounds': 70},
      'Hans': {'category': 'hostel_localite', 'gender': 'male', 'totalChantRounds': 60},
      'Gopi': {'category': 'hostel_localite', 'gender': 'female', 'totalChantRounds': 50},
      'Old': {'gender': 'male', 'totalChantRounds': 40}, // not yet stamped with a category
    };

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  for (final e in scorecardDocs().entries) {
    await db.collection('scorecard').doc(e.key).set(e.value);
  }
  return db;
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

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  tearDown(() {
    GenderDirectory.useForTests(null);
    StudentApi.useForTests(null);
  });

  group('the category comes from the server callable', () {
    test('Hostel / Localite and FOLK; an old server with no category means FOLK', () async {
      Map<String, dynamic> answer = {};
      StudentApi.useForTests((name, data) async => answer);
      GenderDirectory.reset();
      answer = {'mine': 'male', 'category': 'hostel_localite', 'femaleNames': [], 'femaleUids': []};
      var d = await GenderDirectory.forCurrentUserForTestsViaApi();
      expect([d.category, d.isHostelLocalite, d.rankingId], ['hostel_localite', true, 'hostel_localite_male']);
      answer = {'mine': 'female', 'category': 'folk', 'femaleNames': ['Radha'], 'femaleUids': []};
      d = await GenderDirectory.forCurrentUserForTestsViaApi();
      expect([d.category, d.isHostelLocalite, d.rankingId], ['folk', false, 'folk_female']);
      answer = {'mine': 'male', 'femaleNames': [], 'femaleUids': []};
      d = await GenderDirectory.forCurrentUserForTestsViaApi();
      expect(d.category, 'folk');
      answer = {'mine': 'male', 'category': 'something-else', 'femaleNames': [], 'femaleUids': []};
      expect((await GenderDirectory.forCurrentUserForTestsViaApi()).category, 'folk');
    });
  });

  group('scorecard leaderboards: only my own category AND gender are ever queried', () {
    test('Hostel & Localite boy: Hari and Hans only', () async {
      GenderDirectory.useForTests(() async => dir('hostel_localite', 'male'));
      final docs = await readScorecardDocs(firestore: await seeded());
      expect(docs.keys.toSet(), {'Hari', 'Hans'});
    });

    test('Hostel & Localite girl: Gopi only', () async {
      GenderDirectory.useForTests(() async => dir('hostel_localite', 'female'));
      expect((await readScorecardDocs(firestore: await seeded())).keys.toSet(), {'Gopi'});
    });

    test('FOLK boy: Arjun only; FOLK girl: Radha only (H&L never leaks into FOLK)', () async {
      GenderDirectory.useForTests(() async => dir('folk', 'male'));
      expect((await readScorecardDocs(firestore: await seeded())).keys.toSet(), {'Arjun'});
      GenderDirectory.useForTests(() async => dir('folk', 'female'));
      expect((await readScorecardDocs(firestore: await seeded())).keys.toSet(), {'Radha'});
    });
  });

  group('weekly / monthly winners and participants: the student\'s own ranking document', () {
    Future<FakeFirebaseFirestore> results() async {
      final db = FakeFirebaseFirestore();
      final week = db.collection('competition-results').doc('weekly').collection('weeks').doc('2026-W41');
      await week.set({'topUsers': [{'name': 'Arjun'}]});
      await week.collection('byGender').doc('male').set({'topUsers': [{'name': 'Arjun'}]});
      await week.collection('byGender').doc('female').set({'topUsers': [{'name': 'Radha'}]});
      await week.collection('byCategory').doc('folk_male').set({'topUsers': [{'name': 'Arjun'}]});
      await week.collection('byCategory').doc('folk_female').set({'topUsers': [{'name': 'Radha'}]});
      await week.collection('byCategory').doc('hostel_localite_male').set({'topUsers': [{'name': 'Hans'}, {'name': 'Hari'}]});
      await week.collection('byCategory').doc('hostel_localite_female').set({'topUsers': [{'name': 'Gopi'}]});
      // a week finalized before categories existed: byGender only (that is FOLK)
      final old = db.collection('competition-results').doc('weekly').collection('weeks').doc('2026-W30');
      await old.collection('byGender').doc('male').set({'topUsers': [{'name': 'Bhima'}]});
      return db;
    }

    Future<List<String>> winners(FakeFirebaseFirestore db, GenderDirectory d, String week) async {
      GenderDirectory.useForTests(() async => d);
      final parent = db.collection('competition-results').doc('weekly').collection('weeks').doc(week);
      return [for (final u in await readMyGenderList(parent, 'topUsers')) u['name'].toString()];
    }

    test('each of the four rankings reads only its own document', () async {
      final db = await results();
      expect(await winners(db, dir('folk', 'male'), '2026-W41'), ['Arjun']);
      expect(await winners(db, dir('folk', 'female'), '2026-W41'), ['Radha']);
      expect(await winners(db, dir('hostel_localite', 'male'), '2026-W41'), ['Hans', 'Hari']);
      expect(await winners(db, dir('hostel_localite', 'female'), '2026-W41'), ['Gopi']);
    });

    test('an older week (byGender only) still shows for FOLK, and never for Hostel & Localite', () async {
      final db = await results();
      expect(await winners(db, dir('folk', 'male'), '2026-W30'), ['Bhima']);
      expect(await winners(db, dir('hostel_localite', 'male'), '2026-W30'), isEmpty);
    });
  });

  group('Leaderboard page: Daily Services is FOLK only', () {
    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale: FOLK sees four boards, Hostel & Localite three', (tester) async {
          phone(tester, scale);
          for (final category in ['folk', 'hostel_localite']) {
            GenderDirectory.useForTests(() async => dir(category, 'male'));
            await tester.pumpWidget(const SizedBox()); // a fresh page (its State) per category
            await tester.pumpWidget(host(ScorecardPage(), dark: dark));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$category');
            for (final t in ['Chanting', 'Book Reading', 'Bhagavatam Class']) {
              await tester.scrollUntilVisible(find.text(t), 200, scrollable: find.byType(Scrollable).first);
              expect(find.text(t), findsOneWidget, reason: '$category $t');
            }
            if (category == 'folk') {
              await tester.scrollUntilVisible(find.text('Daily Services'), 200, scrollable: find.byType(Scrollable).first);
              expect(find.text('Daily Services'), findsOneWidget);
            } else {
              await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
              await tester.pumpAndSettle();
              expect(find.text('Daily Services'), findsNothing);
            }
            expect(tester.takeException(), isNull, reason: '$category');
          }
        });
      }
    }
  });

  group('Hostel & Localite boards draw without overflow, light and dark, text 1.0 / 1.3 / 1.6', () {
    final hl = <String, Map<String, dynamic>>{
      'Hari Prasad Das Very Long Name Here': {'weekly.pts_chanting': 70, 'weekly.pts_reading': 30, 'weekly.pts_class': 9},
      'Hans': {'weekly.pts_chanting': 60, 'weekly.pts_reading': 20, 'weekly.pts_class': 8},
      'Hira': {'weekly.pts_chanting': 50, 'weekly.pts_reading': 10, 'weekly.pts_class': 7},
      'Hiren': {'weekly.pts_chanting': 40, 'weekly.pts_reading': 5, 'weekly.pts_class': 6},
    };
    Future<Map<String, Map<String, dynamic>>> read() async => hl;
    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale', (tester) async {
          phone(tester, scale);
          GenderDirectory.useForTests(() async => dir('hostel_localite', 'male'));
          for (final board in <Widget>[
            Chanting(reader: read),
            BookReading(reader: read),
            SBclasses(reader: read),
          ]) {
            await tester.pumpWidget(host(board, dark: dark));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Hans'), findsOneWidget);
          }
        });
      }
    }
  });

  group('the screens read through the category-aware helpers', () {
    String read(String f) => File(f).readAsStringSync();

    test('weekly / monthly competition streams filter by category and gender', () {
      for (final f in ['lib/scores/WeeklyResults.dart', 'lib/scores/MonthlyResults.dart']) {
        final src = read(f);
        expect(src, contains(".where('gender', isEqualTo: directory.mine)"), reason: f);
        expect(src, contains(".where('category', isEqualTo: directory.category)"), reason: f);
        // Hostel / Localite do not see the parts their form does not have
        expect(src, contains('_hostelLocalite'), reason: f);
        expect(src, contains('if (!_hostelLocalite)'), reason: f);
      }
    });

    test('Insights: Best Performer is open to Hostel & Localite too; Want to improve? is gone', () {
      final src = read('lib/pages/Competition.dart');
      expect(src.contains('_hostelForm'), isFalse);
      expect(src.contains('isHostelForm(widget.role)'), isFalse);
      expect(src.contains('Want to improve'), isFalse, reason: 'the tile is gone');
      expect(src.contains("title == 'Best Performer'"), isTrue, reason: 'it opens its page, not Coming soon');
    });

    test('Leaderboard page no longer blocks Hostel / Localite', () {
      final src = read('lib/pages/Scorecard.dart');
      expect(src.contains('Stay at Hostel'), isFalse);
      expect(src.contains('Coming soon'), isFalse);
    });
  });
}
