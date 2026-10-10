import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/JourneyMosaic.dart';
import 'package:folk_app/widgets/SadhanaStatTile.dart';

import 'journey_mosaic_test.dart' show host, mosaic;
import 'text_scale_test.dart' show scales, loadAppFonts;

// The Journey mosaic and the Sadhana tiles as they render on a real phone (logical
// 360x800 and 393x873 at devicePixelRatio 2.75, the bundled fonts loaded): every
// title / number is drawn in full, none squeezed to a sliver or cut.
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

// A text is drawn in full when its paragraph did not exceed its lines and, if it
// sits in a FittedBox, the box scales it down by no more than 40 %.
void expectDrawnInFull(WidgetTester tester, Finder text, String reason) {
  final para = tester.renderObject<RenderParagraph>(text);
  expect(para.didExceedMaxLines, isFalse, reason: '$reason was cut');
  expect(para.size.width, greaterThan(para.text.toPlainText().length * 2.0), reason: '$reason is only ${para.size.width} dp wide');
  final fitted = find.ancestor(of: text, matching: find.byType(FittedBox));
  if (fitted.evaluate().isNotEmpty) {
    final box = tester.renderObject<RenderFittedBox>(fitted.first);
    final inner = box.child!.size;
    final outer = box.size;
    if (inner.width > outer.width) {
      expect(outer.width / inner.width, greaterThanOrEqualTo(.6), reason: '$reason is scaled down to ${(outer.width / inner.width * 100).round()}%');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final size in const [Size(360, 800), Size(393, 873)]) {
    for (final dark in [false, true]) {
      for (final scale in scales) {
        final s = '${size.width.toInt()}x${size.height.toInt()} @2.75, ${dark ? 'dark' : 'light'}, text $scale';

        testWidgets('Journey mosaic titles in full — $s', (tester) async {
          realPhone(tester, size, scale);
          await tester.pumpWidget(host((c) => mosaic(c), dark: dark, reduce: true));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final t in tester.widgetList<JourneyTile>(find.byType(JourneyTile))) {
            final tile = find.byWidget(t);
            // the title is the Text(s) inside the tile's FittedBox column
            final titleTexts = find.descendant(of: tile, matching: find.descendant(of: find.byType(FittedBox), matching: find.byType(Text)));
            for (final e in titleTexts.evaluate()) {
              expectDrawnInFull(tester, find.byWidget(e.widget), '${t.title} / ${(e.widget as Text).data}');
            }
          }
        });

        testWidgets('Sadhana tiles in full — $s', (tester) async {
          realPhone(tester, size, scale);
          await tester.pumpWidget(host(
            (c) => const IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: SadhanaStatTile(style: FolkGradientStyle.saffron, value: 14, suffix: 'of 21', caption: 'days submitted')),
                  SizedBox(width: 12),
                  Expanded(child: SadhanaStatTile(style: FolkGradientStyle.green, value: 112, suffix: 'days', caption: 'current streak')),
                ],
              ),
            ),
            dark: dark,
            reduce: true,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final text in ['14', 'of 21', '112', 'days', 'days submitted', 'current streak']) {
            expectDrawnInFull(tester, find.text(text), text);
          }
        });
      }
    }
  }
}
