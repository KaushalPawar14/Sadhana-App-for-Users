import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/GradientCard.dart';
import 'package:folk_app/widgets/ProfileNameCard.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The guide is a line INSIDE the sky-blue name card, directly under the category: "Guide: <name>" or "Guide: Not assigned
// yet" (the "My Guide" row is gone from the list). Same instant source as before (the stamped name + the phone's copy), so
// the line needs no loading; long names wrap to two lines then end with an ellipsis; the card grows to fit.
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

Widget host(Widget card, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(FolkSpace.pagePadding), child: Column(children: [card]))),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  test('the line reads "Guide: NAME", or "Guide: Not assigned yet" for no guide (empty, blank or null)', () {
    expect(guideLineText('Amit Das'), 'Guide: Amit Das');
    expect(guideLineText('  Amit Das '), 'Guide: Amit Das');
    expect(guideLineText(''), 'Guide: Not assigned yet');
    expect(guideLineText('   '), 'Guide: Not assigned yet');
    expect(guideLineText(null), 'Guide: Not assigned yet');
  });

  group('inside the name card, directly under the category', () {
    testWidgets('name, category, then the guide line - all inside the one sky-blue card', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const ProfileNameCard(name: 'Kaushal Pawar', role: 'Stay at Hostel', guideName: 'Amit Das')));
      expect(find.byType(GradientCard), findsOneWidget, reason: 'one card');
      final card = find.byType(GradientCard);
      for (final k in ['profile-name', 'profile-category', 'profile-guide-line']) {
        expect(find.descendant(of: card, matching: find.byKey(ValueKey(k))), findsOneWidget, reason: '$k is inside the card');
      }
      expect(find.text('Stay at Hostel'), findsOneWidget);
      expect(find.text('Guide: Amit Das'), findsOneWidget);
      final name = tester.getRect(find.byKey(const ValueKey('profile-name')));
      final role = tester.getRect(find.byKey(const ValueKey('profile-category')));
      final guide = tester.getRect(find.byKey(const ValueKey('profile-guide-line')));
      expect(role.top, greaterThanOrEqualTo(name.bottom - .5));
      expect(guide.top, greaterThanOrEqualTo(role.bottom - .5), reason: 'directly under the category line');
      expect(guide.top - role.bottom, lessThan(8), reason: 'right under it, not detached');
      expect(guide.left, role.left, reason: 'aligned with the category');
      final text = tester.widget<Text>(find.byKey(const ValueKey('profile-guide-line')));
      final cat = tester.widget<Text>(find.byKey(const ValueKey('profile-category')));
      expect(text.style, cat.style, reason: 'the same secondary text style as the category');
    });

    testWidgets('no guide: "Guide: Not assigned yet"', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const ProfileNameCard(name: 'Kaushal Pawar', role: 'Stay at FOLK', guideName: '')));
      expect(find.text('Guide: Not assigned yet'), findsOneWidget);
    });

    testWidgets('the line follows the name at once when it changes (no loading state)', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const ProfileNameCard(name: 'A', role: 'Stay at FOLK', guideName: '')));
      expect(find.text('Guide: Not assigned yet'), findsOneWidget);
      await tester.pumpWidget(host(const ProfileNameCard(name: 'A', role: 'Stay at FOLK', guideName: 'Radha Devi')));
      expect(find.text('Guide: Radha Devi'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text $scale: short and very long names fit, the card grows, nothing overflows', (tester) async {
          phone(tester, scale);
          const long = 'Shri Bhaktivedanta Swami Prabhupada Dasanudas Brahmachari of the Surat Temple';
          await tester.pumpWidget(host(const ProfileNameCard(name: 'Kaushal', role: 'Stay at Hostel', guideName: 'Amit'), dark: dark));
          expect(tester.takeException(), isNull);
          final shortHeight = tester.getSize(find.byType(GradientCard)).height;
          await tester.pumpWidget(host(const ProfileNameCard(name: 'Kaushal Pawar Kumar Singh Rathore', role: 'Stay at Hostel', guideName: long), dark: dark));
          expect(tester.takeException(), isNull, reason: 'a long guide name does not overflow');
          final guide = tester.getRect(find.byKey(const ValueKey('profile-guide-line')));
          final card = tester.getRect(find.byType(GradientCard));
          expect(guide.right, lessThanOrEqualTo(card.right), reason: 'inside the card');
          expect(guide.bottom, lessThanOrEqualTo(card.bottom), reason: 'the card grew to hold it');
          final lines = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('profile-guide-line')));
          expect(lines.didExceedMaxLines, isTrue, reason: 'a very long name ends with an ellipsis after two lines');
          expect(tester.getSize(find.byType(GradientCard)).height, greaterThan(shortHeight), reason: 'the card grows for a long name');
          // the avatar stays a circle and the card is as wide as the page
          expect(card.width, 360 - 2 * FolkSpace.pagePadding);
        });
      }
    }
  });

  test('wiring: the Profile list has no "My Guide" row; the name card gets the instant guide name (stamped + local copy)', () {
    final src = File('lib/pages/Profile.dart').readAsStringSync();
    expect(src.contains("'My Guide'"), isFalse);
    expect(src, contains('ProfileNameCard('));
    expect(src, contains('guideName: guideName'));
    expect(src, contains('stampedGuideName(data)'), reason: 'the same instant source: the user stream');
    expect(src, contains('GuideNameCache.read(uid)'), reason: 'plus the phone\'s copy');
    final card = File('lib/widgets/ProfileNameCard.dart').readAsStringSync();
    expect(card.contains('FutureBuilder') || card.contains('StreamBuilder'), isFalse, reason: 'the card does no loading of its own');
    expect(card.contains('LayoutBuilder'), isFalse);
  });
}
