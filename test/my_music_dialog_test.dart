import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/MyMusicPage.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/MusicData.dart';
import 'package:folk_app/utils/ReaderContrast.dart' show contrastRatio;
import 'package:folk_app/widgets/FolkChip.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// My Music -> Others: the add / edit dialog is the app's standard dialog (FolkDialog): the themed surface (never the SDK's
// white scrim colour in dark mode), a filled field, the level as theme chips, the main button style and a quiet Cancel;
// every text >= 4.5:1; the same at text 1.0 / 1.3 / 1.6, light and dark; the REAL pixels of the dialog follow the theme.
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

Future<GlobalKey> openDialog(WidgetTester tester, {required bool dark, double scale = 1.0, bool existing = false, bool remove = false}) async {
  phone(tester, scale);
  final db = FakeFirebaseFirestore();
  if (existing || remove) {
    await db.doc('musicProgress/u1').set({
      'uid': 'u1',
      'others': [
        {'id': 'o1', 'name': 'Flute', 'level': 'intermediate'},
      ],
    });
  }
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: MyMusicPage(store: FirestoreMusicStore(db), uid: 'u1', openLink: (_) async => true),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  final Finder trigger = remove
      ? find.byKey(const ValueKey('music-delete-o1'))
      : existing
          ? find.byKey(const ValueKey('music-edit-o1'))
          : find.byKey(const ValueKey('music-add-other'));
  await tester.scrollUntilVisible(trigger, 200, scrollable: find.descendant(of: find.byKey(const ValueKey('music-list')), matching: find.byType(Scrollable)).first);
  await tester.tap(trigger);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return key;
}

Future<ByteData> pixels(WidgetTester tester, GlobalKey key) async {
  late ByteData data;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return data;
}

int pixelAt(ByteData d, int x, int y) {
  final i = (y * 360 + x) * 4;
  return (0xFF << 24) | (d.getUint8(i) << 16) | (d.getUint8(i + 1) << 8) | d.getUint8(i + 2);
}

bool near(int a, int b, [int tol = 4]) => ((a >> 16 & 255) - (b >> 16 & 255)).abs() <= tol && ((a >> 8 & 255) - (b >> 8 & 255)).abs() <= tol && ((a & 255) - (b & 255)).abs() <= tol;

int argb(Color c) => c.toARGB32();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    final colors = dark ? FolkColors.dark : FolkColors.light;

    testWidgets('$mode: the dialog surface IS the theme surface (real pixels), and is not the white scrim colour in dark mode', (tester) async {
      final key = await openDialog(tester, dark: dark);
      final rect = tester.getRect(find.descendant(of: find.byKey(const ValueKey('music-other-dialog')), matching: find.byType(Material)).first);
      final data = await pixels(tester, key);
      // a few pixels inside the dialog's top-left corner (clear of the rounded corner and of any text)
      final sample = pixelAt(data, (rect.left + 14).round(), (rect.top + 14).round());
      expect(near(sample, argb(colors.surface)), isTrue, reason: '$mode: dialog pixel ${sample.toRadixString(16)} vs surface ${argb(colors.surface).toRadixString(16)}');
      if (dark) {
        final r = sample >> 16 & 255, g = sample >> 8 & 255, b = sample & 255;
        expect(r < 120 && g < 120 && b < 120, isTrue, reason: 'no white box in dark mode');
      }
      // and the field inside it is the filled secondary surface
      final field = tester.getRect(find.byKey(const ValueKey('music-other-name')));
      final fieldPixel = pixelAt(data, (field.left + 10).round(), (field.center.dy).round());
      expect(near(fieldPixel, argb(colors.surfaceSecondary)), isTrue, reason: 'the filled input field');
    });

    testWidgets('$mode: the standard dialog component: surface colour, radius 28, no surface tint', (tester) async {
      await openDialog(tester, dark: dark);
      final dialog = tester.widget<AlertDialog>(find.byKey(const ValueKey('music-other-dialog')));
      expect(dialog.backgroundColor, colors.surface);
      expect(dialog.surfaceTintColor, Colors.transparent);
      expect((dialog.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(FolkShape.cardRadius));
      expect(dialog.scrollable, isTrue);
    });

    testWidgets('$mode: level as three theme chips (Basic / Intermediate / Expert), one selected; tapping changes the selection', (tester) async {
      await openDialog(tester, dark: dark);
      expect(find.byType(FolkChip), findsNWidgets(3));
      FolkChip chip(String k) => tester.widget<FolkChip>(find.byKey(ValueKey('music-level-$k')));
      expect(chip('basic').selected, isTrue, reason: 'Basic is the default');
      expect(chip('intermediate').selected, isFalse);
      await tester.tap(find.byKey(const ValueKey('music-level-expert')));
      await tester.pump();
      expect(chip('expert').selected, isTrue);
      expect(chip('basic').selected, isFalse);
      for (final k in ['basic', 'intermediate', 'expert']) {
        expect(tester.getSize(find.byKey(ValueKey('music-level-$k'))).height, greaterThanOrEqualTo(FolkShape.touchTarget - .5), reason: '$k: 48 dp target');
      }
    });

    testWidgets('$mode: buttons: Save is the main button (primary background, ink text), Cancel is quiet; both >= 48 dp', (tester) async {
      await openDialog(tester, dark: dark);
      final save = tester.widget<ElevatedButton>(find.byKey(const ValueKey('music-other-save')));
      final bg = save.style!.backgroundColor!.resolve({});
      final fg = save.style!.foregroundColor!.resolve({});
      expect(bg, colors.primaryBg);
      expect(fg, colors.primaryFg);
      final cancel = tester.widget<TextButton>(find.byKey(const ValueKey('music-other-cancel')));
      expect(cancel.style!.foregroundColor!.resolve({}), colors.mutedText, reason: 'quiet');
      for (final k in ['music-other-save', 'music-other-cancel']) {
        expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(FolkShape.touchTarget - .5), reason: k);
      }
    });

    testWidgets('$mode: every text on it is >= 4.5:1 (title, field text, label, hint, error, chips, buttons)', (tester) async {
      await openDialog(tester, dark: dark);
      double ratio(Color text, Color bg) => contrastRatio(argb(text), argb(bg));
      // title and body text on the dialog surface
      expect(ratio(colors.text, colors.surface), greaterThanOrEqualTo(4.5), reason: 'title');
      expect(ratio(colors.mutedText, colors.surface), greaterThanOrEqualTo(4.5), reason: 'caption "Your level" and the quiet Cancel');
      // the typed text, the label, the hint and the error text on the filled field
      expect(ratio(colors.text, colors.surfaceSecondary), greaterThanOrEqualTo(4.5), reason: 'typed text');
      expect(ratio(colors.mutedText, colors.surfaceSecondary), greaterThanOrEqualTo(4.5), reason: 'label and hint');
      expect(ratio(colors.calendarMissedText, colors.surfaceSecondary), greaterThanOrEqualTo(4.5), reason: 'error text');
      // chips and the main button
      expect(ratio(colors.primaryFg, colors.primaryBg), greaterThanOrEqualTo(4.5), reason: 'selected chip and Save');
      expect(ratio(colors.text, colors.surfaceSecondary), greaterThanOrEqualTo(4.5), reason: 'unselected chips');
      // and the real widgets use exactly those colours
      final tf = tester.widget<TextField>(find.byKey(const ValueKey('music-other-name')));
      expect(tf.style!.color, colors.text);
      expect(tf.decoration!.fillColor, colors.surfaceSecondary);
    });

    testWidgets('$mode: an empty name shows the error in the theme\'s error colour, the dialog stays', (tester) async {
      await openDialog(tester, dark: dark);
      await tester.tap(find.byKey(const ValueKey('music-other-save')));
      await tester.pump();
      expect(find.text('Please write the instrument'), findsOneWidget);
      final tf = tester.widget<TextField>(find.byKey(const ValueKey('music-other-name')));
      expect(tf.decoration!.errorStyle!.color, colors.calendarMissedText);
      expect(find.byKey(const ValueKey('music-other-dialog')), findsOneWidget);
    });

    testWidgets('$mode: the remove-confirmation dialog is the same standard dialog (themed surface, no white box)', (tester) async {
      final key = await openDialog(tester, dark: dark, remove: true);
      expect(find.byKey(const ValueKey('music-remove-dialog')), findsOneWidget);
      final dialog = tester.widget<AlertDialog>(find.byKey(const ValueKey('music-remove-dialog')));
      expect(dialog.backgroundColor, colors.surface);
      expect(dialog.surfaceTintColor, Colors.transparent);
      final rect = tester.getRect(find.descendant(of: find.byKey(const ValueKey('music-remove-dialog')), matching: find.byType(Material)).first);
      final data = await pixels(tester, key);
      expect(near(pixelAt(data, (rect.left + 14).round(), (rect.top + 14).round()), argb(colors.surface)), isTrue);
    });

    for (final scale in scales) {
      testWidgets('$mode, text $scale: add and edit fit (360 dp), the dialog scrolls, nothing overflows, targets >= 48 dp', (tester) async {
        await openDialog(tester, dark: dark, scale: scale);
        expect(tester.takeException(), isNull);
        var box = tester.getRect(find.byKey(const ValueKey('music-other-dialog')));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(360));
        expect(box.bottom, lessThanOrEqualTo(800));
        for (final k in ['music-other-save', 'music-other-cancel', 'music-level-basic', 'music-level-intermediate', 'music-level-expert']) {
          await tester.ensureVisible(find.byKey(ValueKey(k)));
          final r = tester.getRect(find.byKey(ValueKey(k)));
          expect(r.right, lessThanOrEqualTo(360.5), reason: k);
          expect(r.height, greaterThanOrEqualTo(FolkShape.touchTarget - .5), reason: k);
        }
        // the chips wrap onto more lines when they do not fit one row (never overflow)
        final basic = tester.getRect(find.byKey(const ValueKey('music-level-basic')));
        final expert = tester.getRect(find.byKey(const ValueKey('music-level-expert')));
        expect(basic.left, lessThanOrEqualTo(expert.right), reason: 'sane layout');
        await tester.tap(find.byKey(const ValueKey('music-other-cancel')));
        await tester.pump(const Duration(milliseconds: 300));
        // edit: prefilled
        await openDialog(tester, dark: dark, scale: scale, existing: true);
        expect(tester.takeException(), isNull);
        expect(find.text('Edit instrument'), findsOneWidget);
        expect(tester.widget<TextField>(find.byKey(const ValueKey('music-other-name'))).controller!.text, 'Flute');
        expect(tester.widget<FolkChip>(find.byKey(const ValueKey('music-level-intermediate'))).selected, isTrue);
        box = tester.getRect(find.byKey(const ValueKey('music-other-dialog')));
        expect(box.right, lessThanOrEqualTo(360));
      });
    }
  }

  testWidgets('with animations on, the dialog opens and closes smoothly (no exception, ends in place)', (tester) async {
    phone(tester, 1.0);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(MaterialApp(theme: FolkTheme.dark, home: MyMusicPage(store: FirestoreMusicStore(db), uid: 'u1')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.byKey(const ValueKey('music-add-other')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('music-other-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('music-other-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('music-other-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
