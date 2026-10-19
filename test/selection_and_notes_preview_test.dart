import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BooksNotesPage.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/widgets/ReaderHighlights.dart';

import 'text_scale_test.dart' show loadAppFonts;

// Not a check: a picture of the compact selection bar (light / dark / sepia) and the Notes tiles, for the designer.
//   PREVIEW=D:/folk-updates/tools/selection-and-notes.png flutter test test/selection_and_notes_preview_test.dart
// Without PREVIEW it does nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  final out = Platform.environment['PREVIEW'];

  testWidgets('preview', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 640);
    addTearDown(tester.view.resetPhysicalSize);
    final fs = FakeFirebaseFirestore();
    Future<void> hl(String id, String book, String title, HighlightCategory c, int p) => fs.collection('bookHighlights').doc(id).set({
          'uid': 'u1', 'bookKey': book, 'level': 'level-1', 'bookTitle': title, 'chapterIndex': 0, 'startParagraph': p, 'startOffset': 0,
          'endParagraph': p, 'endOffset': 5, 'text': 'Hello', 'textLength': 5, 'snippetStart': 'Hello', 'snippetEnd': 'Hello', 'category': c.key, 'note': '',
        });
    for (var i = 0; i < 12; i++) {
      await hl('g$i', 'b${i % 3}', 'Book ${i % 3}', HighlightCategory.good, i);
    }
    await hl('e1', 'b1', 'Book 1', HighlightCategory.excellent, 40);
    final key = GlobalKey();
    Widget bar(String mode) => SizedBox(
          width: 230,
          child: Container(
            color: kReaderPalettes[mode]!.background,
            padding: const EdgeInsets.all(8),
            child: ReaderSelectionBar(background: kReaderPalettes[mode]!.chrome, onSentence: () {}, onParagraph: () {}, onCancel: () {}, onHighlight: () {}),
          ),
        );
    await tester.pumpWidget(MaterialApp(
      theme: FolkTheme.light,
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          body: Row(children: [
            Column(children: [for (final m in ['light', 'dark', 'sepia']) bar(m)]),
            SizedBox(width: 360, child: BooksNotesPage(uid: 'u1', firestore: fs)),
          ]),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    if (out == null) return;
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      File(out).writeAsBytesSync(bytes.buffer.asUint8List());
    });
  });
}
