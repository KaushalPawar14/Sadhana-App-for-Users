import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journey_mosaic_test.dart' show host, mosaic, phone;
import 'text_scale_test.dart' show loadAppFonts;

// Cost of the Journey mosaic's IntrinsicHeight rows: the whole mosaic (three
// rows, two of them with a stacked pair) laid out again and again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  testWidgets('re-laying out the whole mosaic costs well under a frame', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host((c) => mosaic(c), reduce: true));
    await tester.pumpAndSettle();
    final root = tester.binding.renderViews.first;
    const runs = 200;
    final watch = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      tester.renderObject(find.byType(Column).first).markNeedsLayout();
      await tester.pump();
    }
    watch.stop();
    final perLayoutMs = watch.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('mosaic full layout + frame: ${perLayoutMs.toStringAsFixed(2)} ms average over $runs runs (debug, test VM); root ${root.runtimeType}');
    expect(perLayoutMs, lessThan(16));
  });
}
