import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/Group2Widgets.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The loading placeholder of the assistant History page (and the leaderboards):
// four 68 dp rows need about 320 dp, and the space under the tabs can be less
// (297.4 dp on the device that reported "overflowed by 23 pixels"). It must never
// overflow, at any height. Real app fonts are loaded.
const heights = [200.0, 297.0, 400.0, 800.0];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  void phone(WidgetTester tester, double h, double scale) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(360, h);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  Widget app(Widget home, bool dark) => MaterialApp(
        theme: dark ? FolkTheme.dark : FolkTheme.light,
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true), child: child!),
        home: home,
      );

  for (final dark in [false, true]) {
    for (final scale in scales) {
      for (final h in heights) {
        final s = '${dark ? 'dark' : 'light'}, text $scale, ${h.toInt()} dp tall';

        testWidgets('LeaderboardGhost (all row counts) never overflows — $s', (tester) async {
          phone(tester, 900, scale);
          for (final rows in [2, 3, 4, 5, 8]) {
            await tester.pumpWidget(app(
              Scaffold(body: Align(alignment: Alignment.topCenter, child: SizedBox(width: 360, height: h, child: LeaderboardGhost(rows: rows)))),
              dark,
            ));
            expect(tester.takeException(), isNull, reason: '$rows rows at $h');
            // clipped to its space, never taller than it
            expect(tester.getSize(find.byType(LeaderboardGhost)).height, h);
          }
        });

        testWidgets('History page loading and loaded states, whole page at this height — $s', (tester) async {
          phone(tester, h, scale);
          Widget page(Widget body) => FolkScaffold(
                title: 'History',
                bottom: const Padding(padding: EdgeInsets.only(top: 16), child: SizedBox(height: 44)),
                body: body,
              );
          // loading
          await tester.pumpWidget(app(page(const LeaderboardGhost(rows: 4)), dark));
          expect(tester.takeException(), isNull, reason: 'loading');
          // loaded: sessions, daily messages, and both empty states
          await tester.pumpWidget(app(
              page(ListView(children: [
                HistorySessionTile(label: 'Today', subtitle: 'What does Prabhupada say about the soul and the body?', onTap: () {}),
                const DailyHistoryCard(label: 'Today', text: 'You kept your promise. Keep going with attention.'),
              ])),
              dark));
          expect(tester.takeException(), isNull, reason: 'loaded');
          await tester.pumpWidget(app(page(const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No conversations yet.')))), dark));
          expect(tester.takeException(), isNull, reason: 'empty');
        });
      }
    }
  }

  testWidgets('the placeholder looks the same when there is room: four rows, same size and gaps', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const Scaffold(body: LeaderboardGhost(rows: 4)), false));
    final rows = find.descendant(of: find.byType(LeaderboardGhost), matching: find.byType(Container));
    expect(rows, findsWidgets);
    final first = tester.getRect(find.byType(Column).first);
    expect(first.left, 20, reason: 'same page padding as before');
    expect(first.top, 20);
    expect(first.width, 360 - 40);
    expect(first.height, 4 * (68 + 12), reason: '4 rows of 68 + a 12 gap each, as before');
  });
}
