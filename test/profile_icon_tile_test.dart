import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/ProfileMenuIconTile.dart';
import 'package:folk_app/widgets/ProfileMenuRow.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Profile menu icon tiles: the dark tile (#2E2E32) and the golden-orange icon,
// the same in both themes.
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

const rows = [
  ('My Competitions', 'Chanting competition and your badges', Icons.emoji_events_outlined, true),
  ('My Guide', 'SBSD', CupertinoIcons.person_2, false),
  ('My Notifications', 'Choose what you are notified about', CupertinoIcons.bell, true),
  ('My Date of Birth', 'Tap to add your date of birth', CupertinoIcons.gift, true),
  ('My Commitments', 'Tap to set your daily commitment', CupertinoIcons.flame_fill, true),
  ('My Music', 'Coming soon', CupertinoIcons.music_note_2, true),
];

// The real row the Profile uses (My Guide has no tap: display only).
Widget menu(bool dark) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              for (final r in rows)
                ProfileMenuRow(title: r.$1, subtitle: r.$2, icon: r.$3, onTap: r.$4 ? () {} : null),
            ],
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  test('tokens: tile is the dark secondary surface, icon is the saffron gradient', () {
    expect(FolkColors.profileIconTile, const Color(0xFF2E2E32));
    expect(FolkColors.profileIconTile, FolkColors.dark.surfaceSecondary);
    expect(FolkGradients.profileMenuIcon.colors, const [Color(0xFFFFE48F), Color(0xFFFFB65A)]);
    expect(FolkGradients.profileMenuIcon, FolkGradients.saffron);
  });

  test('Profile uses the tile for all six rows and hardcodes nothing', () {
    final src = File('lib/pages/Profile.dart').readAsStringSync();
    final row = File('lib/widgets/ProfileMenuRow.dart').readAsStringSync();
    expect(RegExp(r'ProfileMenuIconTile\(').allMatches(row).length, 1, reason: 'one shared row widget');
    expect(src.contains('ProfileMenuIconTile('), isFalse);
    for (final label in ['My Competitions', 'My Guide', 'My Notifications', 'My Date of Birth', 'My Commitments', 'My Music']) {
      expect(src, contains("'$label'"));
    }
    for (final gone in ['Book read', 'My Achievements', "'Chanting Competition'"]) {
      expect(src.contains(gone), isFalse, reason: '$gone was removed');
    }
    final tile = File('lib/widgets/ProfileMenuIconTile.dart').readAsStringSync();
    expect(tile.contains('0xFF'), isFalse, reason: 'colours come from tokens');
  });

  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('${dark ? 'dark' : 'light'}, text scale $scale, 360 dp: six rows, dark tiles, golden icons, no overflow', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(menu(dark));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'dark=$dark scale=$scale');
        expect(find.byType(ProfileMenuIconTile), findsNWidgets(6));
        for (final e in tester.widgetList<ProfileMenuIconTile>(find.byType(ProfileMenuIconTile))) {
          final f = find.byWidget(e);
          final box = tester.widget<Container>(find.descendant(of: f, matching: find.byType(Container)).first);
          expect((box.decoration! as BoxDecoration).color, const Color(0xFF2E2E32), reason: 'same dark tile in both modes');
          expect(tester.getSize(f), const Size(42, 42));
          final mask = tester.widget<ShaderMask>(find.descendant(of: f, matching: find.byType(ShaderMask)));
          expect(mask.blendMode, BlendMode.srcIn);
          // the icon sits inside the tile
          final icon = tester.getRect(find.descendant(of: f, matching: find.byType(Icon)));
          expect(tester.getRect(f).contains(icon.center), isTrue);
        }
        for (final r in rows) {
          final rect = tester.getRect(find.text(r.$1));
          expect(rect.right, lessThanOrEqualTo(360), reason: r.$1);
        }
      });
    }
  }
}
