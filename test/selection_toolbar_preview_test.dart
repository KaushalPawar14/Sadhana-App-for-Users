import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/ReaderHighlights.dart';

import 'text_scale_test.dart' show loadAppFonts;

// Not a check: a picture of the floating selection toolbar for the designer, 360 dp wide, in Light, Dark and Sepia and
// at the largest text size.
//   PREVIEW=D:/folk-updates/tools/selection-toolbar-preview.png flutter test test/selection_toolbar_preview_test.dart
// Without PREVIEW it only checks that it renders.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  final out = Platform.environment['PREVIEW'];

  testWidgets('preview', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 4 * 262 + 3 * 8);
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey();

    Widget frame(BuildContext context, String mode, double scale) {
      final pal = kReaderPalettes[mode]!;
      final body = context.folkText.body.copyWith(fontSize: 17, height: 1.5, color: pal.text);
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: SizedBox(
          height: 262,
          child: Container(
            color: pal.background,
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Text.rich(
                  TextSpan(style: body, children: [
                    const TextSpan(text: 'Arjuna said: O Krsna, I see my own kinsmen arrayed here, and my limbs give way. '),
                    TextSpan(text: 'Whenever and wherever', style: TextStyle(backgroundColor: const Color(0xFFC38400).withValues(alpha: .35))),
                    const TextSpan(text: ' there is a decline in religious practice, I descend Myself.'),
                  ]),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(ReaderSelectionBar.sideMargin, 0, ReaderSelectionBar.sideMargin, ReaderSelectionBar.bottomGap),
                  child: ReaderSelectionBar(background: pal.chrome, onSentence: () {}, onParagraph: () {}, onCancel: () {}, onHighlight: () {}),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    await tester.pumpWidget(MaterialApp(
      theme: FolkTheme.light,
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          backgroundColor: const Color(0xFFDDDDDD),
          body: Builder(
            builder: (context) => Column(children: [
              frame(context, 'light', 1.0),
              const SizedBox(height: 8),
              frame(context, 'dark', 1.0),
              const SizedBox(height: 8),
              frame(context, 'sepia', 1.0),
              const SizedBox(height: 8),
              frame(context, 'light', 1.6),
            ]),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('selection-toolbar')), findsNWidgets(4));
    if (out == null) return;
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      File(out).writeAsBytesSync(bytes.buffer.asUint8List());
    });
  });
}
