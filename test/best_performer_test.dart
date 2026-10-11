import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/models/BestPerformers.dart';
import 'package:folk_app/scores/BestPerformer.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Best performer: this week's two winners of the student's OWN category and gender,
// and last week's. Decided on the server (functions/bestPerformers.js).

GenderDirectory dir(String category, String mine) =>
    GenderDirectory(category: category, mine: mine, femaleNames: {}, femaleUids: {});

Map<String, dynamic> improved(String name, num increase) => {
      'name': name,
      'increase': increase,
      'reason': '+$increase points vs last week',
    };

Map<String, dynamic> keeper(String name, int commitment, int met) => {
      'name': name,
      'commitment': commitment,
      'daysMet': met,
      'weekDays': 7,
      'reason': 'kept $commitment rounds on $met of 7 days',
    };

Future<FakeFirebaseFirestore> results() async {
  final db = FakeFirebaseFirestore();
  Future<void> week(String id, String at, Map<String, Map<String, dynamic>> rankings) async {
    final ref = db.collection('competition-results').doc('weekly').collection('weeks').doc(id);
    await ref.set({'generatedAt': at});
    for (final e in rankings.entries) {
      await ref.collection('byCategory').doc(e.key).set(e.value);
    }
  }

  await week('2026-W40', '2026-10-04T00:05:00.000', {
    'folk_male': {'mostImproved': improved('Old Boy', 5), 'commitmentKeeper': null},
  });
  await week('2026-W41', '2026-10-11T00:05:00.000', {
    'folk_male': {'mostImproved': improved('Bhima', 10), 'commitmentKeeper': keeper('Chetan', 8, 5)},
    'folk_female': {'mostImproved': improved('Radha', 7), 'commitmentKeeper': null},
    'hostel_localite_male': {'mostImproved': null, 'commitmentKeeper': keeper('Hans', 12, 4)},
  });
  await week('2026-W42', '2026-10-18T00:05:00.000', {
    'folk_male': {'mostImproved': improved('Arjun', 24), 'commitmentKeeper': keeper('Arjun', 16, 6)},
    'folk_female': {'mostImproved': null, 'commitmentKeeper': keeper('Radha', 8, 7)},
    'hostel_localite_male': {'mostImproved': improved('Hari', 31.5), 'commitmentKeeper': keeper('Hari', 16, 6)},
    'hostel_localite_female': {'mostImproved': null, 'commitmentKeeper': null},
  });
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

Future<List<String>> winnersFor(FakeFirebaseFirestore db, GenderDirectory d) async {
  GenderDirectory.useForTests(() async => d);
  final b = await loadBestPerformers(firestore: db);
  String line(BestWeek? w) => w == null ? '-' : '${w.weekId}: ${w.mostImproved?.name ?? '-'} / ${w.commitmentKeeper?.name ?? '-'}';
  return [line(b.thisWeek), line(b.lastWeek)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  tearDown(() => GenderDirectory.useForTests(null));

  group('the winners are read from the student\'s OWN ranking document only', () {
    test('each of the four rankings sees its own winners, this week and last week', () async {
      final db = await results();
      expect(await winnersFor(db, dir('folk', 'male')), ['2026-W42: Arjun / Arjun', '2026-W41: Bhima / Chetan']);
      expect(await winnersFor(db, dir('folk', 'female')), ['2026-W42: - / Radha', '2026-W41: Radha / -']);
      expect(await winnersFor(db, dir('hostel_localite', 'male')), ['2026-W42: Hari / Hari', '2026-W41: - / Hans']);
      expect(await winnersFor(db, dir('hostel_localite', 'female')), ['2026-W42: - / -', '2026-W41: - / -']);
    });

    test('only the two most recent weeks are read, newest first', () async {
      final db = await results();
      GenderDirectory.useForTests(() async => dir('folk', 'male'));
      final b = await loadBestPerformers(firestore: db);
      expect([b.thisWeek!.weekId, b.lastWeek!.weekId], ['2026-W42', '2026-W41']);
    });

    test('no weeks yet: empty; one week: no last week', () async {
      GenderDirectory.useForTests(() async => dir('folk', 'male'));
      expect((await loadBestPerformers(firestore: FakeFirebaseFirestore())).isEmpty, isTrue);
      final db = FakeFirebaseFirestore();
      final ref = db.collection('competition-results').doc('weekly').collection('weeks').doc('2026-W42');
      await ref.set({'generatedAt': '2026-10-18T00:05:00.000'});
      await ref.collection('byCategory').doc('folk_male').set({'mostImproved': improved('Arjun', 3), 'commitmentKeeper': null});
      final b = await loadBestPerformers(firestore: db);
      expect(b.thisWeek!.mostImproved!.name, 'Arjun');
      expect(b.lastWeek, isNull);
    });

    test('a winner without a ready-made reason is described from the numbers; junk is no winner', () {
      expect(BestWinner.fromMap({'name': 'A', 'increase': 24})!.reason, '+24 points vs last week');
      expect(BestWinner.fromMap({'name': 'A', 'commitment': 16, 'daysMet': 6, 'weekDays': 7})!.reason, 'kept 16 rounds on 6 of 7 days');
      expect(BestWinner.fromMap({'name': 'A', 'increase': 31.5})!.reason, '+31.5 points vs last week');
      expect(BestWinner.fromMap(null), isNull);
      expect(BestWinner.fromMap({'name': ' '}), isNull);
      expect(BestWinner.fromMap('x'), isNull);
    });
  });

  group('the page', () {
    Future<BestPerformers> Function() loaderFor(FakeFirebaseFirestore db, GenderDirectory d) => () async {
          GenderDirectory.useForTests(() async => d);
          return loadBestPerformers(firestore: db);
        };

    testWidgets('shows both winners with their reasons, and last week\'s winners below', (tester) async {
      phone(tester, 1.0);
      final db = await results();
      await tester.pumpWidget(host(BestPerformerPage(username: 'Asha', loader: loaderFor(db, dir('folk', 'male')))));
      await tester.pumpAndSettle();
      expect(find.text("This week's winners"), findsOneWidget);
      expect(find.text('Most Improved'), findsWidgets);
      expect(find.text('Commitment Keeper'), findsWidgets);
      expect(find.text('Arjun'), findsNWidgets(2), reason: 'the same student can win both');
      expect(find.text('+24 points vs last week'), findsOneWidget);
      expect(find.text('kept 16 rounds on 6 of 7 days'), findsOneWidget);
      await tester.scrollUntilVisible(find.text("Last week's winners"), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text("Last week's winners"), findsOneWidget);
      expect(find.text('Bhima'), findsOneWidget);
      expect(find.text('+10 points vs last week'), findsOneWidget);
      expect(find.text('Chetan'), findsOneWidget);
      // never another group's winners
      for (final n in ['Radha', 'Hari', 'Hans', 'Old Boy']) {
        expect(find.text(n), findsNothing, reason: n);
      }
    });

    testWidgets('a Hostel & Localite student sees their own ranking', (tester) async {
      phone(tester, 1.0);
      final db = await results();
      await tester.pumpWidget(host(BestPerformerPage(username: 'Hans', loader: loaderFor(db, dir('hostel_localite', 'male')))));
      await tester.pumpAndSettle();
      expect(find.text('Hari'), findsNWidgets(2));
      expect(find.text('+31.5 points vs last week'), findsOneWidget);
      expect(find.text('Arjun'), findsNothing);
    });

    testWidgets('a winner who is the viewer gets a warm highlight', (tester) async {
      phone(tester, 1.0);
      final db = await results();
      await tester.pumpWidget(host(BestPerformerPage(username: 'Arjun', loader: loaderFor(db, dir('folk', 'male')))));
      await tester.pumpAndSettle();
      expect(find.textContaining("That's you!"), findsNWidgets(2));
      // someone else: no highlight
      await tester.pumpWidget(host(BestPerformerPage(username: 'Asha', loader: loaderFor(db, dir('folk', 'male')))));
      await tester.pumpAndSettle();
      expect(find.textContaining("That's you!"), findsNothing);
    });

    testWidgets('last week\'s winner who is the viewer is marked too', (tester) async {
      phone(tester, 1.0);
      final db = await results();
      await tester.pumpWidget(host(BestPerformerPage(username: 'Bhima', loader: loaderFor(db, dir('folk', 'male')))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Bhima — that was you!'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Bhima — that was you!'), findsOneWidget);
    });

    testWidgets('nobody qualified: friendly lines, no crash', (tester) async {
      phone(tester, 1.0);
      final db = await results();
      await tester.pumpWidget(host(BestPerformerPage(username: 'Gopi', loader: loaderFor(db, dir('hostel_localite', 'female')))));
      await tester.pumpAndSettle();
      expect(find.textContaining('No winner yet'), findsNWidgets(2));
      await tester.scrollUntilVisible(find.text("Last week's winners"), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('No winner last week.'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no weekly results at all yet: one friendly message', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BestPerformerPage(username: 'Asha', loader: () async => const BestPerformers())));
      await tester.pumpAndSettle();
      expect(find.textContaining('The first winners will appear'), findsOneWidget);
    });

    testWidgets('loading shows ghosts, not a spinner; an error offers Try again', (tester) async {
      phone(tester, 1.0);
      var calls = 0;
      await tester.pumpWidget(host(BestPerformerPage(
        username: 'Asha',
        loader: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (calls == 1) throw StateError('offline');
          return const BestPerformers(thisWeek: BestWeek(weekId: 'w', mostImproved: BestWinner(name: 'Arjun', reason: '+1 points vs last week')));
        },
      )));
      await tester.pump();
      expect(find.byType(LeaderboardGhost), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text("Couldn't load the winners just now."), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Arjun'), findsOneWidget);
      expect(calls, 2);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale: no overflow, real fonts (winner / empty / highlighted)', (tester) async {
          phone(tester, scale);
          final db = await results();
          for (final c in [
            (dir('folk', 'male'), 'Arjun'),
            (dir('folk', 'male'), 'Asha'),
            (dir('hostel_localite', 'female'), 'Gopi'),
          ]) {
            await tester.pumpWidget(host(BestPerformerPage(username: c.$2, loader: loaderFor(db, c.$1)), dark: dark));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '${c.$2} dark=$dark scale=$scale');
          }
        });
      }
    }

    test('a long name and a long reason do not break the layout (they wrap)', () {
      // covered by the widget run above at 1.6; the card texts have no maxLines cap
      final w = BestWinner.fromMap({'name': 'A very long student name indeed here', 'reason': 'kept 16 rounds on 6 of 7 days'});
      expect(w!.name.length, greaterThan(30));
    });
  });
}
