import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/ProfileMenuIconTile.dart';

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
  ('Book read', 'Share your books reading history', CupertinoIcons.book),
  ('My Achievements', 'Your All Badges and Tags', CupertinoIcons.mail),
  ('Chanting Competition', "See the group's live rounds target", CupertinoIcons.flame),
  ('Notifications', 'Choose what you are notified about', CupertinoIcons.bell),
  ('Date of Birth', 'Tap to add your date of birth', CupertinoIcons.gift),
  ('Chanting Commitment', 'Tap to set your daily rounds commitment', CupertinoIcons.flame_fill),
];

Widget menu(bool dark) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                  child: Row(
                    children: [
                      ProfileMenuIconTile(r.$3),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.$1, style: context.folkTextForTest.bodyStrong),
                            Text(r.$2, style: context.folkTextForTest.caption),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
            ],
          ),
          ),
        ),
      ),
    );

extension on BuildContext {
  _T get folkTextForTest => _T(this);
}

class _T {
  _T(this.c);
  final BuildContext c;
  TextStyle get bodyStrong => Theme.of(c).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w700);
  TextStyle get caption => Theme.of(c).textTheme.bodySmall!;
}

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
    expect(RegExp(r'ProfileMenuIconTile\(').allMatches(src).length, 1, reason: 'one shared _menuRow');
    for (final label in ['Book read', 'My Achievements', 'Chanting Competition', 'Notifications', 'Date of Birth', 'Chanting Commitment']) {
      expect(src, contains("'$label'"));
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
