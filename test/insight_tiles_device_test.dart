import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/InsightTile.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The Insights tiles as they render on a real phone: logical 360x800 and 393x873
// at devicePixelRatio 2.75, with the bundled Bricolage Grotesque and DM Sans
// loaded (FontLoader, `loadAppFonts`). Each title must be shown IN FULL: as wide
// as the tile allows, never cut to a letter, at most 2 lines, no word broken in
// the middle, and starting at the same place in all five tiles.
//
// (An earlier version of these checks measured positions only, so a title that
// was one letter wide still passed. These measure the title's width and read the
// paragraph itself.)
void realPhone(WidgetTester tester, Size logical, double scale) {
  tester.view.devicePixelRatio = 2.75;
  tester.view.physicalSize = Size(logical.width * 2.75, logical.height * 2.75);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

const titles = ['Leaderboard', 'Weekly Performance', 'Monthly Performance', 'Best Performer'];

Finder tile(String title) => find.byWidgetPredicate((w) => w is InsightTile && w.title == title);

Finder titleOf(String t) => find.descendant(of: tile(t), matching: find.byKey(const ValueKey('insight-tile-title')));

double textWidth(String s, TextStyle style, double scale) {
  final p = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  return p.width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final size in const [Size(360, 800), Size(393, 873)]) {
    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()} @2.75, ${dark ? 'dark' : 'light'}, text $scale: every title is shown in full', (tester) async {
          realPhone(tester, size, scale);
          await tester.pumpWidget(MaterialApp(
            theme: dark ? FolkTheme.dark : FolkTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: CompetitionPage(role: 'Stay at FOLK', username: 'Asha', loadReports: (_) async => {}),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final starts = <double>{};
          for (final t in titles) {
            await tester.scrollUntilVisible(tile(t), 200, scrollable: find.byType(Scrollable).first);
            await tester.ensureVisible(tile(t));
            await tester.pump();
            final box = tester.getRect(tile(t));
            final title = titleOf(t);
            final text = tester.widget<Text>(title);
            final r = tester.getRect(title);

            // 1. the title gets the tile's full inner width (it used to be ONE LETTER wide)
            expect(r.width, closeTo(box.width - 32, 1), reason: '$t: title is ${r.width} dp wide, the tile has ${box.width - 32}');
            // 2. it is not cut: the paragraph has at most 2 lines and did not exceed them
            final para = tester.renderObject<RenderParagraph>(title);
            expect(para.didExceedMaxLines, isFalse, reason: '$t was cut');
            final tops = para
                .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.data!.length))
                .map((b) => b.top.round())
                .toSet();
            expect(tops.length, lessThanOrEqualTo(2), reason: '$t is on ${tops.length} lines');
            // 3. no word is broken in the middle: the widest word fits on a line
            final effective = scale > InsightTile.maxTitleScale ? InsightTile.maxTitleScale : scale;
            for (final word in text.data!.split(' ')) {
              expect(textWidth(word, text.style!, effective), lessThanOrEqualTo(r.width + .5), reason: '$t: "$word" must fit on one line');
            }
            // 4. the whole title is inside its tile
            expect(r.bottom, lessThanOrEqualTo(box.bottom - 8), reason: t);
            starts.add(double.parse((r.top - box.top).toStringAsFixed(1)));
          }
          expect(starts.length, 1, reason: 'the same start position in all four tiles: $starts');
        });
      }
    }
  }
}
