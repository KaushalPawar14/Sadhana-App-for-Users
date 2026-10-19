import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/BooksNotesPage.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/widgets/NotesHowItWorks.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Books -> Notes -> the "i" button: the "How notes work" sheet. Real fonts, text scale 1.0 / 1.3 / 1.6, light and dark.
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

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      home: home,
    );

Future<void> openNotes(WidgetTester tester, {double scale = 1.0, bool dark = false}) async {
  phone(tester, scale);
  await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: FakeFirebaseFirestore()), dark: dark));
  await settle(tester);
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('notes-how-button')));
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  testWidgets('an info "i" button sits at the top-right of the app bar, a 48 dp target', (tester) async {
    await openNotes(tester);
    final button = find.byKey(const ValueKey('notes-how-button'));
    expect(button, findsOneWidget);
    final r = tester.getRect(button);
    expect(r.width, greaterThanOrEqualTo(FolkShape.touchTarget));
    expect(r.height, greaterThanOrEqualTo(FolkShape.touchTarget));
    expect(r.right, greaterThan(360 - FolkSpace.pagePadding - 4), reason: 'top-right');
    expect(r.top, lessThan(100), reason: 'in the app bar');
    expect(find.descendant(of: button, matching: find.byIcon(Icons.info_outline_rounded)), findsOneWidget);
    expect(tester.getSemantics(button).label, 'How notes work');
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsNothing, reason: 'closed until tapped');
  });

  testWidgets('tapping it opens the sheet: the title, the five numbered steps, the three category chips, a Close button', (tester) async {
    await openNotes(tester);
    await openSheet(tester);
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsOneWidget);
    expect(find.text('How notes work'), findsOneWidget);
    expect(kNotesHowSteps.length, 5);
    for (var i = 0; i < 5; i++) {
      expect(find.text('${i + 1}'), findsOneWidget, reason: 'step number ${i + 1}');
    }
    // the wording of the steps (short, as specified)
    expect(find.textContaining('long-press any text to select it'), findsOneWidget);
    expect(find.textContaining('Choose Good, Excellent or Rare'), findsOneWidget);
    expect(find.textContaining('tap Highlight'), findsOneWidget);
    expect(find.textContaining('Tap a highlight to read or edit its note'), findsOneWidget);
    expect(find.textContaining('long-press it to resize or delete'), findsOneWidget);
    expect(find.textContaining('choose a category → a book → swipe through the numbered notes, or type a number to jump'), findsOneWidget);
    expect(find.textContaining('private — only you can see them'), findsOneWidget);
    // the three colours as small chips, in the Notes tiles' gradients, ink text
    for (final c in HighlightCategory.values) {
      final chip = find.byKey(ValueKey('notes-how-chip-${c.key}'));
      expect(chip, findsOneWidget);
      final deco = tester.widget<Container>(chip).decoration! as BoxDecoration;
      expect(deco.gradient, switch (c) {
        HighlightCategory.good => FolkGradients.saffron,
        HighlightCategory.excellent => FolkGradients.green,
        HighlightCategory.rare => FolkGradients.violet,
      });
      expect(tester.widget<Text>(find.descendant(of: chip, matching: find.text(c.label))).style!.color, FolkColors.onGradient);
    }
    expect(find.widgetWithText(PrimaryButton, 'Close'), findsOneWidget);
  });

  testWidgets('it closes: the Close button, a tap outside, and dragging down', (tester) async {
    await openNotes(tester);
    // Close button
    await openSheet(tester);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Close'));
    await settle(tester);
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsNothing);
    // tap outside (the dimmed area above the sheet)
    await openSheet(tester);
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsOneWidget);
    await tester.tapAt(const Offset(180, 20));
    await settle(tester);
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsNothing);
    // drag down
    await openSheet(tester);
    await tester.drag(find.text('How notes work'), const Offset(0, 500));
    await settle(tester);
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsNothing);
    // and it opens again afterwards
    await openSheet(tester);
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsOneWidget);
  });

  for (final scale in scales) {
    for (final dark in [false, true]) {
      testWidgets('the sheet at text scale $scale (${dark ? 'dark' : 'light'}): inside the screen, scrollable, Close reachable, no overflow', (tester) async {
        await openNotes(tester, scale: scale, dark: dark);
        await openSheet(tester);
        final sheet = tester.getRect(find.byKey(const ValueKey('notes-how-sheet')));
        expect(sheet.left, greaterThanOrEqualTo(0));
        expect(sheet.right, lessThanOrEqualTo(360));
        expect(sheet.bottom, lessThanOrEqualTo(800));
        expect(sheet.height, lessThanOrEqualTo(800 * .88 + 1), reason: 'never taller than 88% of the screen');
        // the steps scroll inside the sheet
        final scrollable = find.descendant(of: find.byKey(const ValueKey('notes-how-sheet')), matching: find.byType(SingleChildScrollView));
        expect(scrollable, findsOneWidget);
        await tester.drag(scrollable, const Offset(0, -2000));
        await tester.pump();
        expect(find.textContaining('private — only you can see them'), findsOneWidget);
        final close = tester.getRect(find.widgetWithText(PrimaryButton, 'Close'));
        expect(close.bottom, lessThanOrEqualTo(800));
        expect(close.height, greaterThanOrEqualTo(FolkShape.buttonHeight - 1));
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(PrimaryButton, 'Close'));
        await settle(tester);
        expect(find.byKey(const ValueKey('notes-how-sheet')), findsNothing);
      });
    }
  }

  testWidgets('the button is there while loading too (it needs no data)', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(BooksNotesPage(uid: 'u1', firestore: FakeFirebaseFirestore())));
    expect(find.byKey(const ValueKey('notes-how-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notes-how-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('notes-how-sheet')), findsOneWidget);
  });
}
