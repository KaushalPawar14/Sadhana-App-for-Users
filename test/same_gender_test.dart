import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/models/CompetitionResults.dart';
import 'package:folk_app/scores/BhagavatamClass.dart';
import 'package:folk_app/scores/BookReading.dart';
import 'package:folk_app/scores/Chanting.dart';
import 'package:folk_app/scores/DailyServices.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/ResidenceRule.dart';
import 'package:folk_app/utils/SameGender.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// A student sees ONLY students of their own gender. No gender = male.
//
// Cast (names are what the leaderboards key by, uids what friends key by):
//   males:   Arjun, Bhima, Chaitanya  (Chaitanya has NO gender field)
//   females: Asha, Bhavani, Charu
GenderDirectory directoryFor(String mine) => GenderDirectory(
      mine: mine,
      femaleNames: {'Asha', 'Bhavani', 'Charu'},
      femaleUids: {'uA', 'uB', 'uC'},
    );

final scorecard = <String, Map<String, dynamic>>{
  'flag': {'x': 1},
  'Arjun': {'totalChantRounds': 90, 'totalBookRead': 10, 'totalSBClass': 8, 'totalServiceDone': 5},
  'Asha': {'totalChantRounds': 100, 'totalBookRead': 20, 'totalSBClass': 9, 'totalServiceDone': 6},
  'Bhima': {'totalChantRounds': 80, 'totalBookRead': 30, 'totalSBClass': 7, 'totalServiceDone': 4},
  'Bhavani': {'totalChantRounds': 70, 'totalBookRead': 5, 'totalSBClass': 6, 'totalServiceDone': 3},
  'Chaitanya': {'totalChantRounds': 60, 'totalBookRead': 1, 'totalSBClass': 5, 'totalServiceDone': 2},
  'Charu': {'totalChantRounds': 50, 'totalBookRead': 2, 'totalSBClass': 4, 'totalServiceDone': 1},
};

const males = ['Arjun', 'Bhima', 'Chaitanya'];
const females = ['Asha', 'Bhavani', 'Charu'];

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

