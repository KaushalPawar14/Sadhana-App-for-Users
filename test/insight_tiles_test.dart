import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/InsightTile.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The five Insights tiles: one title style, one layout, titles starting at the
// same place in every tile.
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

const titles = ['Leaderboard', 'Weekly Performance', 'Monthly Performance', 'Best Performer'];

Future<void> pump(WidgetTester tester, {double scale = 1.0, bool dark = false, bool reduce = true, String role = 'Stay at FOLK'}) async {
  phone(tester, scale);
  await tester.pumpWidget(MaterialApp(
    theme: dark ? FolkTheme.dark : FolkTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: child!,
    ),
    home: CompetitionPage(role: role, username: 'Asha', loadReports: (_) async => {}),
  ));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Best Performer'), 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Finder tile(String title) => find.byWidgetPredicate((w) => w is InsightTile && w.title == title);

Finder titleOf(String t) => find.descendant(of: tile(t), matching: find.byKey(const ValueKey('insight-tile-title')));

Finder subtitleOf(String t) => find.descendant(of: tile(t), matching: find.byKey(const ValueKey('insight-tile-subtitle')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale: same title size, same title and subtitle position in all four tiles, no overflow', (tester) async {
        await pump(tester, scale: scale, dark: dark);
        expect(tester.takeException(), isNull, reason: 'dark=$dark scale=$scale');

        final sizes = <double>{};
        final titleOffsets = <double>{};
        final subtitleOffsets = <double>{};
        for (final t in titles) {
          await tester.ensureVisible(tile(t));
          await tester.pump();
          expect(tile(t), findsOneWidget);
          final box = tester.getRect(tile(t));
          final text = tester.widget<Text>(titleOf(t));
          sizes.add(text.style!.fontSize!);
          titleOffsets.add(double.parse((tester.getTopLeft(titleOf(t)).dy - box.top).toStringAsFixed(1)));
          subtitleOffsets.add(double.parse((tester.getTopLeft(subtitleOf(t)).dy - box.top).toStringAsFixed(1)));
          expect(text.maxLines, 2, reason: t);
          // no per-tile scaling to fit
          expect(find.descendant(of: tile(t), matching: find.byType(FittedBox)), findsNothing, reason: t);
          // the title stays inside its tile
          final r = tester.getRect(titleOf(t));
          expect(r.left, greaterThanOrEqualTo(box.left + 15.5), reason: t);
          expect(r.right, lessThanOrEqualTo(box.right - 15.5), reason: t);
          expect(r.bottom, lessThanOrEqualTo(box.bottom + .5), reason: t);
        }
        expect(sizes.length, 1, reason: 'one font size for every title: $sizes');
        expect(sizes.single, 18, reason: 'the tileTitle token (FolkTypography), one size for all four');
        expect(titleOffsets.length, 1, reason: 'every title starts at the same offset from the top of its tile: $titleOffsets');
        expect(subtitleOffsets.length, 1, reason: 'and every subtitle: $subtitleOffsets');
      });
    }
  }

  testWidgets('the wide Leaderboard tile has the same title and subtitle positions and the same styles', (tester) async {
    await pump(tester);
    await tester.ensureVisible(tile('Leaderboard'));
    await tester.pump();
    final wide = tester.getRect(tile('Leaderboard'));
    expect(wide.width, 320);
    final square = tester.getRect(tile('Weekly Performance'));
    expect(tester.getTopLeft(titleOf('Leaderboard')).dx - wide.left, tester.getTopLeft(titleOf('Weekly Performance')).dx - square.left);
    expect(tester.widget<Text>(titleOf('Leaderboard')).style, tester.widget<Text>(titleOf('Weekly Performance')).style);
    expect(tester.widget<Text>(subtitleOf('Leaderboard')).style, tester.widget<Text>(subtitleOf('Weekly Performance')).style);
  });

  testWidgets('layout: icon circle top-left in every tile; tiles at least as tall as a square; equal squares in a row; Best Performer wide', (tester) async {
    await pump(tester);
    for (final t in titles) {
      await tester.ensureVisible(tile(t));
      await tester.pump();
      final box = tester.getRect(tile(t));
      expect(box.height, greaterThanOrEqualTo(154 - .5), reason: t);
      final icon = tester.getRect(find.descendant(of: tile(t), matching: find.byType(Container)).at(1));
      expect(icon.left - box.left, closeTo(16, 1), reason: '$t: icon circle at the top left');
      expect(icon.top - box.top, closeTo(16, 1), reason: t);
    }
    expect(tester.getRect(tile('Weekly Performance')).height, closeTo(tester.getRect(tile('Monthly Performance')).height, .5));
    // Best Performer is a full-width card like the Leaderboard one
    expect(tester.getRect(tile('Best Performer')).width, 320);
    expect(tester.getRect(tile('Best Performer')).height, greaterThanOrEqualTo(154 - .5));
  });

  testWidgets('no colour change: the gradients are as before', (tester) async {
    await pump(tester);
    final styles = {for (final t in titles) t: tester.widget<InsightTile>(tile(t)).style.name};
    expect(styles, {
      'Leaderboard': 'saffron',
      'Weekly Performance': 'green',
      'Monthly Performance': 'coral',
      'Best Performer': 'violet',
    });
  });
}
