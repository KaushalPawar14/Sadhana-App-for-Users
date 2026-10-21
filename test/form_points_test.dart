import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/utils/Commitments.dart';
import 'package:folk_app/utils/DayScore.dart';
import 'package:folk_app/utils/FormPoints.dart';
import 'package:folk_app/utils/PointsHelp.dart';
import 'package:folk_app/widgets/PointsChip.dart';
import 'package:folk_app/widgets/PointsHelpSheet.dart';

import 'save_path_test.dart' show app, fillFolk, fillHostel, phone;
import 'text_scale_test.dart' show scales, loadAppFonts;

// The Sadhana forms show the points of each answer while it is typed (a chip in the question's card), a running
// "Today so far" total, and an "i" help sheet per scoring question. All of it uses the same DayScore rules as the server.
Map<String, dynamic> vectors() => jsonDecode(File('test/fixtures/scoring_vectors.json').readAsStringSync()) as Map<String, dynamic>;

LiveFormPoints live(ReportForm form, Map<String, Object?> values, {int rounds = 16, int? reading = 0}) {
  final p = LiveFormPoints(form: form, read: () => values);
  p.commitments = Commitments(rounds: rounds, readingMinutes: reading);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('the chips: what each answer earns (the DayScore rules)', () {
    test('chanting and reading against the commitment; reading commitment 0 = a flat 50', () {
      var p = live(ReportForm.folk, {'chantRounds': 16, 'bookReading': 5});
      expect(p.chipFor(PointsTopic.chanting), '+50 pts');
      expect(p.chipFor(PointsTopic.reading), '+50 pts', reason: 'commitment 0: any reading is a flat 50');
      p = live(ReportForm.folk, {'chantRounds': 8, 'bookReading': 0});
      expect(p.chipFor(PointsTopic.chanting), '+25 pts');
      expect(p.chipFor(PointsTopic.reading), '+0 pts');
      p = live(ReportForm.folk, {'chantRounds': 64, 'bookReading': 45}, reading: 30);
      expect(p.chipFor(PointsTopic.chanting), '+200 pts', reason: 'no cap');
      expect(p.chipFor(PointsTopic.reading), '+75 pts');
      p = live(ReportForm.folk, {'chantRounds': 10}, rounds: 8);
      expect(p.chipFor(PointsTopic.chanting), '+62.5 pts');
    });

    test('Fully / Partially / Not and the extra lecture tiers', () {
      final p = live(ReportForm.folk, {'classHearing': 2, 'dailyServices': 1, 'extraLecture': 0});
      expect(p.chipFor(PointsTopic.sbClass), '+50 pts');
      expect(p.chipFor(PointsTopic.services), '+25 pts');
      expect(p.chipFor(PointsTopic.extraLecture), '+0 pts');
      expect(live(ReportForm.folk, {'extraLecture': 2}).chipFor(PointsTopic.extraLecture), '+50 pts');
      expect(live(ReportForm.folk, {'extraLecture': 1}).chipFor(PointsTopic.extraLecture), '+25 pts');
    });

    test('the time multipliers of FOLK: temple, sleep, japa', () {
      LiveFormPoints f(Map<String, Object?> v) => live(ReportForm.folk, v);
      expect(f({'templeEntry': '05:20'}).chipFor(PointsTopic.temple), '×1.5');
      expect(f({'templeEntry': '05:40'}).chipFor(PointsTopic.temple), '×1.25');
      expect(f({'templeEntry': '06:00'}).chipFor(PointsTopic.temple), '×1.15');
      expect(f({'templeEntry': '07:00'}).chipFor(PointsTopic.temple), '×1.0');
      expect(f({'sleepTiming': '22:00'}).chipFor(PointsTopic.sleep), '×1.5');
      expect(f({'sleepTiming': '22:30'}).chipFor(PointsTopic.sleep), '×1.25');
      expect(f({'sleepTiming': '23:00'}).chipFor(PointsTopic.sleep), '×1.15');
      expect(f({'sleepTiming': '23:59'}).chipFor(PointsTopic.sleep), '×1.0');
      expect(f({'finishTiming': '09:00'}).chipFor(PointsTopic.japa), '×1.5');
      expect(f({'finishTiming': '14:00'}).chipFor(PointsTopic.japa), '×1.25');
      expect(f({'finishTiming': '18:00'}).chipFor(PointsTopic.japa), '×1.15');
      expect(f({'finishTiming': '19:15'}).chipFor(PointsTopic.japa), '×1.0');
    });

    test('Hostel & Localite: wake-up and its own sleep tiers; no temple / services / extra lecture', () {
      LiveFormPoints h(Map<String, Object?> v) => live(ReportForm.hostel, v);
      expect(h({'wakeUpTime': '05:30'}).chipFor(PointsTopic.wakeup), '×1.5');
      expect(h({'wakeUpTime': '06:00'}).chipFor(PointsTopic.wakeup), '×1.25');
      expect(h({'wakeUpTime': '06:30'}).chipFor(PointsTopic.wakeup), '×1.15');
      expect(h({'wakeUpTime': '07:00'}).chipFor(PointsTopic.wakeup), '×1.0');
      expect(h({'sleepTiming': '22:30'}).chipFor(PointsTopic.sleep), '×1.5', reason: 'the Hostel tiers differ from FOLK (22:30 is x1.25 there)');
      expect(live(ReportForm.folk, {'sleepTiming': '22:30'}).chipFor(PointsTopic.sleep), '×1.25');
      for (final t in [PointsTopic.temple, PointsTopic.services, PointsTopic.extraLecture]) {
        expect(h({'templeEntry': '05:00', 'dailyServices': 2, 'extraLecture': 2}).chipFor(t), isNull, reason: '$t is not on the Hostel form');
      }
      expect(live(ReportForm.folk, {'wakeUpTime': '05:00'}).chipFor(PointsTopic.wakeup), isNull);
    });

    test('nothing is shown until the question is answered', () {
      final p = live(ReportForm.folk, {'chantRounds': null, 'bookReading': null, 'classHearing': null, 'templeEntry': '', 'sleepTiming': '', 'finishTiming': 'abc'});
      for (final t in PointsTopic.values) {
        expect(p.chipFor(t), isNull, reason: '$t');
      }
    });
  });

  group('the running total equals the day\'s points (the shared vectors)', () {
    test('every whole-day vector, FOLK and Hostel & Localite', () {
      for (final d in vectors()['days'] as List) {
        final r = Map<String, Object?>.from(d['report'] as Map);
        final p = live(d['form'] == 'hostel' ? ReportForm.hostel : ReportForm.folk, r,
            rounds: (d['chantCommitment'] as num).toInt(), reading: (d['readCommitment'] as num).toInt());
        expect(p.total, closeTo((d['total'] as num).toDouble(), 1e-6), reason: d['name'] as String);
      }
    });

    test('the text: whole points, "point" for one, 0 when nothing is answered', () {
      expect(live(ReportForm.folk, {}).totalText, 'Today so far: 0 points');
      expect(live(ReportForm.folk, {'chantRounds': 16, 'finishTiming': '23:00'}, rounds: 16).totalText, 'Today so far: 50 points');
      expect(live(ReportForm.folk, {'chantRounds': 1}, rounds: 50).totalText, 'Today so far: 1 point');
      expect(live(ReportForm.folk, {'classHearing': 2, 'dailyServices': 1, 'chantRounds': 16, 'bookReading': 30, 'extraLecture': 1, 'templeEntry': '05:20', 'sleepTiming': '22:30', 'finishTiming': '19:15'}).totalText,
          'Today so far: 375 points');
    });

    test('it follows the answers live (the notifier ticks)', () {
      final values = <String, Object?>{'chantRounds': 16};
      final p = live(ReportForm.folk, values);
      var ticks = 0;
      p.tick.addListener(() => ticks++);
      expect(p.totalText, 'Today so far: 50 points');
      values['chantRounds'] = 32;
      p.bump();
      expect(p.totalText, 'Today so far: 100 points');
      p.setCommitments(const Commitments(rounds: 32, readingMinutes: 0));
      expect(p.totalText, 'Today so far: 50 points');
      expect(ticks, 2);
    });
  });

  group('the "i" help: plain words, the student\'s own commitments, the real tier tables', () {
    test('chanting and reading use the commitment; a missing commitment says so; commitment 0 has its own rule', () {
      var h = pointsHelp(PointsTopic.chanting, ReportForm.folk, const Commitments(rounds: 8, readingMinutes: 30));
      expect(h.paragraphs.join(' '), contains('Your commitment is 8 rounds a day.'));
      expect(h.rows, [('8 rounds', '50 pts'), ('4 rounds', '25 pts'), ('16 rounds', '100 pts')]);
      h = pointsHelp(PointsTopic.chanting, ReportForm.folk, const Commitments(roundsSet: false, readingMinutes: 0));
      expect(h.paragraphs.join(' '), contains('standard 16 rounds'));
      h = pointsHelp(PointsTopic.reading, ReportForm.folk, const Commitments(readingMinutes: 30));
      expect(h.rows, [('30 minutes', '50 pts'), ('15 minutes', '25 pts'), ('60 minutes', '100 pts')]);
      h = pointsHelp(PointsTopic.reading, ReportForm.folk, const Commitments(readingMinutes: 0));
      expect(h.paragraphs.join(' '), contains('flat 50 points'));
      expect(h.rows, [('Any reading', '50 pts'), ('No reading', '0 pts')]);
    });

    test('Fully / Partially / Not, and the extra lecture tiers', () {
      expect(pointsHelp(PointsTopic.sbClass, ReportForm.folk, const Commitments()).rows, [('Fully', '50 pts'), ('Partial', '25 pts'), ('Missed', '0 pts')]);
      expect(pointsHelp(PointsTopic.services, ReportForm.folk, const Commitments()).rows, [('Done fully', '50 pts'), ('Done partially', '25 pts'), ('Not done', '0 pts')]);
      expect(pointsHelp(PointsTopic.extraLecture, ReportForm.folk, const Commitments()).rows,
          [('More than 30 minutes', '50 pts'), ('More than 15 minutes', '25 pts'), ('No', '0 pts')]);
    });

    test('every multiplier table is exactly the scorer\'s tiers, for the student\'s category', () {
      final cases = <(PointsTopic, ReportForm, ScoreTier)>[
        (PointsTopic.temple, ReportForm.folk, ScoreTier.temple),
        (PointsTopic.wakeup, ReportForm.hostel, ScoreTier.wakeup),
        (PointsTopic.sleep, ReportForm.folk, ScoreTier.sleepFolk),
        (PointsTopic.sleep, ReportForm.hostel, ScoreTier.sleepHostel),
        (PointsTopic.japa, ReportForm.folk, ScoreTier.japa),
        (PointsTopic.japa, ReportForm.hostel, ScoreTier.japa),
      ];
      for (final c in cases) {
        final h = pointsHelp(c.$1, c.$2, const Commitments());
        final tiers = tierRows(c.$3);
        expect(h.rows.length, tiers.length + 1, reason: '${c.$1} ${c.$2}');
        for (var i = 0; i < tiers.length; i++) {
          expect(h.rows[i], ('By ${clockText(tiers[i].limit)}', multiplierText(tiers[i].multiplier)));
        }
        expect(h.rows.last, ('Later, or not entered', '×1.0'));
      }
      expect(pointsHelp(PointsTopic.sleep, ReportForm.folk, const Commitments()).rows.first, ('By 10:00 PM', '×1.5'));
      expect(pointsHelp(PointsTopic.sleep, ReportForm.hostel, const Commitments()).rows.first, ('By 10:30 PM', '×1.5'));
      expect(pointsHelp(PointsTopic.temple, ReportForm.folk, const Commitments()).rows.first, ('By 5:35 AM', '×1.5'));
      expect(pointsHelp(PointsTopic.japa, ReportForm.folk, const Commitments()).rows.first, ('By 10:00 AM', '×1.5'));
      expect(clockText(0), '12:00 AM');
      expect(clockText(12 * 60), '12:00 PM');
    });

    test('how the total works: points × multipliers, with the category\'s multipliers', () {
      expect(pointsHelp(null, ReportForm.folk, const Commitments()).paragraphs.join(' '), contains('temple, sleep and japa'));
      expect(pointsHelp(null, ReportForm.hostel, const Commitments()).paragraphs.join(' '), contains('wake-up, sleep and japa'));
      expect(pointsHelp(PointsTopic.chanting, ReportForm.folk, const Commitments()).footer, contains('× your temple × sleep × japa multipliers'));
      expect(pointsHelp(PointsTopic.chanting, ReportForm.hostel, const Commitments()).footer, contains('× your wake-up × sleep × japa multipliers'));
    });
  });

  // ------------------------------------------------------------------------------------------------ the real forms
  Future<void> openFolk(WidgetTester tester, {double scale = 1.0, Commitments commitments = const Commitments(readingMinutes: 0), bool dark = false}) async {
    phone(tester, scale);
    await tester.pumpWidget(app(QuestionsPage(saveReport: (r, d, e) async {}, loadCommitments: () async => commitments)));
    await tester.pump();
    await tester.pump();
  }

  Future<void> openHostel(WidgetTester tester, {double scale = 1.0, Commitments commitments = const Commitments(readingMinutes: 0)}) async {
    phone(tester, scale);
    await tester.pumpWidget(app(SadhanaPage(saveReport: (r, d) async {}, loadCommitments: () async => commitments)));
    await tester.pump();
    await tester.pump();
  }

  String chipText(WidgetTester tester, String topic) => tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('chip-$topic')), matching: find.byType(Text))).data!;
  Finder total() => find.byKey(const ValueKey('today-total-text'));
  String totalText(WidgetTester tester) => tester.widget<Text>(total()).data!;

  group('the FOLK form', () {
    testWidgets('chips appear as answers are entered, with the multiplier chips, and the total follows', (tester) async {
      await openFolk(tester);
      expect(find.byType(PointsChip), findsNothing, reason: 'nothing answered yet');
      expect(totalText(tester), 'Today so far: 0 points');
      await fillFolk(tester); // temple 05:20, class 2, services 1, rounds 16, book 30, sleep 22:30, japa 19:15, extra "more than 15 mins"
      expect(chipText(tester, 'temple'), '×1.5');
      expect(chipText(tester, 'sbClass'), '+50 pts');
      expect(chipText(tester, 'services'), '+25 pts');
      expect(chipText(tester, 'chanting'), '+50 pts');
      expect(chipText(tester, 'reading'), '+50 pts', reason: 'commitment 0: a flat 50');
      expect(chipText(tester, 'sleep'), '×1.25');
      expect(chipText(tester, 'japa'), '×1.0');
      expect(chipText(tester, 'extraLecture'), '+25 pts');
      expect(totalText(tester), 'Today so far: 375 points');
      // changing an answer updates its chip and the total at once
      final rounds = find.byType(TextField, skipOffstage: false).at(3);
      await tester.enterText(rounds, '32');
      await tester.pump();
      expect(chipText(tester, 'chanting'), '+100 pts');
      expect(totalText(tester), 'Today so far: 469 points');
      await tester.enterText(rounds, '');
      await tester.pump();
      expect(find.byKey(const ValueKey('chip-chanting')), findsNothing, reason: 'cleared: the chip goes');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the student\'s own commitments are used (chanting 8, reading 60)', (tester) async {
      await openFolk(tester, commitments: const Commitments(rounds: 8, readingMinutes: 60));
      await fillFolk(tester);
      expect(chipText(tester, 'chanting'), '+100 pts', reason: '16 rounds on 8');
      expect(chipText(tester, 'reading'), '+25 pts', reason: '30 minutes on 60');
    });

    testWidgets('only the scoring questions have an "i" (and a chip); the date and academics do not', (tester) async {
      await openFolk(tester);
      final infos = tester.widgetList<PointsInfoButton>(find.byType(PointsInfoButton, skipOffstage: false)).map((b) => b.label).toList();
      expect(infos.length, 9, reason: 'eight scoring questions + the total');
      for (final q in ['Time Entered Temple Hall', 'SB Class', 'Daily Assigned Services', 'Total rounds chanted yesterday', 'Total book reading', 'Sleep time', 'Japa finish time', 'extra lecture']) {
        expect(infos.any((l) => l.contains(q)), isTrue, reason: q);
      }
      expect(infos.any((l) => l.contains('Date of Submission')), isFalse);
      expect(infos.any((l) => l.contains('Academics')), isFalse);
    });

    testWidgets('the "i" of chanting opens its sheet with the student\'s commitment; Close closes it', (tester) async {
      await openFolk(tester, commitments: const Commitments(rounds: 8, readingMinutes: 30));
      final info = find.byWidgetPredicate((w) => w is PointsInfoButton && w.label.contains('rounds chanted'));
      await tester.ensureVisible(info);
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('points-help-sheet')), findsOneWidget);
      expect(find.text('Chanting points'), findsOneWidget);
      expect(find.text('Your commitment is 8 rounds a day.'), findsOneWidget);
      expect(find.text('16 rounds'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('points-help-sheet')), findsNothing);
    });

    testWidgets('the total has its own "i": how the points add up', (tester) async {
      await openFolk(tester);
      final info = find.descendant(of: find.byKey(const ValueKey('today-total')), matching: find.byType(PointsInfoButton));
      await tester.ensureVisible(info);
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(find.text("How today's points add up"), findsOneWidget);
      expect(find.textContaining('temple, sleep and japa'), findsOneWidget);
    });

    for (final scale in scales) {
      testWidgets('text scale $scale: chips and "i" fit, no overflow, the sheets scroll', (tester) async {
        await openFolk(tester, scale: scale);
        await fillFolk(tester);
        expect(tester.takeException(), isNull);
        for (final k in ['temple', 'sbClass', 'services', 'chanting', 'reading', 'sleep', 'japa', 'extraLecture']) {
          final chip = tester.getRect(find.byKey(ValueKey('chip-$k')));
          expect(chip.right, lessThanOrEqualTo(360), reason: k);
          expect(chip.left, greaterThanOrEqualTo(0), reason: k);
        }
        for (final b in tester.widgetList<PointsInfoButton>(find.byType(PointsInfoButton, skipOffstage: false))) {
          final r = tester.getRect(find.byWidget(b, skipOffstage: false));
          expect(r.height, greaterThanOrEqualTo(44), reason: b.label);
          expect(r.right, lessThanOrEqualTo(360 + 8), reason: b.label);
        }
        // the longest sheet (the japa tiers) at this size: inside the screen, scrolls, Close reachable
        final info = find.byWidgetPredicate((w) => w is PointsInfoButton && w.label.contains('Japa finish time'));
        await tester.ensureVisible(info);
        await tester.tap(info);
        await tester.pumpAndSettle();
        final sheet = tester.getRect(find.byKey(const ValueKey('points-help-sheet')));
        expect(sheet.right, lessThanOrEqualTo(360));
        expect(sheet.height, lessThanOrEqualTo(800 * .88 + 1));
        expect(find.text('Close'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the Hostel & Localite form', () {
    testWidgets('chips, wake-up and its own multipliers, and the total', (tester) async {
      await openHostel(tester);
      expect(totalText(tester), 'Today so far: 0 points');
      await fillHostel(tester); // sleep 22:30, wake 05:30, rounds 16, class 2, book 30, japa 19:15
      expect(chipText(tester, 'sleep'), '×1.5');
      expect(chipText(tester, 'wakeup'), '×1.5');
      expect(chipText(tester, 'chanting'), '+50 pts');
      expect(chipText(tester, 'sbClass'), '+50 pts');
      expect(chipText(tester, 'reading'), '+50 pts');
      expect(chipText(tester, 'japa'), '×1.0');
      for (final gone in ['temple', 'services', 'extraLecture']) {
        expect(find.byKey(ValueKey('chip-$gone')), findsNothing);
      }
      expect(totalText(tester), 'Today so far: 338 points');
      final infos = tester.widgetList<PointsInfoButton>(find.byType(PointsInfoButton, skipOffstage: false)).map((b) => b.label).toList();
      expect(infos.length, 7, reason: 'six scoring questions + the total');
      expect(infos.any((l) => l.contains('Temple')), isFalse);
    });

    testWidgets('the sleep sheet shows the HOSTEL tiers (10:30 PM first), and the wake-up sheet its own', (tester) async {
      await openHostel(tester);
      Future<void> openAndRead(String label, String first) async {
        final info = find.byWidgetPredicate((w) => w is PointsInfoButton && w.label.contains(label));
        await tester.ensureVisible(info);
        await tester.tap(info);
        await tester.pumpAndSettle();
        expect(find.text(first), findsOneWidget, reason: label);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }

      await openAndRead('Sleep time', 'By 10:30 PM');
      await openAndRead('Waking Up Time', 'By 5:30 AM');
    });

    for (final scale in scales) {
      testWidgets('text scale $scale: no overflow', (tester) async {
        await openHostel(tester, scale: scale);
        await fillHostel(tester);
        expect(tester.takeException(), isNull);
        for (final k in ['sleep', 'wakeup', 'chanting', 'sbClass', 'reading', 'japa']) {
          expect(tester.getRect(find.byKey(ValueKey('chip-$k'))).right, lessThanOrEqualTo(360), reason: k);
        }
      });
    }
  });

  testWidgets('light and dark: the chips keep the ink colour (gold points, violet multipliers)', (tester) async {
    await openFolk(tester);
    await fillFolk(tester);
    final pts = tester.widget<Container>(find.descendant(of: find.byKey(const ValueKey('chip-chanting')), matching: find.byType(Container)).first);
    final mult = tester.widget<Container>(find.descendant(of: find.byKey(const ValueKey('chip-sleep')), matching: find.byType(Container)).first);
    expect((pts.decoration! as BoxDecoration).gradient, isNotNull);
    expect((mult.decoration! as BoxDecoration).gradient, isNot((pts.decoration! as BoxDecoration).gradient), reason: 'points and multipliers look different');
  });
}
