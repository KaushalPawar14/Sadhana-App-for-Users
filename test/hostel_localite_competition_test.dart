import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/LeaderboardPage.dart';
import 'package:folk_app/utils/LeaderboardData.dart';
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

// competition documents, stamped by the server with category + gender
Map<String, Map<String, dynamic>> competitionDocs() => {
      'Arjun': {'category': 'folk', 'gender': 'male', 'weekly.total_score': 90},
      'Radha': {'category': 'folk', 'gender': 'female', 'weekly.total_score': 80},
      'Hari': {'category': 'hostel_localite', 'gender': 'male', 'weekly.total_score': 70},
      'Hans': {'category': 'hostel_localite', 'gender': 'male', 'weekly.total_score': 60},
      'Gopi': {'category': 'hostel_localite', 'gender': 'female', 'weekly.total_score': 50},
      'Old': {'gender': 'male', 'weekly.total_score': 40}, // not yet stamped with a category
    };

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  for (final e in competitionDocs().entries) {
    await db.collection('competition').doc(e.key).set(e.value);
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

  group('the Leaderboard reads only my own category AND gender', () {
    Future<List<String>> shown(WidgetTester tester, GenderDirectory d) async {
      GenderDirectory.useForTests(() async => d);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(LeaderboardPage(username: 'nobody', firestore: await seeded(), changesLoader: (_) async => {})));
      await tester.pumpAndSettle();
      final names = <String>[];
      for (final n in ['Arjun', 'Radha', 'Hari', 'Hans', 'Gopi', 'Old']) {
        if (find.text(n).evaluate().isNotEmpty) names.add(n);
      }
      return names;
    }

    testWidgets('Hostel & Localite boy: Hari and Hans only', (tester) async {
      phone(tester, 1.0);
      expect(await shown(tester, dir('hostel_localite', 'male')), ['Hari', 'Hans']);
    });

    testWidgets('Hostel & Localite girl: Gopi only', (tester) async {
      phone(tester, 1.0);
      expect(await shown(tester, dir('hostel_localite', 'female')), ['Gopi']);
    });

    testWidgets('FOLK boy: Arjun only; FOLK girl: Radha only (H&L never leaks into FOLK)', (tester) async {
      phone(tester, 1.0);
      expect(await shown(tester, dir('folk', 'male')), ['Arjun']);
      expect(await shown(tester, dir('folk', 'female')), ['Radha']);
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

  group('Leaderboard page: Best Service is FOLK only', () {
    final docs = {
      'Asha': {'category': 'x', 'gender': 'male', 'weekly.total_score': 100, 'weekly.pts_chanting': 50, 'weekly.pts_reading': 50, 'weekly.pts_hearing': 50, 'weekly.pts_service': 50},
    };
    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale: FOLK sees four Best cards, Hostel & Localite three', (tester) async {
          phone(tester, scale);
          for (final category in ['folk', 'hostel_localite']) {
            GenderDirectory.useForTests(() async => dir(category, 'male'));
            await tester.pumpWidget(const SizedBox()); // a fresh page (its State) per category
            await tester.pumpWidget(host(
              LeaderboardPage(username: 'Asha', docsStream: Stream.value(docs), changesLoader: (_) async => {}, initialTab: LeaderboardTab.scores),
              dark: dark,
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$category');
            final list = find.byType(Scrollable).first;
            for (final f in ['chanting', 'reading', 'hearing']) {
              await tester.scrollUntilVisible(find.byKey(ValueKey('best-$f')), 250, scrollable: list);
              expect(find.byKey(ValueKey('best-$f')), findsOneWidget, reason: '$category $f');
            }
            if (category == 'folk') {
              await tester.scrollUntilVisible(find.byKey(const ValueKey('best-service')), 250, scrollable: list);
              expect(find.byKey(const ValueKey('best-service')), findsOneWidget);
            } else {
              await tester.drag(list, const Offset(0, -3000));
              await tester.pumpAndSettle();
              expect(find.byKey(const ValueKey('best-service')), findsNothing);
            }
            expect(tester.takeException(), isNull, reason: '$category');
          }
        });
      }
    }
  });

  group('the screens read through the category-aware helpers', () {
    String read(String f) => File(f).readAsStringSync();

    test('the Leaderboard\'s competition stream filters by category and gender', () {
      for (final f in ['lib/pages/LeaderboardPage.dart']) {
        final src = read(f);
        expect(src, contains(".where('gender', isEqualTo: directory.mine)"), reason: f);
        expect(src, contains(".where('category', isEqualTo: directory.category)"), reason: f);
        // Hostel / Localite do not see the parts their form does not have
        expect(src, contains('f.folkOnly && hostel'), reason: f);
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
      final src = read('lib/pages/LeaderboardPage.dart');
      expect(src.contains('Stay at Hostel'), isFalse);
      expect(src.contains('Coming soon'), isFalse);
    });
  });
}
