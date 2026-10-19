import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/utils/Commitments.dart';
import 'package:folk_app/utils/DayScore.dart';

import 'save_path_test.dart' show app, fillFolk, fillHostel, flushBanner, phone, tapSubmit;
import 'text_scale_test.dart' show loadAppFonts;

// "Sadhana submitted · N points": the points of THAT day, worked out with the SAME rules and the SAME shared vectors
// as the server (functions/scoring.js; functions/test/scoring_vectors.json is copied to test/fixtures).
Map<String, dynamic> vectors() => jsonDecode(File('test/fixtures/scoring_vectors.json').readAsStringSync()) as Map<String, dynamic>;

void near(num a, num b, [String? reason]) => expect(a, closeTo(b, 1e-6), reason: reason);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('the app scorer equals the server on the shared vectors', () {
    test('every tier boundary of every multiplier', () {
      final tiers = vectors()['tiers'] as Map<String, dynamic>;
      final fns = <String, double Function(Object?)>{
        'japa': japaMultiplier,
        'sleepFolk': folkSleepMultiplier,
        'temple': templeMultiplier,
        'wakeup': wakeupMultiplier,
        'sleepHostel': hostelSleepMultiplier,
      };
      expect(tiers.keys.toSet(), fns.keys.toSet(), reason: 'a new tier list on the server needs a port here');
      for (final e in tiers.entries) {
        for (final c in e.value as List) {
          near(fns[e.key]!(c[0]), (c[1] as num).toDouble(), '${e.key} at ${c[0]}');
        }
      }
    });

    test('chanting, reading (commitment 0 = flat 50), graded items and the extra lecture', () {
      final v = vectors();
      for (final c in v['chanting'] as List) {
        near(chantingPoints(c[0] as num, c[1] as num), (c[2] as num).toDouble(), 'chanting ${c[0]}/${c[1]}');
      }
      for (final c in v['reading'] as List) {
        near(readingPoints(c[0] as num, c[1] as num), (c[2] as num).toDouble(), 'reading ${c[0]}/${c[1]}');
      }
      for (final c in v['graded'] as List) {
        near(gradedPoints(c[0]), (c[1] as num).toDouble());
      }
      for (final c in v['extra'] as List) {
        near(gradedPoints(c[0]), (c[1] as num).toDouble());
      }
    });

    test('whole days: FOLK and Hostel & Localite, multipliers included, commitment 0, no cap', () {
      final days = vectors()['days'] as List;
      expect(days.length, greaterThanOrEqualTo(7));
      for (final d in days) {
        final total = scoreDayTotal(
          Map<String, dynamic>.from(d['report'] as Map),
          form: d['form'] == 'hostel' ? ReportForm.hostel : ReportForm.folk,
          chantCommitment: (d['chantCommitment'] as num).toInt(),
          readCommitment: (d['readCommitment'] as num).toInt(),
        );
        near(total, (d['total'] as num).toDouble(), d['name'] as String);
      }
    });

    test('a missing commitment is the server default (chanting 16; reading flat 50)', () {
      final report = {'classHearing': 0, 'chantRounds': 16, 'bookReading': 10, 'templeEntry': '09:00', 'sleepTiming': '23:59', 'finishTiming': '19:00'};
      near(scoreDayTotal(report, form: ReportForm.folk, chantCommitment: 0, readCommitment: 0), 100);
      near(scoreDayTotal(report, form: ReportForm.folk, chantCommitment: -5, readCommitment: -1), 100);
    });
  });

  group('the message', () {
    test('a sensible whole number: halves up, never a fraction, never negative', () {
      expect(sadhanaSubmittedMessage(150), 'Sadhana submitted · 150 points');
      expect(sadhanaSubmittedMessage(337.5), 'Sadhana submitted · 338 points');
      expect(sadhanaSubmittedMessage(759.375), 'Sadhana submitted · 759 points');
      expect(sadhanaSubmittedMessage(390.625), 'Sadhana submitted · 391 points');
      expect(sadhanaSubmittedMessage(0), 'Sadhana submitted · 0 points');
      expect(sadhanaSubmittedMessage(0.4), 'Sadhana submitted · 0 points');
      expect(sadhanaSubmittedMessage(1), 'Sadhana submitted · 1 point');
      expect(sadhanaSubmittedMessage(337.4), 'Sadhana submitted · 337 points');
      expect(sadhanaSubmittedMessage(337.49999999999994), 'Sadhana submitted · 338 points', reason: 'float drift below a .5 is still a half');
      expect(sadhanaSubmittedMessage(1234.56), isNot(contains('.')));
    });
  });

  // -------------------------------------------------------------------------- through the real screens
  Future<void> openFolk(WidgetTester tester, {double scale = 1.0, Commitments? commitments}) async {
    phone(tester, scale);
    await tester.pumpWidget(app(QuestionsPage(
      saveReport: (r, d, e) async {},
      loadCommitments: () async => commitments ?? const Commitments(readingMinutes: 0),
    )));
    await tester.pump();
  }

  Future<void> openHostel(WidgetTester tester, {double scale = 1.0, Commitments? commitments}) async {
    phone(tester, scale);
    await tester.pumpWidget(app(SadhanaPage(
      saveReport: (r, d) async {},
      loadCommitments: () async => commitments ?? const Commitments(readingMinutes: 0),
    )));
    await tester.pump();
  }

  Future<void> submitted(WidgetTester tester, String message) async {
    await tester.pump();
    await tester.pump();
    expect(find.text(message), findsOneWidget);
    // the green banner fits the 360 dp screen (no overflow, nothing cut off) at every text size
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.text(message));
    expect(box.left, greaterThanOrEqualTo(0));
    expect(box.right, lessThanOrEqualTo(360));
    await flushBanner(tester);
  }

  for (final scale in [1.0, 1.3, 1.6]) {
    group('text scale $scale', () {
      testWidgets('FOLK form: temple 05:20 (1.5) x sleep 22:30 (1.25) x japa 19:15 (1.0); 200 base points -> 375', (tester) async {
        await openFolk(tester, scale: scale);
        await fillFolk(tester); // class 50 + services 25 + chanting 50 (16/16) + reading 50 (commitment 0, flat) + extra 25
        await tapSubmit(tester);
        await submitted(tester, 'Sadhana submitted · 375 points');
      });

      testWidgets('Hostel & Localite form: wake 05:30 (1.5) x sleep 22:30 (1.5) x japa 19:15 (1.0); 150 base -> 338', (tester) async {
        await openHostel(tester, scale: scale);
        await fillHostel(tester);
        await tapSubmit(tester);
        await submitted(tester, 'Sadhana submitted · 338 points');
      });
    });
  }

  testWidgets('uses the student\'s own commitments: chanting 8, reading 60 minutes (Hostel & Localite)', (tester) async {
    await openHostel(tester, commitments: const Commitments(rounds: 8, readingMinutes: 60));
    await fillHostel(tester); // class 50 + chanting 100 (16 on 8) + reading 25 (30 on 60) = 175 x 2.25
    await tapSubmit(tester);
    await submitted(tester, 'Sadhana submitted · 394 points');
  });

  testWidgets('re-submitting the same date shows that day\'s UPDATED points', (tester) async {
    await openFolk(tester);
    await fillFolk(tester);
    await tapSubmit(tester);
    await submitted(tester, 'Sadhana submitted · 375 points');
    // the same date again with 32 rounds instead of 16: chanting 100 -> base 250 x 1.875
    await fillFolk(tester, rounds: '32');
    await tapSubmit(tester);
    await submitted(tester, 'Sadhana submitted · 469 points');
  });
}
