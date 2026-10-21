import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/DayScore.dart';
import 'package:folk_app/utils/ReadingSessionStore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// THE READING TIMER NEVER TOUCHES A SADHANA REPORT. Reports, points, leaderboards, best stats and the AI insights use only
// what the student types in the form. The timer records the Books -> History reading log (and its own totals) and nothing
// else. (A trace found a typed 65 minutes becoming 88 because the timer added its minutes on top.)

const _reportPath = 'hostel-sadhana/Testing/dates/20-10-2026';
const _typed = {'bookReading': 65, 'chantRounds': 16, 'classHearing': 2, 'wakeUpTime': '04:00', 'sleepTiming': '21:45', 'finishTiming': '07:00', 'roundsSource': 'form'};

Future<FakeFirebaseFirestore> world() async {
  final fs = FakeFirebaseFirestore();
  await fs.doc(_reportPath).set(_typed);
  await fs.doc('sadhana-reports/Testing/dates/20-10-2026').set({'bookReading': 30, 'chantRounds': 16});
  await fs.doc('users/u1').set({'name': 'Testing', 'role': 'Stay at Hostel', 'bestReadingMinutes': 65});
  return fs;
}

Future<Map<String, Object?>> snapshotOf(FakeFirebaseFirestore fs, List<String> collections) async {
  final out = <String, Object?>{};
  for (final c in collections) {
    for (final d in (await fs.collection(c).get()).docs) {
      out['$c/${d.id}'] = d.data().toString();
      for (final sub in ['dates']) {
        for (final s in (await d.reference.collection(sub).get()).docs) {
          out['$c/${d.id}/$sub/${s.id}'] = s.data().toString();
        }
      }
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReadingSessionStore.debugResetQueue();
  });

  group('the timer never writes to a sadhana report', () {
    test('a normal close adds to the reading log only: the typed 65 stays 65, in both report collections, and no report appears', () async {
      final fs = await world();
      final before = await snapshotOf(fs, ['hostel-sadhana', 'sadhana-reports']);
      // the day's earlier reading is banked; this session completes new whole minutes (the very case that used to add 15 and 8)
      await fs.doc('users/u1/dailyReading/20-10-2026').set({'secondsToday': 2880});
      for (final seconds in [900, 480, 700]) {
        final ok = await issueReadingWrites(db: fs, uid: 'u1', level: 'level-2', bookKey: 'book_11', title: 'TEACHINGS OF LORD CHAITANYA', seconds: seconds, when: DateTime(2026, 10, 20, 18, 57));
        expect(ok, isTrue);
      }
      expect(await snapshotOf(fs, ['hostel-sadhana', 'sadhana-reports']), before, reason: 'every report byte for byte as the student left it');
      expect((await fs.doc(_reportPath).get()).data()!['bookReading'], 65);
      expect((await fs.doc('sadhana-reports/Testing/dates/20-10-2026').get()).data()!['bookReading'], 30);
      // the reading log did get the time
      expect((await fs.doc('readingDays/u1_20261020').get()).data()!['totalSeconds'], 900 + 480 + 700);
      expect((await fs.doc('users/u1/dailyReading/20-10-2026').get()).data()!['secondsToday'], 2880 + 900 + 480 + 700);
      // nothing on the user's best stats either
      expect((await fs.doc('users/u1').get()).data()!['bestReadingMinutes'], 65);
    });

    test('the recovery of a killed app\'s session also leaves every report alone', () async {
      final fs = await world();
      final before = await snapshotOf(fs, ['hostel-sadhana', 'sadhana-reports']);
      final store = ReadingSessionStore();
      await store.save(ReadingSession(id: 'u1_level-2_book_11_1', uid: 'u1', level: 'level-2', bookKey: 'book_11', title: 'Gita', seconds: 1500, when: DateTime(2026, 10, 20, 12), run: 'old-run'));
      ReadingSessionStore.currentRun = 'new-run';
      final written = await recoverReadingSessions(
        uid: 'u1',
        store: store,
        write: (s) async {
          await issueReadingWrites(db: fs, uid: s.uid, level: s.level, bookKey: s.bookKey, title: s.title, seconds: s.seconds, when: s.when);
        },
      );
      expect(written, 1);
      expect(await snapshotOf(fs, ['hostel-sadhana', 'sadhana-reports']), before);
      expect((await fs.doc('readingDays/u1_20261020').get()).data()!['totalSeconds'], 1500, reason: 'the history has it');
    });

    test('a day with NO report is not given one either', () async {
      final fs = FakeFirebaseFirestore();
      await issueReadingWrites(db: fs, uid: 'u1', level: 'level-1', bookKey: 'book_1', title: 'Gita', seconds: 3000, when: DateTime(2026, 10, 20));
      expect((await fs.collection('hostel-sadhana').get()).docs, isEmpty);
      expect((await fs.collection('sadhana-reports').get()).docs, isEmpty);
    });

    test('the write function cannot even be pointed at a report any more (no name / collection parameters)', () {
      final src = File('lib/utils/ReadingSessionStore.dart').readAsStringSync();
      expect(src.contains('reportCollection'), isFalse);
      expect(src.contains('userName'), isFalse);
      expect(src.contains("'bookReading'"), isFalse, reason: 'the timer file never writes a bookReading field');
      expect(src.contains('sadhana-reports'), isFalse);
      expect(src.contains('hostel-sadhana'), isFalse);
      expect(src.contains('SadhanaReportSource'), isFalse);
    });
  });

  test('no code in the app writes a sadhana report except the two forms (and the Guide-side calendar is not here)', () {
    // every `bookReading` write in lib/ is a form's own typed value; none is an increment
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      final p = f.path.replaceAll('\\', '/');
      if (RegExp(r'bookReading.{0,3}:\s*FieldValue').hasMatch(src) || RegExp(r'increment\([^)]*\)[^;]*bookReading|bookReading[^;]*increment\(').hasMatch(src)) offenders.add(p);
      if (p.endsWith('utils/ReadingSessionStore.dart') || p.endsWith('pages/BookPageList.dart') || p.endsWith('pages/BookReaderPage.dart') || p.endsWith('utils/BookReadingLog.dart')) {
        expect(src.contains("'bookReading'"), isFalse, reason: '$p touches a report field');
        expect(src.contains('hostel-sadhana') || src.contains('sadhana-reports'), isFalse, reason: '$p reads or writes a sadhana report');
      }
    }
    expect(offenders, isEmpty, reason: 'nobody adds minutes to bookReading');
  });

  group('the points use only the typed form values', () {
    test('the day score reads the report map and nothing else: the same typed 65 gives the same points whatever the timer logged', () {
      const report = {'classHearing': 2, 'chantRounds': 16, 'bookReading': 65, 'wakeUpTime': '04:00', 'sleepTiming': '21:45', 'finishTiming': '07:00'};
      // the scoring function takes one report map and the commitments: there is no way to give it a reading log
      double total(Map<String, dynamic> r) => scoreDayTotal(r, form: ReportForm.hostel, chantCommitment: 12, readCommitment: 50);
      final a = total(report);
      final b = total({...report, 'readingLogSeconds': 99999, 'secondsToday': 99999});
      expect(b, a, reason: 'unknown (timer) fields change nothing');
      expect(readingPoints(65, 50), 65, reason: 'the typed minutes');
      expect(total({...report, 'bookReading': 88}) - a, closeTo(23 * 3.375, 1e-6), reason: 'only a typed change moves the points');
    });
    test('the score code never reads the timer\'s collections or fields', () {
      for (final f in ['lib/utils/DayScore.dart', 'lib/utils/FormPoints.dart', 'lib/utils/InsightsData.dart', 'lib/utils/LeaderboardData.dart']) {
        final src = File(f).readAsStringSync();
        for (final timer in ['readingDays', 'dailyReading', 'totalReadingSeconds', 'secondsToday', 'ReadingSessionStore']) {
          expect(src.contains(timer), isFalse, reason: '$f must not read $timer');
        }
      }
    });
  });
}
