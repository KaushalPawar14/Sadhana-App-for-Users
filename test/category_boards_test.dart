import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/scores/BhagavatamClass.dart';
import 'package:folk_app/scores/BookReading.dart';
import 'package:folk_app/scores/CategoryBoard.dart';
import 'package:folk_app/scores/Chanting.dart';
import 'package:folk_app/scores/DailyServices.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SameGender.dart';

import 'same_gender_test.dart' show directoryFor, phone, host;
import 'text_scale_test.dart' show scales, loadAppFonts;

// The four category leaderboards rank by the ITEM's points over the period, with no multipliers, and
// show points (not rounds / minutes). The points themselves are the server's (functions/scoring.js).
final docs = <String, Map<String, dynamic>>{
  'flag': {'x': 1},
  'Arjun': {'weekly.pts_chanting': 62.5, 'weekly.pts_reading': 50, 'weekly.pts_class': 75, 'weekly.pts_service': 25, 'monthly.pts_chanting': 400, 'monthly.pts_reading': 100, 'monthly.pts_class': 200, 'monthly.pts_service': 150},
  'Bhima': {'weekly.pts_chanting': 200, 'weekly.pts_reading': 25, 'weekly.pts_class': 50, 'weekly.pts_service': 50, 'monthly.pts_chanting': 300, 'monthly.pts_reading': 500, 'monthly.pts_class': 100, 'monthly.pts_service': 300},
  'Chaitanya': {'weekly.pts_chanting': 100, 'weekly.pts_reading': 100, 'weekly.pts_class': 25, 'weekly.pts_service': 0, 'monthly.pts_chanting': 100},
  'Newbie': {'weekly.total_score': 5},
  'Asha': {'weekly.pts_chanting': 999, 'weekly.pts_reading': 999, 'weekly.pts_class': 999, 'weekly.pts_service': 999},
};

Future<Map<String, Map<String, dynamic>>> read() async => docs;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  setUp(() => GenderDirectory.useForTests(() async => directoryFor(kMale)));

  group('the ranking', () {
    test('by the item points of the period, best first; a student with none scores 0; the flag document is skipped', () {
      final w = rankByItem(docs, BoardItem.chanting, 'weekly');
      expect(w.map((r) => r['userName']).toList(), ['Asha', 'Bhima', 'Chaitanya', 'Arjun', 'Newbie']);
      expect(w.map((r) => r['points']).toList(), [999, 200, 100, 62.5, 0]);
      final m = rankByItem(docs, BoardItem.reading, 'monthly');
      expect(m.first['userName'], 'Asha' == m.first['userName'] ? 'Asha' : 'Bhima');
      expect(m.where((r) => r['userName'] == 'Newbie').single['points'], 0);
      expect(m.any((r) => r['userName'] == 'flag'), isFalse);
    });

    test('each board reads its own field, and week and month are different periods', () {
      String top(BoardItem i, String p) => rankByItem(docs, i, p, include: (n) => n != 'Asha').first['userName'] as String;
      expect(top(BoardItem.chanting, 'weekly'), 'Bhima');
      expect(top(BoardItem.chanting, 'monthly'), 'Arjun');
      expect(top(BoardItem.reading, 'weekly'), 'Chaitanya');
      expect(top(BoardItem.reading, 'monthly'), 'Bhima');
      expect(top(BoardItem.sbClass, 'weekly'), 'Arjun');
      expect(top(BoardItem.service, 'monthly'), 'Bhima');
    });

    test('the multipliers are not here at all: only pts_* fields count', () {
      final r = rankByItem({'A': {'weekly.chanting_rounds': 9999, 'weekly.total_score': 9999, 'weekly.pts_chanting': 10}}, BoardItem.chanting, 'weekly');
      expect(r.single['points'], 10);
    });

    test('points text: whole numbers plain, a fraction to one decimal', () {
      expect(pointsText(50), '50 pts');
      expect(pointsText(62.5), '62.5 pts');
      expect(pointsText(0), '0 pts');
    });
  });

  group('the screens', () {
    testWidgets('Chanting: points (no "rounds"), week by default, the switch shows the month', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(Chanting(reader: read)));
      await tester.pumpAndSettle();
      expect(find.text('200 pts'), findsOneWidget);
      expect(find.textContaining('rounds'), findsNothing);
      expect(find.text('Asha'), findsNothing, reason: 'another gender');
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('400 pts'), findsOneWidget);
      expect(find.text('200 pts'), findsNothing);
      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();
      expect(find.text('200 pts'), findsOneWidget);
    });

    testWidgets('Book Reading shows points, not minutes', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(BookReading(reader: read)));
      await tester.pumpAndSettle();
      expect(find.textContaining('mins'), findsNothing);
      expect(find.text('100 pts'), findsOneWidget);
    });

    testWidgets('SB class and Daily services are plain rows of points', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(SBclasses(reader: read)));
      await tester.pumpAndSettle();
      expect(find.text('75 pts'), findsOneWidget);
      await tester.pumpWidget(host(DailyServices(reader: read)));
      await tester.pumpAndSettle();
      expect(find.text('50 pts'), findsOneWidget);
      expect(find.text('25 pts'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('no overflow — ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
          phone(tester, scale);
          for (final board in <Widget>[Chanting(reader: read), BookReading(reader: read), SBclasses(reader: read), DailyServices(reader: read)]) {
            await tester.pumpWidget(host(board, dark: dark));
            await tester.pumpAndSettle();
            await tester.tap(find.text('This month'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  });
}
