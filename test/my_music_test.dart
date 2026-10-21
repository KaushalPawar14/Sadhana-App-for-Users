import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/MyMusicPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/MusicData.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// MY MUSIC: the curriculum the HODs and Guides set (live), the student's progress by checkpoint id, the expandable cards
// with tick boxes, the Completed badge, the link icon, and "Others".
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

Map<String, Object?> instrument(String name, List<(String, String)> cps, {String link = '', int order = 0}) => {
      'name': name,
      'link': link,
      'order': order,
      'checkpoints': [for (final (id, title) in cps) {'id': id, 'title': title}],
    };

Future<FakeFirebaseFirestore> world() async {
  final db = FakeFirebaseFirestore();
  await db.doc('musicCurriculum/kartal').set(instrument('Kartal', [
    ('k1', 'Hold it properly'),
    ('k2', 'Slow beat'),
    ('k3', 'Fast beat'),
  ], link: 'https://www.youtube.com/watch?v=159NsltEMXQ&list=PLX', order: 0));
  await db.doc('musicCurriculum/harmonium').set(instrument('Harmonium', [('h1', 'Learn the keys'), ('h2', 'Play Sa Re Ga Ma')], order: 1));
  await db.doc('musicCurriculum/womper').set(instrument('Womper', [('w1', 'Learning Womper')], link: 'https://youtu.be/sZAHVmFB8s8', order: 2));
  return db;
}

