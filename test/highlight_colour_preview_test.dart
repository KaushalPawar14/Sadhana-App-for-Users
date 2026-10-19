import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/utils/ReaderContrast.dart';

import 'text_scale_test.dart' show loadAppFonts;

// Draws the three highlight categories side by side, BEFORE and AFTER, in Light, Dark and Sepia, to look at.
//   PREVIEW=D:/folk-updates/tools/highlight-colours.png flutter test test/highlight_colour_preview_test.dart
// (skipped in a normal run)
class _Look {
  const _Look(this.name, this.border, this.glow, this.tintAlpha);
  final String name;
  final int border;
  final bool glow;
  final int tintAlpha;
}

const _before = [
  _Look('Good', 0xFFE2578A, false, 0x33), // the pink it was
  _Look('Excellent', 0xFF2FA55A, false, 0x33),
  _Look('Rare', 0xFFAE7DF3, true, 0x33),
];

Widget _chip(_Look l, String mode, {required bool after}) {
  final color = Color(l.border);
  final page = kReaderModeColors[mode]!;
  final tint = Color((l.border & 0x00FFFFFF) | (l.tintAlpha << 24));
  final glowAlpha = .3;
  final category = HighlightCategory.values.firstWhere((c) => c.label == l.name);
  final textColor = Color(readableOnHighlights(null, mode, {category}));
  return Container(
    margin: const EdgeInsets.all(5),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color, width: 1.3),
      boxShadow: l.glow ? [BoxShadow(color: color.withValues(alpha: glowAlpha), blurRadius: 7)] : null,
    ),
    child: Text(l.name, style: TextStyle(fontFamily: 'DM Sans', color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
  );
}

void main() {
  final out = Platform.environment['PREVIEW'];
  setUpAll(loadAppFonts);
  testWidgets('preview: before and after, all three categories, each reading mode', skip: out == null, (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1800, 760);
    addTearDown(tester.view.resetPhysicalSize);
    final after = [
      for (final c in HighlightCategory.values) _Look(c.label, c.argb, c.glows, c.tintArgb >> 24),
    ];
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Container(
          color: Colors.grey.shade300,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in ['light', 'dark', 'sepia'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final isAfter in [false, true])
                      Container(
                        width: 410,
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.all(10),
                        color: Color(kReaderModeColors[mode]!.background),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${mode.toUpperCase()} - ${isAfter ? 'AFTER' : 'BEFORE'}',
                                style: TextStyle(fontFamily: 'DM Sans', color: Color(kReaderModeColors[mode]!.secondaryText), fontSize: 12, fontWeight: FontWeight.w700)),
                            Row(children: [for (final l in (isAfter ? after : _before)) _chip(l, mode, after: isAfter)]),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    if (out == null) return;
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      File(out).writeAsBytesSync(bytes.buffer.asUint8List());
    });
  });
}
