import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/FormRounds.dart';

/// ALL SADHANA NUMBERS COME FROM THE SADHANA FORM ONLY: the ABCDE chanting number is the form's rounds over the last 30 days, never the in-app
/// japa counter, and the screens that score / summarise sadhana never read a timer or a counter.
void main() {
  final now = DateTime(2026, 10, 30, 10);
  Map<String, Map<String, dynamic>> reports(Map<String, Object?> byKey) => {for (final e in byKey.entries) e.key: <String, dynamic>{'chantRounds': e.value}};

  test('the rounds of the last 30 days from the form: a report filed on day N records day N-1', () {
    final r = reports({'29-10-2026': 16, '28-10-2026': 12, '01-10-2026': 8});
    expect(formRoundsLast30(r, now), 16 + 12 + 8);
  });

  test('older than 30 days, or today\'s practice not yet reported, does not count; junk keys and values are ignored', () {
    final r = reports({
      '30-10-2026': 10, // records 29 Oct: counts
      '31-10-2026': 99, // records 30 Oct = today: not yet
      '29-09-2026': 50, // records 28 Sep: more than 30 days ago
      'not-a-date': 5,
      '27-10-2026': 'x',
      '26-10-2026': -3,
    });
    expect(formRoundsLast30(r, now), 10);
  });

  test('a counter field on the report is never added to the rounds', () {
    final r = {
      '29-10-2026': <String, dynamic>{'chantRounds': 12, 'japaCounterRounds': 500, 'roundsSource': 'both', 'lifetimeRounds': 9999},
    };
    expect(formRoundsLast30(r, now), 12);
  });

  test('the ABCDE home screen reads no timer and no counter', () {
    final src = File('lib/pages/ABCDEScreen.dart').readAsStringSync().split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    for (final banned in ['lifetimeRounds', 'totalReadingSeconds', 'secondsToday', 'readingDays', 'dailyReading', 'japaCounterRounds']) {
      expect(src.contains(banned), isFalse, reason: 'ABCDEScreen must not read $banned');
    }
  });

  test('only the personal-history screens touch the timer / counter data', () {
    const personal = {
      'ChantingScreen.dart', // the counter itself and its own history strip
      'BookReadingLog.dart', 'ReadingSessionStore.dart', 'BooksHistoryPage.dart', 'BookPageList.dart', 'RduaScreen.dart', // the reading timer and its history
      'Questions.dart', 'Sadhana.dart', // the forms keep the counter's metadata field when they save a report (never read for scoring)
      'FormRounds.dart', // this rule
    };
    final banned = RegExp(r'\b(lifetimeRounds|totalReadingSeconds|secondsToday|readingDays|dailyReading|japaCounterRounds)\b');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final name = f.uri.pathSegments.last;
      if (personal.contains(name)) continue;
      final code = f.readAsStringSync().split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      if (banned.hasMatch(code)) offenders.add(f.path);
    }
    expect(offenders, isEmpty, reason: 'these files read timer / counter data: ${offenders.join(', ')}');
  });
}