Future<Map<String, Map<String, dynamic>>> reader() async => scorecard;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  tearDown(() => GenderDirectory.useForTests(null));

  group('who counts as male / female', () {
    test('no gender field, and anything that is not "female", is male', () {
      expect(genderOfData(null), kMale);
      expect(genderOfData({}), kMale);
      expect(genderOfData({'name': 'x'}), kMale);
      expect(genderOfData({'gender': 'male'}), kMale);
      expect(genderOfData({'gender': ''}), kMale);
      expect(genderOfData({'gender': 'Female'}), kMale, reason: 'only the stored "female" counts');
      expect(genderOfData({'gender': 'female'}), kFemale);
    });

    test('a male sees males (and unknown names); a female sees only known females', () {
      final m = directoryFor(kMale);
      for (final n in males) {
        expect(m.sameByName(n), isTrue, reason: n);
      }
      for (final n in females) {
        expect(m.sameByName(n), isFalse, reason: n);
      }
      expect(m.sameByName('Nobody Known'), isTrue, reason: 'no gender on record = male');
      final f = directoryFor(kFemale);
      for (final n in females) {
        expect(f.sameByName(n), isTrue, reason: n);
      }
      for (final n in males) {
        expect(f.sameByName(n), isFalse, reason: n);
      }
      expect(f.sameByName('Nobody Known'), isFalse);
      expect(f.sameByName(null), isFalse);
      expect(m.sameByUid('uA'), isFalse);
      expect(m.sameByUid('uX'), isTrue);
      expect(f.sameByUid('uA'), isTrue);
      expect(f.sameByUid('uX'), isFalse);
      // a users document is compared by its own gender field
      expect(m.sameByData({'gender': 'female'}), isFalse);
      expect(m.sameByData({'name': 'no gender'}), isTrue);
      expect(f.sameByData({'gender': 'female'}), isTrue);
      expect(f.sameByData({'name': 'no gender'}), isFalse);
    });
  });

  // ------------------------------------------------------------ leaderboards
  final boards = <String, (Widget Function() build, String title)>{
    'Chanting': (() => Chanting(scorecardReader: reader), 'Chanting Leaderboard'),
    'Book Reading': (() => BookReading(scorecardReader: reader), 'Book Reading Leaderboard'),
    'SB class': (() => SBclasses(scorecardReader: reader), 'SB Watch Leaderboard'),
    'Daily services': (() => DailyServices(scorecardReader: reader), 'Daily Services Leaderboard'),
  };

  for (final board in boards.entries) {
    for (final viewer in [kMale, kFemale]) {
      testWidgets('${board.key} leaderboard: a $viewer sees only ${viewer == kMale ? 'males' : 'females'}', (tester) async {
        phone(tester, 1.0);
        GenderDirectory.useForTests(() async => directoryFor(viewer));
        await tester.pumpWidget(host(board.value.$1()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final mine = viewer == kMale ? males : females;
        final others = viewer == kMale ? females : males;
        for (final n in mine) {
          expect(find.text(n), findsOneWidget, reason: '$n should be listed');
        }
        for (final n in others) {
          expect(find.text(n), findsNothing, reason: '$n must not be listed');
        }
        expect(find.text('flag'), findsNothing);
      });
    }
  }

  testWidgets('ranks are recomputed among the same gender: a female who is 2nd overall is 1st; rows start at 1 with no gaps', (tester) async {
    phone(tester, 1.0);
    // SB class has plain rank rows: Asha(9) Arjun(8) Bhima(7) Bhavani(6) Chaitanya(5) Charu(4)
    GenderDirectory.useForTests(() async => directoryFor(kFemale));
    await tester.pumpWidget(host(SBclasses(scorecardReader: reader)));
    await tester.pumpAndSettle();
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
    expect(texts.indexOf('Asha'), lessThan(texts.indexOf('Bhavani')));
    expect(texts.indexOf('Bhavani'), lessThan(texts.indexOf('Charu')));
    // the rank numbers shown are 1, 2, 3 (not 1, 4, 6 as overall places)
    expect(find.text('1'), findsWidgets);
    expect(find.text('4'), findsNothing);
    expect(find.text('6'), findsNothing);
  });

  testWidgets('a male reader with a non-gender user (Chaitanya) sees him as male', (tester) async {
    phone(tester, 1.0);
    GenderDirectory.useForTests(() async => directoryFor(kMale));
    await tester.pumpWidget(host(SBclasses(scorecardReader: reader)));
    await tester.pumpAndSettle();
    expect(find.text('Chaitanya'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('leaderboards draw without overflow — ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
        phone(tester, scale);
        for (final viewer in [kMale, kFemale]) {
          GenderDirectory.useForTests(() async => directoryFor(viewer));
          for (final b in boards.values) {
            await tester.pumpWidget(host(b.$1(), dark: dark));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }

  // ------------------------------------------------------------ ranks
  group('"Your position" among the same gender only', () {
    final entries = [
      (name: 'Asha', score: 100.0),
      (name: 'Arjun', score: 90.0),
      (name: 'Bhima', score: 80.0),
      (name: 'Bhavani', score: 70.0),
      (name: 'Chaitanya', score: 60.0),
      (name: 'Charu', score: 50.0),
    ];

    test('a male: Arjun is 1st of 3 (not 2nd of 6); Chaitanya 3rd of 3', () {
      final m = directoryFor(kMale);
      expect(positionAmongSameGender(m, entries, 'Arjun'), (rank: 1, outOf: 3));
      expect(positionAmongSameGender(m, entries, 'Bhima'), (rank: 2, outOf: 3));
      expect(positionAmongSameGender(m, entries, 'Chaitanya'), (rank: 3, outOf: 3));
    });

    test('a female: Asha 1st of 3, Bhavani 2nd of 3 (not 4th of 6), Charu 3rd of 3', () {
      final f = directoryFor(kFemale);
      expect(positionAmongSameGender(f, entries, 'Asha'), (rank: 1, outOf: 3));
      expect(positionAmongSameGender(f, entries, 'Bhavani'), (rank: 2, outOf: 3));
      expect(positionAmongSameGender(f, entries, 'Charu'), (rank: 3, outOf: 3));
    });

    test('a student not among them gets rank 0; scores are not mixed between genders', () {
      expect(positionAmongSameGender(directoryFor(kMale), entries, 'Asha'), (rank: 0, outOf: 3));
      expect(positionAmongSameGender(directoryFor(kFemale), const [], 'Asha'), (rank: 0, outOf: 0));
    });
  });

  // ------------------------------------------------------------ winners
  group('winners and podiums among the same gender', () {
    UserCompetitionResult r(String n, double score) => UserCompetitionResult(
          name: n, totalScore: score, bhagavatam: 0, dailyService: 0, chantingRounds: 0, bookReading: 0,
          extraLecture: 0, templeMultiplier: 1, japaMultiplier: 1, sleepingMultiplier: 1,
        );
    final all = [r('Asha', 100), r('Arjun', 90), r('Bhima', 80), r('Bhavani', 70), r('Chaitanya', 60), r('Charu', 50), r('Dev', 40)];

    test('topByGender: the best three of EACH gender', () {
      final by = topByGender<UserCompetitionResult>(all, nameOf: (u) => u.name, scoreOf: (u) => u.totalScore, femaleNames: {'Asha', 'Bhavani', 'Charu'});
      expect(by[kMale]!.map((u) => u.name), ['Arjun', 'Bhima', 'Chaitanya']);
      expect(by[kFemale]!.map((u) => u.name), ['Asha', 'Bhavani', 'Charu']);
    });

    test('badges: the weekly winner and the monthly gold / silver / bronze go to each gender\'s own top', () {
      final by = topByGender<UserCompetitionResult>(all, nameOf: (u) => u.name, scoreOf: (u) => u.totalScore, femaleNames: {'Asha', 'Bhavani', 'Charu'});
      expect(weeklyWinnerNames(by).toSet(), {'Arjun', 'Asha'});
      final awards = monthlyBadgeAwards(by);
      expect({for (final a in awards) a.name: a.field}, {
        'Arjun': 'monthly-gold', 'Bhima': 'monthly-silver', 'Chaitanya': 'monthly-bronze',
        'Asha': 'monthly-gold', 'Bhavani': 'monthly-silver', 'Charu': 'monthly-bronze',
      });
      // a gender whose best scored nothing gets no badge at all
      final quiet = topByGender<UserCompetitionResult>([r('Arjun', 5), r('Asha', 0)], nameOf: (u) => u.name, scoreOf: (u) => u.totalScore, femaleNames: {'Asha'});
      expect(weeklyWinnerNames(quiet), ['Arjun']);
      expect(monthlyBadgeAwards(quiet).map((a) => a.name), ['Arjun']);
    });

    test('winnersForMe: the list kept for my gender; an older document (only topUsers) is filtered to my gender', () {
      final doc = {
        'topUsers': [r('Asha', 100).toMap(), r('Arjun', 90).toMap(), r('Bhima', 80).toMap()],
        'topUsersMale': [r('Arjun', 90).toMap(), r('Bhima', 80).toMap(), r('Chaitanya', 60).toMap()],
        'topUsersFemale': [r('Asha', 100).toMap(), r('Bhavani', 70).toMap()],
      };
      expect(winnersForMe(doc, directoryFor(kMale)).map((u) => u['name']), ['Arjun', 'Bhima', 'Chaitanya']);
      expect(winnersForMe(doc, directoryFor(kFemale)).map((u) => u['name']), ['Asha', 'Bhavani']);
      final old = {'topUsers': doc['topUsers']};
      expect(winnersForMe(old, directoryFor(kMale)).map((u) => u['name']), ['Arjun', 'Bhima']);
      expect(winnersForMe(old, directoryFor(kFemale)).map((u) => u['name']), ['Asha']);
      expect(winnersForMe(null, directoryFor(kMale)), isEmpty);
      expect(winnersForMe({}, directoryFor(kFemale)), isEmpty);
    });

    test('the results documents carry the per-gender lists as ADDITIVE fields', () {
      final w = WeeklyResults(
          weekId: '2026-W41', topUsers: [r('Asha', 1)], generatedAt: DateTime(2026), topUsersMale: [r('Arjun', 1)], topUsersFemale: [r('Asha', 1)]);
      expect(w.toMap().keys, containsAll(['topUsers', 'topUsersMale', 'topUsersFemale', 'generatedAt']));
      final legacy = WeeklyResults(weekId: 'x', topUsers: [], generatedAt: DateTime(2026));
      expect(legacy.toMap().keys.toSet(), {'topUsers', 'generatedAt'});
    });
  });

  // ------------------------------------------------------------ RDUA friends + the rest (source)
  group('every other place filters by gender (source-level proof)', () {
    String read(String f) => File(f).readAsStringSync();

    test('RDUA Friends: search, send, accept, requests, friends, groups', () {
      final src = read('lib/pages/RduaFriendsScreen.dart');
      // search finds only my gender
      expect(src, contains('StudentApi.instance.searchStudents(trimmed)'), reason: 'the server returns only my gender');
      // a request cannot be SENT to the other gender (re-read at the moment of sending)
      final send = src.substring(src.indexOf('Future<void> _sendFriendRequest('));
      expect(send.indexOf('directory.sameByUid(toUid)'), lessThan(send.indexOf("add({")), reason: 'checked before the request is written');
      // …or ACCEPTED
      final accept = src.substring(src.indexOf('Future<void> _respondToRequest('));
      expect(accept, contains('StudentApi.instance.acceptFriendRequest(requestId)'), reason: 'the server checks the gender and writes both lists');
      expect(accept.contains('batch.commit()'), isFalse, reason: 'no client batch writing another student list');
      // incoming requests, friends, group members: same gender only
      expect(src, contains("_directory?.sameByUid(d.data()['fromUid']?.toString())"));
      expect(src, contains('final docs = _sameGender(snap.data?.docs ?? []);'));
      expect(src, contains('_sameGender(friendsSnap.docs)'));
      expect(src, contains('.where((m) => _directory?.sameByUid(m) ?? false)'));
    });

    test('RDUA friend rule: opposite genders never pair', () {
      final m = directoryFor(kMale);
      final f = directoryFor(kFemale);
      expect(m.sameByData({'gender': 'female'}), isFalse, reason: 'a boy cannot find or add a girl');
      expect(f.sameByData({'gender': 'male'}), isFalse);
      expect(f.sameByData({}), isFalse, reason: 'no gender = male: a girl cannot add them');
      expect(genderOfData({'gender': 'female'}) != genderOfData({}), isTrue);
    });

    test('the Chanting Competition contributors / winners', () {
      // (the voice-room screen has no way in from the app, and its file was deleted)
      expect(File('lib/pages/VoiceRoomScreen.dart').existsSync(), isFalse);
      final cc = read('lib/pages/ChantingCompetition.dart');
      expect(cc, contains("_directory?.sameByName(data['studentName']?.toString())"));
      expect(cc, contains("directory.sameByName(d['studentName']?.toString())"));
    });

    test('Weekly / Monthly results: the position is among the same gender', () {
      for (final f in ['lib/scores/WeeklyResults.dart', 'lib/scores/MonthlyResults.dart']) {
        final src = read(f);
        expect(src, contains('positionAmongSameGender('), reason: f);
        expect(src, contains('GenderDirectory.forCurrentUser()'), reason: f);
        expect(src.contains('users.indexWhere'), isFalse, reason: '$f no longer ranks everyone together');
      }
      for (final f in ['lib/scores/TopWeekResults.dart', 'lib/scores/TopMonthResults.dart']) {
        expect(read(f), contains('readMyGenderList('), reason: f);
        expect(read(f).contains("'byGender'") || read('lib/utils/SameGender.dart').contains("'byGender'"), isTrue, reason: f);
      }
      // Finalisation moved to the server (functions/competitionFinalize.js).
      final svc = read('lib/models/CompetitionResults.dart');
      expect(svc.contains('CompetitionResultService'), isFalse);
      expect(svc.contains('checkAndRunWeeklyLazyTrigger'), isFalse);
      expect(read('lib/main.dart').contains('LazyTrigger'), isFalse);
    });

    test('no collection is added and nothing is deleted by this feature', () {
      final util = read('lib/utils/SameGender.dart');
      expect(util.contains('.delete('), isFalse);
      expect(util.contains('.set('), isFalse);
      expect(util.contains('.update('), isFalse);
      expect(RegExp(r"collection\('([a-zA-Z-]+)'\)").allMatches(util).map((m) => m.group(1)).toSet(), {'scorecard', 'byCategory', 'byGender'}, reason: 'the directory comes from the server now; results are read from the byCategory (or, for FOLK, the older byGender) document of the student own category and gender');
    });
  });

  // ------------------------------------------------------------ registration
  group('registration: a girl cannot choose "Stay at FOLK"', () {
    test('the choices: a girl is offered Hostel and Localite only; a boy (or no choice yet) all three', () {
      expect(residenceChoices('female'), ['Stay at Hostel', 'Stay at Localite']);
      expect(residenceChoices('male'), ['Stay at FOLK', 'Stay at Hostel', 'Stay at Localite']);
      expect(residenceChoices(null), ['Stay at FOLK', 'Stay at Hostel', 'Stay at Localite']);
      expect(kFolkBoysOnlyNote, 'Stay at FOLK is available for boys only.');
      expect(kContactGuideToRegister, 'Please contact your guide to complete registration.');
    });

    test('female + Stay at FOLK is forbidden, whoever chose it; every other pairing is allowed', () {
      expect(folkForbidden('female', 'Stay at FOLK'), isTrue);
      expect(folkForbidden('female', 'Stay at Hostel'), isFalse);
      expect(folkForbidden('female', 'Stay at Localite'), isFalse);
      expect(folkForbidden('female', null), isFalse);
      expect(folkForbidden('male', 'Stay at FOLK'), isFalse);
      expect(folkForbidden(null, 'Stay at FOLK'), isFalse);
    });

    test('CompleteProfilePage: the dropdown follows the gender, the note shows, FOLK is reset on Female, and the guard runs BEFORE the write', () {
      final src = read('lib/pages/CompleteProfile.dart');
      expect(src, contains('in residenceChoices(selectedGender)'));
      expect(src, contains("if (selectedGender == 'female')"));
      expect(src, contains('Text(kFolkBoysOnlyNote'));
      // choosing Female drops an earlier "Stay at FOLK"; choosing Male brings the option back
      expect(src, contains('if (folkForbidden(selectedGender,'));
      // the guard: before isSubmitting, before the set()
      final submit = src.substring(src.indexOf('Future<void> _submitForm() async {'));
      final guard = submit.indexOf('if (folkForbidden(selectedGender, residenceToWrite))');
      expect(guard, greaterThan(0));
      expect(guard, lessThan(submit.indexOf('isSubmitting = true')));
      expect(guard, lessThan(submit.indexOf(".set({")));
      // a matched guide entry that says FOLK for a girl is refused with the guide message
      expect(submit, contains('isMatched ? kContactGuideToRegister : kFolkBoysOnlyNote'));
      expect(submit.substring(guard, guard + 400), contains('return;'));
    });

    test('everything else in the profile write is as it was', () {
      final src = read('lib/pages/CompleteProfile.dart');
      for (final line in [
        "if (!nameAlreadySaved) 'name': nameController.text,",
        "if (!genderAlreadySaved) 'gender': selectedGender,",
        "if (!mobileAlreadySaved) 'mobileNumber': mobileController.text,",
        "'role': roleToWrite,",
        "if (dob != null) 'dob': Timestamp.fromDate(dob!),",
        "'uid': currentUser.uid,",
        '}, SetOptions(merge: true));',
      ]) {
        expect(src, contains(line), reason: line);
      }
    });
  });
}

String read(String f) => File(f).readAsStringSync();
