import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/utils/Commitments.dart';
import 'package:folk_app/utils/ScoreBreakdown.dart';
import 'package:folk_app/widgets/CommitmentDialog.dart';

import 'sadhana_form_time_test.dart' show app, phone, fillFolk, fillHostel, fields, tapSubmit;
import 'text_scale_test.dart' show scales, loadAppFonts;

// The reading commitment, the typo guard and the score breakdown. The points
// themselves are worked out on the server (functions/scoring.js, tested there
// against the same vectors file, copied to test/fixtures).
Map<String, dynamic> vectors() =>
    jsonDecode(File('test/fixtures/scoring_vectors.json').readAsStringSync()) as Map<String, dynamic>;

Future<Commitments> Function() commits({int rounds = 16, int? reading = 0}) =>
    () async => Commitments(rounds: rounds, readingMinutes: reading);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('the typo guard rule', () {
    test('the shared vectors: more than 4x the commitment asks; a commitment of 0 never asks', () {
      for (final v in vectors()['typo'] as List) {
        expect(looksLikeTypo(v[0] as num, v[1] as num), v[2] as bool, reason: '${v[0]} on ${v[1]}');
      }
      expect(kTypoFactor, 4);
    });

    test('the edge: exactly 4x does not ask, one more does', () {
      expect(looksLikeTypo(64, 16), false);
      expect(looksLikeTypo(65, 16), true);
      expect(looksLikeTypo(120, 30), false);
      expect(looksLikeTypo(121, 30), true);
    });
  });

  group('commitments from the profile', () {
    test('missing chanting commitment counts as 16; missing reading is "not set"; 0 reading is set', () {
      final none = Commitments.fromUser({});
      expect(none.rounds, 16);
      expect(none.readingMinutes, isNull);
      expect(none.readingSet, false);
      final beginner = Commitments.fromUser({'commitmentRounds': 8, 'readingCommitmentMinutes': 0});
      expect(beginner.rounds, 8);
      expect(beginner.readingMinutes, 0);
      expect(beginner.readingSet, true);
      expect(Commitments.fromUser(null).rounds, 16);
      expect(Commitments.fromUser({'commitmentRounds': 0}).rounds, 16);
    });

    test('the Profile line: "16 rounds · 30 min reading"', () {
      expect(commitmentLine(const Commitments(rounds: 16, readingMinutes: 30)), '16 rounds · 30 min reading');
      expect(commitmentLine(const Commitments(rounds: 8, readingMinutes: 0)), '8 rounds · no reading target');
      expect(commitmentLine(const Commitments()), '16 rounds · reading not set');
    });

    test('reading commitment entries: 0 .. 1440, whole numbers only', () {
      expect(parseReadingCommitment('0'), 0);
      expect(parseReadingCommitment(' 30 '), 30);
      expect(parseReadingCommitment('1440'), 1440);
      for (final bad in ['', '-1', '1441', '7.5', 'abc', '3 0']) {
        expect(parseReadingCommitment(bad), isNull, reason: bad);
      }
    });
  });

  group('the breakdown reads', () {
    test('multipliers are the averages over the days filed (stored as sums)', () {
      expect(averageMultiplier(7.5, 5), '1.50');
      expect(averageMultiplier(0, 0), '1.00');
      final folk = multiplierLines({
        'weekly.days_count': 2,
        'weekly.temple_multiplier': 2.5,
        'weekly.japa_multiplier': 2.4,
        'weekly.sleeping_multiplier': 2.0,
        'weekly.wakeup_multiplier': 9.0,
      }, 'weekly', hostelLocalite: false);
      expect(folk.map((l) => '${l.label} ${l.value}').toList(), ['🛕 Temple 1.25', '📿 Japa 1.20', '😴 Sleep 1.00']);
      final hostel = multiplierLines({
        'monthly.days_count': 4,
        'monthly.wakeup_multiplier': 4.6,
        'monthly.japa_multiplier': 4.0,
        'monthly.sleeping_multiplier': 5.0,
      }, 'monthly', hostelLocalite: true);
      expect(hostel.map((l) => '${l.label} ${l.value}').toList(), ['⏰ Wake-up 1.15', '📿 Japa 1.00', '😴 Sleep 1.25']);
    });
  });

  group('FOLK form typo guard', () {
    Future<List<Object>> run(WidgetTester tester, {required String rounds, required String book, int? readingCommit, bool confirm = true, bool expectDialog = true}) async {
      final saves = <Object>[];
      phone(tester);
      await tester.pumpWidget(app(QuestionsPage(
        loadCommitments: commits(reading: readingCommit ?? 0),
        saveReport: (r, d, e) async => saves.add([r.chantRounds, r.bookReading, e]),
      )));
      await tester.pump();
      await fillFolk(tester);
      await tester.enterText(fields().at(3), rounds);
      await tester.enterText(fields().at(4), book);
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      if (expectDialog) {
        expect(find.text('You entered ${rounds == '65' || rounds == '200' ? rounds : book}'), findsOneWidget);
        await tester.tap(find.text(confirm ? 'Yes, it is correct' : 'No, let me fix it'));
        await tester.pumpAndSettle();
      } else {
        expect(find.textContaining('You entered'), findsNothing);
      }
      await tester.pump(const Duration(seconds: 4));
      return saves;
    }

    testWidgets('65 rounds on a commitment of 16 asks; "No" saves nothing and keeps what was typed', (tester) async {
      final saves = await run(tester, rounds: '65', book: '30', confirm: false);
      expect(saves, isEmpty);
      expect(tester.widget<TextField>(fields().at(3)).controller!.text, '65');
    });

    testWidgets('65 rounds, "Yes" saves it (no cap)', (tester) async {
      final saves = await run(tester, rounds: '65', book: '30');
      expect(saves.length, 1);
      expect((saves.single as List)[0], 65);
    });

    testWidgets('64 rounds (exactly 4x) does not ask', (tester) async {
      final saves = await run(tester, rounds: '64', book: '30', expectDialog: false);
      expect(saves.length, 1);
    });

    testWidgets('reading 121 minutes on a commitment of 30 asks; 120 does not', (tester) async {
      var saves = await run(tester, rounds: '16', book: '121', readingCommit: 30);
      expect(saves.length, 1);
      saves = await run(tester, rounds: '16', book: '120', readingCommit: 30, expectDialog: false);
      expect(saves.length, 1);
    });

    testWidgets('a reading commitment of 0 never asks about reading (not set: the mandatory box, below)', (tester) async {
      var saves = await run(tester, rounds: '16', book: '600', readingCommit: 0, expectDialog: false);
      expect(saves.length, 1);
    });

    testWidgets('the extra lecture answer goes to the save (more than 15 mins = level 1)', (tester) async {
      final saves = await run(tester, rounds: '16', book: '30', expectDialog: false);
      expect((saves.single as List)[2], 1.0);
    });

    testWidgets('the guard also catches 200 rounds', (tester) async {
      final saves = await run(tester, rounds: '200', book: '30');
      expect((saves.single as List)[0], 200);
    });
  });

  group('Hostel & Localite form typo guard', () {
    testWidgets('65 rounds asks; 64 does not', (tester) async {
      final saves = <int>[];
      phone(tester);
      await tester.pumpWidget(app(SadhanaPage(
        loadCommitments: commits(),
        saveReport: (r, d) async => saves.add(r.chantRounds),
      )));
      await tester.pump();
      await fillHostel(tester);
      await tester.enterText(fields().at(3), '65');
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.text('You entered 65'), findsOneWidget);
      await tester.tap(find.text('No, let me fix it'));
      await tester.pumpAndSettle();
      expect(saves, isEmpty);
      await tester.enterText(fields().at(3), '64');
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('You entered'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(saves, [64]);
    });

    testWidgets('reading far above the commitment asks, "Yes" saves', (tester) async {
      final saves = <int>[];
      phone(tester);
      await tester.pumpWidget(app(SadhanaPage(
        loadCommitments: commits(reading: 20),
        saveReport: (r, d) async => saves.add(r.bookReading),
      )));
      await tester.pump();
      await fillHostel(tester);
      await tester.enterText(fields().at(4), '81');
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.text('You entered 81'), findsOneWidget);
      await tester.tap(find.text('Yes, it is correct'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      expect(saves, [81]);
    });
  });

  group('the commitment dialog', () {
    Future<void> open(WidgetTester tester, {required bool mandatory, double scale = 1.0, bool dark = false, CommitmentChoice? Function(CommitmentChoice?)? onResult, Commitments current = const Commitments(rounds: 16, readingMinutes: 30)}) async {
      phone(tester, scale);
      late BuildContext ctx;
      await tester.pumpWidget(app(
        Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
        dark: dark,
      ));
      showCommitmentDialog(ctx, current: current, mandatory: mandatory).then((v) => onResult?.call(v));
      await tester.pumpAndSettle();
    }

    for (final scale in scales) {
      for (final dark in [false, true]) {
        testWidgets('both fields fit and nothing overflows (text x$scale, ${dark ? 'dark' : 'light'})', (tester) async {
          await open(tester, mandatory: false, scale: scale, dark: dark);
          expect(find.text('Rounds per day'), findsOneWidget);
          expect(find.text('Reading minutes per day'), findsOneWidget);
          expect(find.text('Save'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
        testWidgets('the mandatory prompt fits (text x$scale, ${dark ? 'dark' : 'light'})', (tester) async {
          await open(tester, mandatory: true, scale: scale, dark: dark, current: const Commitments());
          expect(find.textContaining('If you\'re a beginner you can enter 0'), findsOneWidget);
          expect(find.text('Rounds per day'), findsNothing);
          expect(find.text('Cancel'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the Profile edit saves both values', (tester) async {
      CommitmentChoice? got;
      await open(tester, mandatory: false, onResult: (v) { got = v; return null; });
      await tester.enterText(find.byKey(const ValueKey('commitment-rounds')), '8');
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '45');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(got?.rounds, 8);
      expect(got?.readingMinutes, 45);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      CommitmentChoice? got = const CommitmentChoice(rounds: 1, readingMinutes: 1);
      await open(tester, mandatory: false, onResult: (v) { got = v; return null; });
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(got, isNull);
    });

    testWidgets('0 is accepted as a reading commitment (a beginner)', (tester) async {
      CommitmentChoice? got;
      await open(tester, mandatory: true, current: const Commitments(), onResult: (v) { got = v; return null; });
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(got?.readingMinutes, 0);
      expect(got?.rounds, isNull, reason: 'the chanting commitment is left alone');
    });

    testWidgets('an empty or invalid entry shows a message and does not close', (tester) async {
      CommitmentChoice? got;
      await open(tester, mandatory: true, current: const Commitments(), onResult: (v) { got = v; return null; });
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter minutes from 0 to 1440'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '1441');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter minutes from 0 to 1440'), findsOneWidget);
      expect(got, isNull);
    });

    testWidgets('the mandatory prompt cannot be dismissed (tap outside, back)', (tester) async {
      bool closed = false;
      await open(tester, mandatory: true, current: const Commitments(), onResult: (v) { closed = true; return null; });
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.textContaining('If you\'re a beginner'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('If you\'re a beginner'), findsOneWidget);
      expect(closed, false);
    });

    testWidgets('the Profile edit CAN be dismissed (tap outside)', (tester) async {
      await open(tester, mandatory: false);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);
    });
  });

  group('asking a student who has not set it', () {
    Future<BuildContext> host(WidgetTester tester) async {
      phone(tester);
      late BuildContext ctx;
      await tester.pumpWidget(app(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      return ctx;
    }

    testWidgets('not set: asks; a save that fails asks again; a save that works stops', (tester) async {
      resetCommitmentPromptForTests();
      final ctx = await host(tester);
      final saved = <CommitmentChoice>[];
      var tries = 0;
      final done = askForCommitmentsIfMissing(
        ctx,
        load: () async => const Commitments(),
        save: (c) async {
          tries++;
          if (tries == 1) return false;
          saved.add(c);
          return true;
        },
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // the first save failed: still asking
      expect(find.textContaining('If you\'re a beginner'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await done;
      expect(saved.single.readingMinutes, 0);
      expect(find.textContaining('If you\'re a beginner'), findsNothing);
    });

    testWidgets('already set (even to 0): never asks', (tester) async {
      resetCommitmentPromptForTests();
      final ctx = await host(tester);
      await askForCommitmentsIfMissing(ctx, load: () async => const Commitments(readingMinutes: 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('If you\'re a beginner'), findsNothing);
    });
  });

  group('both commitments are mandatory', () {
    test('what counts as missing: no chanting commitment, or no reading commitment', () {
      expect(Commitments.fromUser({}).complete, false);
      expect(Commitments.fromUser({'commitmentRounds': 16}).complete, false, reason: 'reading missing');
      expect(Commitments.fromUser({'readingCommitmentMinutes': 0}).complete, false, reason: 'chanting missing');
      expect(Commitments.fromUser({'commitmentRounds': 16, 'readingCommitmentMinutes': 0}).complete, true, reason: '0 reading is set');
      expect(Commitments.fromUser({'commitmentRounds': 0, 'readingCommitmentMinutes': 30}).complete, false, reason: '0 rounds is not a commitment');
      expect(Commitments.fromUser({}).rounds, 16, reason: 'scoring still uses the standard 16 until it is set');
    });

    test('chanting is a whole number of 1 or more', () {
      expect(parseChantCommitment('16'), 16);
      expect(parseChantCommitment('1'), 1);
      for (final bad in ['', '0', '-3', '2.5', 'x', '1000']) {
        expect(parseChantCommitment(bad), isNull, reason: bad);
      }
    });

    Future<void> open(WidgetTester tester, Commitments current, void Function(CommitmentChoice?) done) async {
      phone(tester, 1.0);
      late BuildContext ctx;
      await tester.pumpWidget(app(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      showCommitmentDialog(ctx, current: current, mandatory: true).then(done);
      await tester.pumpAndSettle();
    }

    testWidgets('only chanting missing: asks only for chanting; 0 rounds is refused', (tester) async {
      CommitmentChoice? got;
      await open(tester, const Commitments(roundsSet: false, readingMinutes: 30), (v) => got = v);
      expect(find.byKey(const ValueKey('commitment-rounds')), findsOneWidget);
      expect(find.byKey(const ValueKey('commitment-reading')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('commitment-rounds')), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number of rounds, 1 or more'), findsOneWidget);
      expect(got, isNull);
      await tester.enterText(find.byKey(const ValueKey('commitment-rounds')), '8');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(got?.rounds, 8);
      expect(got?.readingMinutes, isNull, reason: 'reading is left alone');
    });

    testWidgets('both missing: both fields, both required, 0 reading accepted', (tester) async {
      CommitmentChoice? got;
      await open(tester, const Commitments(roundsSet: false), (v) => got = v);
      expect(find.byKey(const ValueKey('commitment-rounds')), findsOneWidget);
      expect(find.byKey(const ValueKey('commitment-reading')), findsOneWidget);
      expect(find.textContaining('you can enter 0'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number of rounds, 1 or more'), findsOneWidget);
      expect(find.textContaining('Enter minutes from 0 to 1440'), findsOneWidget);
      expect(got, isNull);
      await tester.enterText(find.byKey(const ValueKey('commitment-rounds')), '16');
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(got?.rounds, 16);
      expect(got?.readingMinutes, 0);
    });

    testWidgets('app open: asks for what is missing and stops when both are saved', (tester) async {
      resetCommitmentPromptForTests();
      phone(tester, 1.0);
      late BuildContext ctx;
      await tester.pumpWidget(app(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      final saved = <CommitmentChoice>[];
      final done = askForCommitmentsIfMissing(ctx,
          load: () async => const Commitments(roundsSet: false),
          save: (c) async {
            saved.add(c);
            return true;
          });
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('commitment-rounds')), '12');
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '20');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await done;
      expect(saved.single.rounds, 12);
      expect(saved.single.readingMinutes, 20);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('app open: complete commitments are never asked again', (tester) async {
      resetCommitmentPromptForTests();
      phone(tester, 1.0);
      late BuildContext ctx;
      await tester.pumpWidget(app(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      await askForCommitmentsIfMissing(ctx, load: () async => const Commitments(readingMinutes: 0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('before the FOLK form is saved: missing commitments are asked first, then the report saves', (tester) async {
      final saves = <int>[];
      final committed = <CommitmentChoice>[];
      phone(tester, 1.0);
      await tester.pumpWidget(app(QuestionsPage(
        loadCommitments: () async => const Commitments(roundsSet: false),
        saveCommitment: (c) async {
          committed.add(c);
          return true;
        },
        saveReport: (r, d, e) async => saves.add(r.chantRounds),
      )));
      await tester.pump();
      await fillFolk(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(saves, isEmpty, reason: 'nothing is saved before the commitments');
      expect(find.byKey(const ValueKey('commitment-rounds')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('commitment-rounds')), '16');
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '30');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      expect(committed.single.rounds, 16);
      expect(saves, [16], reason: 'the report is saved right after');
    });

    testWidgets('before the Hostel and Localite form is saved: the same', (tester) async {
      final saves = <int>[];
      phone(tester, 1.0);
      await tester.pumpWidget(app(SadhanaPage(
        loadCommitments: () async => const Commitments(roundsSet: false),
        saveCommitment: (c) async => true,
        saveReport: (r, d) async => saves.add(r.chantRounds),
      )));
      await tester.pump();
      await fillHostel(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(saves, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('commitment-rounds')), '16');
      await tester.enterText(find.byKey(const ValueKey('commitment-reading')), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      expect(saves, [16]);
    });
  });
}
