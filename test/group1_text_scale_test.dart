import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/BookCardActions.dart';
import 'package:folk_app/widgets/FolkCard.dart';
import 'package:folk_app/widgets/FolkDialog.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/ReaderChrome.dart';
import 'package:folk_app/widgets/RoundIconButton.dart';

import 'text_scale_test.dart' show scales, host, expectNoClip, loadAppFonts;

// Phase 11b group 1: the pieces the Journey destinations are built from, at
// 360 dp and text scale 1.0 / 1.3 / 1.6. The screens themselves need Firebase,
// so each piece is rendered on its own with the screens' own labels.
// A real 360 x 800 dp phone screen with the system text scale set to [scale].
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final scale in scales) {
    final s = 'text scale $scale';

    group('Page shell (FolkScaffold) — $s at 360 dp', () {
      for (final title in ['My Books', 'RDUA Friends', 'A very long page title that cannot possibly fit on one line']) {
        testWidgets('title "$title" with two actions: one line, no overflow', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(MaterialApp(
            theme: FolkTheme.light,
            home: FolkScaffold(
              title: title,
              actions: [
                RoundIconButton(icon: Icons.person_add, semanticLabel: 'Add', onPressed: () {}),
                RoundIconButton(icon: Icons.refresh, semanticLabel: 'Refresh', onPressed: () {}),
              ],
              body: const Center(child: Text('body')),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          final t = tester.getRect(find.text(title));
          expect(t.left, greaterThanOrEqualTo(0));
          expect(t.right, lessThanOrEqualTo(360));
        });
      }
    });

    group('Book card buttons (BookCardActions) — $s at 360 dp', () {
      testWidgets('Read and Update, 48 dp tall at least, no overflow, no clipping', (tester) async {
        await tester.pumpWidget(host(
          FolkCard(
            child: BookCardActions(onRead: () {}, onUpdate: () {}),
          ),
          scale,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: s);
        expect(tester.getSize(find.byType(OutlinedButton)).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(find.byType(ElevatedButton)).height, greaterThanOrEqualTo(48));
        expectNoClip(tester, find.byType(OutlinedButton), reason: s);
        expectNoClip(tester, find.byType(ElevatedButton), reason: s);
      });
    });

    group('Reader chrome — $s at 360 dp', () {
      testWidgets('chapter strip with a bookmark wraps instead of overflowing', (tester) async {
        await tester.pumpWidget(host(
          const ReaderChapterStrip(
            background: Colors.white,
            textColor: Colors.black87,
            chapterLabel: 'Chapter 12 of 18',
            bookmarkLabel: 'Saved at ch 12 · para 34',
          ),
          scale,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: s);
        expectNoClip(tester, find.byType(ReaderChapterStrip), reason: s);
      });

      for (final label in ['Next Chapter  →', 'Finish Book', 'Reflection Questions and Practical Applications  →']) {
        testWidgets('gradient button "$label": at least 56 dp, label never clips', (tester) async {
          await tester.pumpWidget(host(
            ReaderGradientButton(
                label: label, onPressed: () {}, gradient: FolkGradients.violet),
            scale,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          expect(tester.getSize(find.byType(ReaderGradientButton)).height,
              greaterThanOrEqualTo(FolkShape.buttonHeight));
          expectNoClip(tester, find.byType(ReaderGradientButton), reason: s);
        });
      }

      testWidgets('hint pill and the loading variant of the button', (tester) async {
        await tester.pumpWidget(host(
          Column(children: [
            const ReaderPill(label: 'Tap a paragraph to bookmark'),
            ReaderGradientButton(
                label: 'Finish Book',
                onPressed: null,
                loading: true,
                gradient: FolkGradients.green),
          ]),
          scale,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: s);
        expectNoClip(tester, find.byType(ReaderPill), reason: s);
      });
    });

    group('Reader title bar (selection mode, two-line title) — $s at 360 dp', () {
      testWidgets('the bar height grows with the text and the title and hint never clip', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(MaterialApp(
          theme: FolkTheme.light,
          home: Builder(builder: (context) {
            final text = context.folkText;
            final scaler = MediaQuery.textScalerOf(context);
            // The same height rule as BookReaderPage.build.
            final toolbarHeight = math.max(
                kToolbarHeight, scaler.scale(16) * 1.5 + scaler.scale(11) * 1.5 + 12 + 16);
            return Scaffold(
              appBar: AppBar(
                toolbarHeight: toolbarHeight,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Beyond Birth and Death', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyStrong),
                    const SizedBox(height: 4),
                    const ReaderPill(label: 'Tap a paragraph to bookmark'),
                  ],
                ),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.text_fields)),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
                ],
              ),
            );
          }),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: s);
        final bar = tester.getRect(find.byType(AppBar));
        for (final t in [find.text('Beyond Birth and Death'), find.byType(ReaderPill)]) {
          final r = tester.getRect(t);
          expect(r.top, greaterThanOrEqualTo(bar.top));
          expect(r.bottom, lessThanOrEqualTo(bar.bottom));
        }
      });
    });

    group('Dialog (FolkDialog.alert) — $s at 360 dp', () {
      testWidgets('commitment-date style dialog: title, body, button, no overflow', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(MaterialApp(
          theme: FolkTheme.light,
          home: Builder(
            builder: (context) => FolkDialog.alert(
              context,
              title: 'Set your commitment date',
              content: const Text(
                  'Choose a target date to finish this book. This is required before you can start reading.'),
              actions: [
                ElevatedButton(onPressed: () {}, child: const Text('Start Reading')),
              ],
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: s);
      });
    });
  }
}
