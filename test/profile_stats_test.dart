import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/LogoutButton.dart';
import 'package:folk_app/widgets/ProfileStatTiles.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The three stat tiles under the Profile name card, and the red Log Out button.
// Real app fonts, 360 dp, text scale 1.0 / 1.3 / 1.6, light and dark.
void phone(WidgetTester tester, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 900);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Widget host(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: child),
      ),
    );

double luminance(Color c) {
  double f(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * f(c.r) + .7152 * f(c.g) + .0722 * f(c.b);
}

double contrast(Color a, Color b) {
  final l1 = luminance(a), l2 = luminance(b);
  return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text $scale';

      testWidgets('three tiles in a row, in order green / coral / violet, values and captions — $s', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(host(
            const ProfileStatTiles(bestChantRounds: 16, bestReadingMinutes: 90, bestDayPoints: 759),
            dark: dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (final t in ['16', '90', '759', 'best rounds', 'best reading (min)', 'best day points']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        final gradients = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .map((d) => d.gradient)
            .whereType<LinearGradient>()
            .toList();
        expect(gradients.map((g) => g.colors).toList(), [
          FolkGradients.green.colors,
          FolkGradients.coral.colors,
          FolkGradients.violet.colors,
        ]);

        // one row, equal widths, equal heights, inside the 320 dp column
        final rects = [for (final t in ['16', '90', '759']) tester.getRect(find.text(t))];
        final cards = tester.widgetList(find.byType(ProfileStatTiles)).length;
        expect(cards, 1);
        final tiles = [
          for (final c in ['best rounds', 'best reading (min)', 'best day points'])
            tester.getRect(find.ancestor(of: find.text(c), matching: find.byType(Container)).last)
        ];
        expect(rects[0].center.dy, closeTo(rects[1].center.dy, .5));
        expect(rects[1].center.dy, closeTo(rects[2].center.dy, .5));
        expect(tiles[0].right, lessThan(tiles[1].left));
        expect(tiles[1].right, lessThan(tiles[2].left));
        expect(tiles[2].right, lessThanOrEqualTo(340.01));
        expect(tiles[0].left, greaterThanOrEqualTo(19.99));
        expect({for (final t in tiles) t.height.toStringAsFixed(1)}.length, 1, reason: 'all three tiles are as tall as the tallest');
        expect(tiles[0].width, closeTo(tiles[1].width, .5));

        // no caption word is broken or cut: the longest word fits its line
        for (final c in ['best rounds', 'best reading (min)', 'best day points']) {
          final box = tester.renderObject<RenderParagraph>(find.text(c));
          expect(box.didExceedMaxLines, isFalse, reason: c);
          final scaler = const TextScaler.linear(1).clamp(maxScaleFactor: 1.2);
          final style = tester.widget<Text>(find.text(c)).style!;
          final real = tester.element(find.text(c));
          final eff = MediaQuery.textScalerOf(real);
          expect(eff.scale(10), lessThanOrEqualTo(12.001), reason: 'caption text is held to 1.2x');
          for (final w in c.split(' ')) {
            final tp = TextPainter(
              text: TextSpan(text: w, style: DefaultTextStyle.of(real).style.merge(style)),
              textDirection: TextDirection.ltr,
              textScaler: eff,
            )..layout();
            expect(tp.width, lessThanOrEqualTo(box.size.width + .5), reason: '"$w" fits the tile whole');
          }
          expect(scaler.scale(10), lessThanOrEqualTo(12.001));
        }
      });

      testWidgets('the loading ghost row is exactly as tall as the real row — $s', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(host(
            const ProfileStatTiles(bestChantRounds: 16, bestReadingMinutes: 90, bestDayPoints: 759),
            dark: dark));
        await tester.pumpAndSettle();
        final real = tester.getSize(find.byType(ProfileStatTiles)).height;

        await tester.pumpWidget(host(const ProfileStatTilesGhost(), dark: dark));
        expect(tester.getSize(find.byType(ProfileStatTilesGhost)).height, closeTo(real, 1.5));
        expect(tester.takeException(), isNull);

        // a zero best (nothing earned yet) is still a whole, same-height tile
        await tester.pumpWidget(host(
            const ProfileStatTiles(bestChantRounds: 0, bestReadingMinutes: 0, bestDayPoints: 0),
            dark: dark));
        await tester.pump();
        expect(find.text('best day points'), findsOneWidget);
        expect(tester.getSize(find.byType(ProfileStatTiles)).height, closeTo(real, 1.5));
        expect(tester.takeException(), isNull);
      });

      testWidgets('big numbers shrink, never overflow or wrap — $s', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(host(
            const ProfileStatTiles(bestChantRounds: 250, bestReadingMinutes: 1440, bestDayPoints: 12345),
            dark: dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final t in ['250', '1440', '12345']) {
          expect(find.text(t), findsOneWidget);
        }
      });

      testWidgets('Log Out: filled red, white label and icon, tappable, ≥56 dp, no overflow — $s', (tester) async {
        phone(tester, scale);
        var taps = 0;
        await tester.pumpWidget(host(LogoutButton(onPressed: () => taps++), dark: dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final deco = tester
            .widgetList<Container>(find.descendant(of: find.byType(LogoutButton), matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .first;
        expect(deco.color, FolkColors.logoutRed);
        expect(deco.color, const Color(0xFFC62828));
        final label = tester.widget<Text>(find.text('Log Out'));
        expect(label.style!.color, Colors.white);
        expect(tester.widget<Icon>(find.byIcon(Icons.logout_rounded)).color, Colors.white);
        expect(tester.getSize(find.byType(LogoutButton)).height, greaterThanOrEqualTo(56));
        expect(tester.getSize(find.byType(LogoutButton)).width, 320);
        await tester.tap(find.byType(LogoutButton));
        expect(taps, 1);
      });
    }
  }

  test('the red gives white text at least 4.5:1 (WCAG AA), in both modes (it is one fixed colour)', () {
    final ratio = contrast(FolkColors.logoutRed, FolkColors.onLogoutRed);
    expect(ratio, greaterThanOrEqualTo(4.5));
    // ignore: avoid_print
    print('white on #C62828 = ${ratio.toStringAsFixed(2)}:1');
    expect(ratio, closeTo(5.62, .02));
  });

  test('Profile wiring: tiles sit under the name card from the user document (no books query, no books-completed tile); Log Out uses the button', () {
    final src = File('lib/pages/Profile.dart').readAsStringSync();
    expect(src, contains("data['bestChantRounds']"));
    expect(src, contains("data['bestReadingMinutes']"));
    expect(src, contains("data['bestDayPoints']"));
    expect(src, isNot(contains(".collection('booksRead')")));
    expect(src, isNot(contains('completedBooksOf(')));
    expect(src, isNot(contains('books completed')));
    expect(src, contains('ProfileStatTilesGhost()'));
    expect(src, contains('LogoutButton(onPressed: () => showLogoutDialog(context))'));
    final nameCard = src.indexOf('/// Profile header');
    final tiles = src.indexOf('ProfileStatTiles(');
    final menu = src.indexOf('/// Menu rows');
    expect(nameCard < tiles && tiles < menu, isTrue);
    // the Appearance control is untouched
    expect(src, contains('FolkThemeMode.auto'));
  });
}
