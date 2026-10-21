import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/MyMusicPage.dart';
import 'package:folk_app/theme/FolkTheme.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Profile: every row is a "My ..." row (Appearance and Log Out stay as they are) and My Music opens "Coming soon".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  test('the Profile rows are named "My ..." (the old names are gone), My Music is the last one; Appearance and Log Out are unchanged', () {
    final src = File('lib/pages/Profile.dart').readAsStringSync();
    final order = ['My Competitions', 'My Guide', 'My Notifications', 'My Date of Birth', 'My Commitments', 'My Music'].map((l) => src.indexOf("'$l'")).toList();
    expect(order.every((i) => i > 0), isTrue);
    expect(order, [...order]..sort(), reason: 'in this order');
    for (final old in ["'Notifications'", "'Date of Birth'", "'Commitment'"]) {
      expect(src.contains(old), isFalse, reason: '$old was renamed');
    }
    expect(src, contains('"Appearance"'));
    expect(src, contains('showLogoutDialog'));
    expect(src, contains('MyMusicPage()'));
  });

  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('My Music says "Coming soon" - ${dark ? 'dark' : 'light'}, text $scale: no overflow', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(MaterialApp(theme: dark ? FolkTheme.dark : FolkTheme.light, home: const MyMusicPage()));
        await tester.pumpAndSettle();
        expect(find.text('My Music'), findsOneWidget, reason: 'the title');
        expect(find.byKey(const ValueKey('my-music-coming-soon')), findsOneWidget);
        expect(find.text('Coming soon'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