Future<void> open(WidgetTester tester, FakeFirebaseFirestore db, {double scale = 1.0, bool dark = false, bool reduce = true, List<Uri>? opened, bool linkOk = true}) async {
  phone(tester, scale);
  await tester.pumpWidget(MaterialApp(
    theme: dark ? FolkTheme.dark : FolkTheme.light,
    builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduce), child: w!),
    home: MyMusicPage(
      store: FirestoreMusicStore(db),
      uid: uid,
      openLink: (u) async {
        opened?.add(u);
        return linkOk;
      },
    ),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Finder card(String id) => find.byKey(ValueKey('music-instrument-$id'));
Future<void> expand(WidgetTester tester, String id) async {
  await reveal(tester, find.byKey(ValueKey('music-header-$id')));
  await tester.tap(find.byKey(ValueKey('music-header-$id')));
  await settle(tester);
}

Future<void> tickBox(WidgetTester tester, String cp) async {
  await reveal(tester, find.byKey(ValueKey('music-cp-$cp')));
  await tester.tap(find.byKey(ValueKey('music-cp-$cp')));
  await settle(tester);
}

/// Scrolls the (lazy) list until [f] is built and on screen.
Future<void> reveal(WidgetTester tester, Finder f) async {
  final scrollable = find.descendant(of: find.byKey(const ValueKey('music-list')), matching: find.byType(Scrollable)).first;
  if (f.evaluate().isEmpty) {
    // not built: it is below or above the visible part, try both ways (bounded)
    try {
      await tester.scrollUntilVisible(f, 200, scrollable: scrollable, maxScrolls: 40);
    } catch (_) {
      await tester.scrollUntilVisible(f, -200, scrollable: scrollable, maxScrolls: 40);
    }
  } else {
    await tester.ensureVisible(f);
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // ------------------------------------------------------------------------------------------------ the data
  group('the data: progress is kept by checkpoint id', () {
    const kartal = MusicInstrument(id: 'kartal', name: 'Kartal', checkpoints: [
      MusicCheckpoint(id: 'k1', title: 'A'),
      MusicCheckpoint(id: 'k2', title: 'B'),
      MusicCheckpoint(id: 'k3', title: 'C'),
    ]);
    MusicTick t() => const MusicTick(by: 'student', byName: '');

    test('done counts the ticked checkpoints of the instrument; completed = all of them (and at least one checkpoint)', () {
      expect(MusicProgress.empty.done(kartal), 0);
      expect(MusicProgress(ticks: {'k1': t()}).done(kartal), 1);
      expect(MusicProgress(ticks: {'k1': t(), 'k2': t(), 'k3': t()}).completed(kartal), isTrue);
      expect(MusicProgress(ticks: {'k1': t(), 'k2': t()}).completed(kartal), isFalse);
      expect(MusicProgress.empty.completed(const MusicInstrument(id: 'x', name: 'Empty')), isFalse, reason: 'no checkpoints: not completed');
    });

    test('a rename or a reorder keeps the ticks (the ids are the same); a deleted checkpoint stops counting; a new one un-completes', () {
      final ticks = {'k1': t(), 'k2': t(), 'k3': t()};
      final p = MusicProgress(ticks: ticks);
      final renamedAndReordered = const MusicInstrument(id: 'kartal', name: 'Karatalas', checkpoints: [
        MusicCheckpoint(id: 'k3', title: 'Third, renamed'),
        MusicCheckpoint(id: 'k1', title: 'First'),
        MusicCheckpoint(id: 'k2', title: 'Second'),
      ]);
      expect(p.done(renamedAndReordered), 3);
      expect(p.completed(renamedAndReordered), isTrue);
      final deleted = const MusicInstrument(id: 'kartal', name: 'Kartal', checkpoints: [MusicCheckpoint(id: 'k1', title: 'A'), MusicCheckpoint(id: 'k2', title: 'B')]);
      expect(p.done(deleted), 2, reason: 'the tick of the deleted checkpoint stays in storage but does not count');
      expect(p.completed(deleted), isTrue);
      final added = const MusicInstrument(id: 'kartal', name: 'Kartal', checkpoints: [
        MusicCheckpoint(id: 'k1', title: 'A'), MusicCheckpoint(id: 'k2', title: 'B'), MusicCheckpoint(id: 'k3', title: 'C'), MusicCheckpoint(id: 'k4', title: 'New'),
      ]);
      expect(p.completed(added), isFalse, reason: 'a new checkpoint makes a completed instrument incomplete until it is ticked');
      expect(MusicProgress(ticks: {...ticks, 'k4': t()}).completed(added), isTrue);
    });

    test('an instrument reads from its document (bad checkpoints and nameless instruments are dropped)', () {
      final i = MusicInstrument.fromDoc('x', {
        'name': ' Mridanga ',
        'link': ' https://youtu.be/a ',
        'order': 3,
        'checkpoints': [
          {'id': 'a', 'title': ' One '},
          {'id': '', 'title': 'No id'},
          {'id': 'b', 'title': '  '},
          'junk',
          {'id': 'c', 'title': 'Three'},
        ],
      })!;
      expect(i.name, 'Mridanga');
      expect(i.link, 'https://youtu.be/a');
      expect(i.hasLink, isTrue);
      expect(i.order, 3);
      expect(i.checkpoints.map((c) => '${c.id}:${c.title}'), ['a:One', 'c:Three']);
      expect(MusicInstrument.fromDoc('y', {'name': '  '}), isNull);
      expect(MusicInstrument.fromDoc('y', null), isNull);
      expect(const MusicInstrument(id: 'n', name: 'N').hasLink, isFalse);
    });

    test('progress reads who ticked and when, and the Others list; levels default to Basic', () {
      final at = DateTime(2026, 10, 12, 9);
      final p = MusicProgress.fromDoc({
        'ticks': {
          'k1': {'by': 'student', 'byName': '', 'at': Timestamp.fromDate(at)},
          'k2': {'by': 'G1', 'byName': 'Gopal Das'},
        },
        'others': [
          {'id': 'o1', 'name': ' Flute ', 'level': 'expert'},
          {'id': 'o2', 'name': 'Tabla', 'level': 'weird'},
          {'id': '', 'name': 'No id'},
        ],
      });
      expect(p.ticks['k1']!.byStudent, isTrue);
      expect(p.ticks['k1']!.at, at);
      expect(p.ticks['k2']!.by, 'G1');
      expect(p.ticks['k2']!.byName, 'Gopal Das');
      expect(p.ticks['k2']!.at, isNull);
      expect(p.others.map((o) => '${o.name}:${o.level.label}'), ['Flute:Expert', 'Tabla:Basic']);
      expect(MusicProgress.fromDoc(null).ticks, isEmpty);
      expect(MusicLevel.values.map((l) => l.label), ['Basic', 'Intermediate', 'Expert']);
    });

    test('new ids are unique and carry their prefix', () {
      final ids = {for (var i = 0; i < 50; i++) newMusicId('o')};
      expect(ids.length, 50);
      expect(ids.every((i) => i.startsWith('o-')), isTrue);
    });
  });

  group('the Firestore store', () {
    test('the curriculum comes in the HODs\' order, live: a rename, a reorder and a new instrument arrive without a reload', () async {
      final db = await world();
      final store = FirestoreMusicStore(db);
      final seen = <List<String>>[];
      final sub = store.curriculum().listen((l) => seen.add([for (final i in l) i.name]));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ['Kartal', 'Harmonium', 'Womper']);
      await db.doc('musicCurriculum/kartal').update({'name': 'Karatalas', 'order': 5});
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ['Harmonium', 'Womper', 'Karatalas']);
      await db.doc('musicCurriculum/flute').set(instrument('Flute', [('f1', 'Hold it')], order: 1));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ['Flute', 'Harmonium', 'Womper', 'Karatalas'], reason: 'the same order: by name');
      await db.doc('musicCurriculum/womper').delete();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ['Flute', 'Harmonium', 'Karatalas']);
      await sub.cancel();
    });

    test('ticking writes the checkpoint id with who and when; unticking removes only that one; others are kept', () async {
      final db = await world();
      final store = FirestoreMusicStore(db);
      await store.setTick(uid, 'k1', true, by: 'student', byName: '');
      await store.setTick(uid, 'k2', true, by: 'G1', byName: 'Gopal Das');
      var doc = (await db.doc('musicProgress/$uid').get()).data()!;
      expect(doc['uid'], uid);
      expect((doc['ticks'] as Map).keys, {'k1', 'k2'});
      expect((doc['ticks']['k2'] as Map)['by'], 'G1');
      expect((doc['ticks']['k2'] as Map)['byName'], 'Gopal Das');
      expect((doc['ticks']['k1'] as Map)['at'], isNotNull);
      await store.saveOthers(uid, [const OtherInstrument(id: 'o1', name: 'Flute', level: MusicLevel.expert)]);
      await store.setTick(uid, 'k1', false, by: 'student', byName: '');
      doc = (await db.doc('musicProgress/$uid').get()).data()!;
      expect((doc['ticks'] as Map).keys, {'k2'}, reason: 'only k1 was removed');
      expect((doc['others'] as List).length, 1, reason: 'the Others are untouched by ticks');
      // unticking when nothing exists yet is a quiet no-op
      await store.setTick('nobody', 'k1', false, by: 'student', byName: '');
    });

    test('Others are replaced as a whole; the live progress follows', () async {
      final db = await world();
      final store = FirestoreMusicStore(db);
      final seen = <MusicProgress>[];
      final sub = store.progress(uid).listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.ticks, isEmpty);
      await store.setTick(uid, 'k1', true, by: 'student', byName: '');
      await store.saveOthers(uid, [const OtherInstrument(id: 'o1', name: 'Flute', level: MusicLevel.basic), const OtherInstrument(id: 'o2', name: 'Tabla', level: MusicLevel.intermediate)]);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.ticks.keys, ['k1']);
      expect(seen.last.others.map((o) => o.name), ['Flute', 'Tabla']);
      await store.saveOthers(uid, [const OtherInstrument(id: 'o2', name: 'Tabla', level: MusicLevel.expert)]);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.others.map((o) => '${o.name}:${o.level.label}'), ['Tabla:Expert']);
      await sub.cancel();
    });
  });

  // ------------------------------------------------------------------------------------------------ the page
  group('the page', () {
    testWidgets('the instruments in the HODs\' order, each with "0 of N" and its progress bar; collapsed to start with', (tester) async {
      await open(tester, await world());
      expect(find.text('My Music'), findsOneWidget);
      final order = ['kartal', 'harmonium', 'womper'].map((i) => tester.getTopLeft(card(i)).dy).toList();
      expect(order, [...order]..sort());
      expect(find.text('Kartal'), findsOneWidget);
      expect(find.byKey(const ValueKey('music-count-kartal')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-count-kartal'))).data, '0 of 3');
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-count-harmonium'))).data, '0 of 2');
      expect(find.byKey(const ValueKey('music-cp-k1')), findsNothing, reason: 'collapsed');
      expect(find.byKey(const ValueKey('music-bar-kartal')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card opens and closes; the checkpoints are tick boxes in the HODs\' order', (tester) async {
      await open(tester, await world());
      await expand(tester, 'kartal');
      final tops = ['k1', 'k2', 'k3'].map((c) => tester.getTopLeft(find.byKey(ValueKey('music-cp-$c'))).dy).toList();
      expect(tops, [...tops]..sort());
      expect(find.text('Hold it properly'), findsOneWidget);
      expect(find.text('Fast beat'), findsOneWidget);
      await expand(tester, 'kartal');
      expect(find.byKey(const ValueKey('music-cp-k1')), findsNothing);
    });

    testWidgets('ticking writes the tick (by the student) and the count, bar and box follow; unticking takes it away', (tester) async {
      final db = await world();
      await open(tester, db);
      await expand(tester, 'kartal');
      await tickBox(tester, 'k1');
      await tickBox(tester, 'k2');
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-count-kartal'))).data, '2 of 3');
      final doc = (await db.doc('musicProgress/$uid').get()).data()!;
      expect((doc['ticks'] as Map).keys, {'k1', 'k2'});
      expect((doc['ticks']['k1'] as Map)['by'], 'student');
      final fill = tester.getSize(find.descendant(of: card('kartal'), matching: find.byKey(const ValueKey('music-bar-fill')))).width;
      final track = tester.getSize(find.byKey(const ValueKey('music-bar-kartal'))).width;
      expect(fill / track, closeTo(2 / 3, .03), reason: 'the bar shows 2 of 3');
      expect(find.byKey(const ValueKey('music-by-k1')), findsOneWidget, reason: 'who ticked, subtly');
      await tickBox(tester, 'k2');
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-count-kartal'))).data, '1 of 3');
      expect(((await db.doc('musicProgress/$uid').get()).data()!['ticks'] as Map).keys, {'k1'});
      expect(find.byKey(const ValueKey('music-by-k2')), findsNothing);
    });

    testWidgets('Completed appears when every checkpoint is ticked and goes when one is unticked', (tester) async {
      await open(tester, await world());
      await expand(tester, 'harmonium');
      expect(find.byKey(const ValueKey('music-completed')), findsNothing);
      await tickBox(tester, 'h1');
      expect(find.byKey(const ValueKey('music-completed')), findsNothing);
      await tickBox(tester, 'h2');
      expect(find.byKey(const ValueKey('music-completed')), findsOneWidget);
      expect(find.descendant(of: card('harmonium'), matching: find.text('Completed')), findsOneWidget);
      expect(find.descendant(of: card('kartal'), matching: find.byKey(const ValueKey('music-completed'))), findsNothing, reason: 'only on the finished instrument');
      await tickBox(tester, 'h1');
      expect(find.byKey(const ValueKey('music-completed')), findsNothing);
    });

    testWidgets('HOD edits arrive live: a rename and a reorder keep the ticks; a new checkpoint un-completes; a deleted one stops counting', (tester) async {
      final db = await world();
      await db.doc('musicProgress/$uid').set({
        'uid': uid,
        'ticks': {
          'h1': {'by': 'student', 'byName': ''},
          'h2': {'by': 'G1', 'byName': 'Gopal Das'},
        },
      });
      await open(tester, db);
      expect(find.byKey(const ValueKey('music-completed')), findsOneWidget, reason: 'Harmonium is complete');
      // the HOD renames the instrument and reorders / renames its checkpoints
      await db.doc('musicCurriculum/harmonium').update({
        'name': 'Harmonium (keys)',
        'checkpoints': [
          {'id': 'h2', 'title': 'Sa Re Ga Ma'},
          {'id': 'h1', 'title': 'The keys'},
        ],
      });
      await settle(tester);
      expect(find.text('Harmonium (keys)'), findsOneWidget);
      expect(find.byKey(const ValueKey('music-completed')), findsOneWidget, reason: 'the ticks follow the ids');
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-count-harmonium'))).data, '2 of 2');
      // a new checkpoint
      await db.doc('musicCurriculum/harmonium').update({
        'checkpoints': [
          {'id': 'h2', 'title': 'Sa Re Ga Ma'},
          {'id': 'h1', 'title': 'The keys'},
          {'id': 'h3', 'title': 'Know scales'},
        ],
      });
      await settle(tester);
      expect(find.byKey(const ValueKey('music-completed')), findsNothing, reason: 'incomplete again until the new one is ticked');
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-count-harmonium'))).data, '2 of 3');
      // the HOD deletes the new checkpoint again: complete again
      await db.doc('musicCurriculum/harmonium').update({
        'checkpoints': [
          {'id': 'h2', 'title': 'Sa Re Ga Ma'},
          {'id': 'h1', 'title': 'The keys'},
        ],
      });
      await settle(tester);
      expect(find.byKey(const ValueKey('music-completed')), findsOneWidget);
      // the HOD deletes the instrument: it disappears for the student (their ticks stay in storage)
      await db.doc('musicCurriculum/harmonium').delete();
      await settle(tester);
      expect(find.byKey(const ValueKey('music-instrument-harmonium')), findsNothing);
      expect(((await db.doc('musicProgress/$uid').get()).data()!['ticks'] as Map).keys, {'h1', 'h2'});
    });

    testWidgets('who ticked and when is shown subtly: "You · 12 Oct" for the student, the admin\'s name for a guide', (tester) async {
      final db = await world();
      await db.doc('musicProgress/$uid').set({
        'uid': uid,
        'ticks': {
          'k1': {'by': 'student', 'byName': '', 'at': Timestamp.fromDate(DateTime(2026, 10, 12, 9))},
          'k2': {'by': 'G1', 'byName': 'Gopal Das', 'at': Timestamp.fromDate(DateTime(2026, 10, 14, 18))},
        },
      });
      await open(tester, db);
      await expand(tester, 'kartal');
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-by-k1'))).data, 'You · 12 Oct');
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-by-k2'))).data, 'Gopal Das · 14 Oct');
      expect(find.byKey(const ValueKey('music-by-k3')), findsNothing);
    });

    testWidgets('a small link icon (no visible URL) only when the instrument has a link; tapping opens it', (tester) async {
      final opened = <Uri>[];
      await open(tester, await world(), opened: opened);
      expect(find.byKey(const ValueKey('music-link-kartal')), findsOneWidget);
      expect(find.byKey(const ValueKey('music-link-womper')), findsOneWidget);
      expect(find.byKey(const ValueKey('music-link-harmonium')), findsNothing, reason: 'no link, no icon');
      expect(find.textContaining('youtube'), findsNothing, reason: 'the URL is never shown');
      expect(find.textContaining('youtu.be'), findsNothing);
      expect(find.textContaining('http'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('music-link-kartal')));
      await settle(tester);
      expect(opened.single.toString(), 'https://www.youtube.com/watch?v=159NsltEMXQ&list=PLX');
      expect(find.byKey(const ValueKey('music-cp-k1')), findsNothing, reason: 'the link icon does not also open the card');
    });

    testWidgets('a link that cannot be opened says so, nothing else changes', (tester) async {
      await open(tester, await world(), linkOk: false);
      await tester.tap(find.byKey(const ValueKey('music-link-kartal')));
      await settle(tester);
      expect(find.text("Couldn't open the link."), findsOneWidget);
    });

    testWidgets('no instruments yet: a plain message; Others is still there', (tester) async {
      await open(tester, FakeFirebaseFirestore());
      expect(find.byKey(const ValueKey('music-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('music-add-other')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ Others
  group('Others: the student\'s own instruments', () {
    Future<void> addOther(WidgetTester tester, String name, {String? level}) async {
      await reveal(tester, find.byKey(const ValueKey('music-add-other')));
      await tester.tap(find.byKey(const ValueKey('music-add-other')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('music-other-name')), name);
      if (level != null) {
        await tester.tap(find.descendant(of: find.byKey(const ValueKey('music-other-level')), matching: find.text(level)));
        await settle(tester);
      }
      await tester.tap(find.byKey(const ValueKey('music-other-save')));
      await settle(tester);
    }

    Future<List<dynamic>> stored(FakeFirebaseFirestore db) async => ((await db.doc('musicProgress/$uid').get()).data()?['others'] as List?) ?? [];

    testWidgets('add one: name + level (Basic / Intermediate / Expert); it is listed and stored', (tester) async {
      final db = await world();
      await open(tester, db);
      expect(find.byKey(const ValueKey('music-others-empty')), findsOneWidget);
      await addOther(tester, '  Flute ', level: 'Expert');
      expect(find.text('Flute'), findsOneWidget);
      final saved = await stored(db);
      expect(saved.length, 1);
      expect(saved.first['name'], 'Flute');
      expect(saved.first['level'], 'expert');
      expect((saved.first['id'] as String).startsWith('o-'), isTrue, reason: 'a stable id');
      await addOther(tester, 'Tabla');
      expect((await stored(db)).length, 2);
      expect((await stored(db)).last['level'], 'basic', reason: 'Basic is the default level');
      expect(find.byKey(const ValueKey('music-others-empty')), findsNothing);
    });

    testWidgets('a name is required', (tester) async {
      final db = await world();
      await open(tester, db);
      await reveal(tester, find.byKey(const ValueKey('music-add-other')));
      await tester.tap(find.byKey(const ValueKey('music-add-other')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('music-other-save')));
      await settle(tester);
      expect(find.text('Please write the instrument'), findsOneWidget);
      expect(find.byKey(const ValueKey('music-other-dialog')), findsOneWidget, reason: 'the dialog stays');
      expect(await stored(db), isEmpty);
      await tester.tap(find.byKey(const ValueKey('music-other-cancel')));
      await settle(tester);
      expect(find.byKey(const ValueKey('music-other-dialog')), findsNothing);
      expect(await stored(db), isEmpty);
    });

    testWidgets('edit one (name and level) and remove one (with a confirmation); the id stays the same', (tester) async {
      final db = await world();
      await db.doc('musicProgress/$uid').set({
        'uid': uid,
        'others': [
          {'id': 'o1', 'name': 'Flute', 'level': 'basic'},
          {'id': 'o2', 'name': 'Tabla', 'level': 'intermediate'},
        ],
      });
      await open(tester, db);
      expect(tester.widget<Text>(find.byKey(const ValueKey('music-other-level-o2'))).data, 'Intermediate');
      await reveal(tester, find.byKey(const ValueKey('music-edit-o1')));
      await tester.tap(find.byKey(const ValueKey('music-edit-o1')));
      await settle(tester);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('music-other-name'))).controller!.text, 'Flute', reason: 'prefilled');
      await tester.enterText(find.byKey(const ValueKey('music-other-name')), 'Bamboo flute');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('music-other-level')), matching: find.text('Expert')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('music-other-save')));
      await settle(tester);
      var saved = await stored(db);
      expect(saved.first['id'], 'o1');
      expect(saved.first['name'], 'Bamboo flute');
      expect(saved.first['level'], 'expert');
      // remove: asks first
      await reveal(tester, find.byKey(const ValueKey('music-delete-o2')));
      await tester.tap(find.byKey(const ValueKey('music-delete-o2')));
      await settle(tester);
      expect(find.text('Remove Tabla?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect((await stored(db)).length, 2, reason: 'Cancel keeps it');
      await tester.tap(find.byKey(const ValueKey('music-delete-o2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('music-remove-confirm')));
      await settle(tester);
      saved = await stored(db);
      expect(saved.map((o) => o['id']), ['o1']);
      expect(find.text('Tabla'), findsNothing);
    });

    testWidgets('Others never touches the ticks', (tester) async {
      final db = await world();
      await db.doc('musicProgress/$uid').set({'uid': uid, 'ticks': {'k1': {'by': 'student', 'byName': ''}}});
      await open(tester, db);
      await addOther(tester, 'Flute');
      expect((((await db.doc('musicProgress/$uid').get()).data()!)['ticks'] as Map).keys, {'k1'});
    });
  });

  // ------------------------------------------------------------------------------------------------ look
  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('${dark ? 'dark' : 'light'}, text $scale: every card open, a completed one, Others: fits, no overflow, targets >= 48 dp', (tester) async {
        final db = await world();
        await db.doc('musicProgress/$uid').set({
          'uid': uid,
          'ticks': {
            'h1': {'by': 'student', 'byName': '', 'at': Timestamp.fromDate(DateTime(2026, 10, 12))},
            'h2': {'by': 'G1', 'byName': 'Gopal Das Brahmachari', 'at': Timestamp.fromDate(DateTime(2026, 10, 13))},
            'k1': {'by': 'student', 'byName': ''},
          },
          'others': [
            {'id': 'o1', 'name': 'A very long instrument name that has to wrap onto several lines nicely', 'level': 'intermediate'},
          ],
        });
        await open(tester, db, scale: scale, dark: dark);
        for (final i in ['kartal', 'harmonium', 'womper']) {
          await expand(tester, i);
        }
        expect(tester.takeException(), isNull);
        final width = 360.0;
        for (final key in ['music-header-kartal', 'music-cp-k1', 'music-cp-h2', 'music-link-kartal', 'music-edit-o1', 'music-delete-o1', 'music-add-other']) {
          final f = find.byKey(ValueKey(key));
          await reveal(tester, f);
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(0), reason: key);
          expect(r.right, lessThanOrEqualTo(width + .5), reason: key);
          expect(r.height, greaterThanOrEqualTo(FolkShape.touchTarget - .5), reason: '$key: a comfortable target');
        }
        expect(find.byKey(const ValueKey('music-completed')), findsOneWidget);
        await reveal(tester, find.byKey(const ValueKey('music-other-o1')));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('with animations on, the card opens smoothly and the bar fills (no exception, ends in place)', (tester) async {
    final db = await world();
    await open(tester, db, reduce: false);
    await tester.tap(find.byKey(const ValueKey('music-header-kartal')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(const ValueKey('music-cp-k1')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('wiring: Profile -> My Music opens the page; the "Coming soon" text is gone', () {
    final src = File('lib/pages/Profile.dart').readAsStringSync();
    expect(src, contains('MyMusicPage()'));
    expect(src.contains('Coming soon'), isFalse);
    expect(File('lib/pages/MyMusicPage.dart').readAsStringSync().contains('Coming soon'), isFalse);
    expect(File('lib/pages/MyMusicPage.dart').readAsStringSync().contains('LayoutBuilder'), isFalse);
  });
}
