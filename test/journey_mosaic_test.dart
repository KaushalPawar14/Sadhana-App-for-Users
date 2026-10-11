import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/CountUpText.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/GhostedTextLine.dart';
import 'package:folk_app/widgets/JourneyMosaic.dart';
import 'package:folk_app/widgets/MinHeightBox.dart';
import 'package:folk_app/widgets/SectionDivider.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The Journey mosaic at 360 dp, text scale 1.0 / 1.3 / 1.6, light and dark. The
// screen needs Firebase, so the rows are rebuilt here from the very same
// widgets (JourneyPair, JourneyStack, JourneyTile) with the screen's own
// titles and lines.
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

Widget avatar(BuildContext context, String letter) => Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99FFFFFF)),
      child: Text(letter, style: context.folkText.cardTitle),
    );

// The square tiles' icon and two-line description, as Phase7Section draws them.
Widget smallAvatar(BuildContext context, String letter) => Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99FFFFFF)),
      child: Text(letter, style: context.folkText.cardTitle),
    );

Widget twoLines(BuildContext context, String text) => MinHeightBox(
      minHeight: ghostHeight(context, 2 * 17.2),
      child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.folkText.onGradientCaption),
    );

Widget line(BuildContext context, String text, {bool oneLine = true}) => oneLine
    ? GhostedTextLine(
        loading: false,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.folkText.onGradientCaption))
    : Text(text, style: context.folkText.onGradientCaption);

Widget host(Widget Function(BuildContext) rows, {bool dark = false, bool reduce = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Scaffold(
        body: GhostScope(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Builder(builder: rows),
          ),
        ),
      ),
    );

Widget mosaic(BuildContext context, {int lifetime = 108, String reading = 'Currently reading: Beyond Birth and Death'}) {
  void tap() {}
  return Column(
    children: [
      const SectionDivider(label: 'ABCDE'),
      // row 2: Chanting tall on the LEFT; Association over Books on the RIGHT
      JourneyPair(
        left: JourneyTile(
          style: FolkFeatureGradients.chanting,
          title: 'Chanting',
          subtitle: 'Track your japa rounds',
          tall: true,
          watermark: Icons.radio_button_checked_outlined,
          leading: avatar(context, 'C'),
          stat: GhostedTextLine(
            loading: false,
            lineHeight: 53,
            child: CountUpText(value: lifetime, style: context.folkText.bigStat),
          ),
          statCaption: 'rounds lifetime',
          onTap: tap,
        ),
        right: JourneyStack(
          top: JourneyTile(
            style: FolkFeatureGradients.association,
            title: 'Association',
            watermark: Icons.people_alt_outlined,
            leading: avatar(context, 'A'),
            line: line(context, '12 sessions this month'),
            onTap: tap,
          ),
          bottom: JourneyTile(
            style: FolkFeatureGradients.books,
            title: 'Books',
            watermark: Icons.menu_book_outlined,
            leading: avatar(context, 'B'),
            line: line(context, reading),
            onTap: tap,
          ),
        ),
      ),
      const SizedBox(height: FolkSpace.cardGap),
      // row 3: Devotional Service and Expeditions, half width each
      JourneyPair(
        left: JourneyTile(
          style: FolkFeatureGradients.devotionalService,
          title: 'Devotional Service',
          watermark: Icons.volunteer_activism_outlined,
          leading: avatar(context, 'D'),
          line: line(context, 'Browse opportunities'),
          onTap: tap,
        ),
        right: JourneyTile(
          style: FolkFeatureGradients.expeditions,
          title: 'Expeditions',
          watermark: Icons.explore_outlined,
          leading: avatar(context, 'E'),
          line: line(context, 'View upcoming trips'),
          onTap: tap,
        ),
      ),
      const SectionDivider(label: 'MODULES'),
      // row 4: two SQUARE tiles on the LEFT; Podcast tall on the RIGHT
      JourneyPair(
        left: JourneyStack(
          top: JourneyTile(
            style: FolkFeatureGradients.rduaModules,
            title: 'RDUA Modules',
            square: true,
            watermark: Icons.school_outlined,
            leading: smallAvatar(context, 'R'),
            line: twoLines(context, '50 topics, 2 chapters each — open to everyone'),
            onTap: tap,
          ),
          bottom: JourneyTile(
            style: FolkFeatureGradients.rduaFriends,
            title: 'RDUA Friends',
            square: true,
            watermark: Icons.people_alt_outlined,
            leading: smallAvatar(context, 'F'),
            line: twoLines(context, 'Add friends, make groups, start a voice room'),
            onTap: tap,
          ),
        ),
        right: JourneyTile(
          style: FolkFeatureGradients.podcastModules,
          title: 'Podcast Modules',
          tall: true,
          watermark: Icons.headphones,
          leading: avatar(context, 'P'),
          line: line(context, 'FOLK-2 to FOLK-16 — listen to all of them, any time', oneLine: false),
          onTap: tap,
        ),
      ),
    ],
  );
}

Rect rectOf(WidgetTester tester, String title) =>
    tester.getRect(find.byWidgetPredicate((w) => w is JourneyTile && w.title == title));

void insideTile(WidgetTester tester, String title, String reason) {
  final tile = find.byWidgetPredicate((w) => w is JourneyTile && w.title == title);
  final box = tester.getRect(tile);
  for (final e in find.descendant(of: tile, matching: find.byType(Text)).evaluate()) {
    final r = tester.getRect(find.byWidget(e.widget).first);
    final label = (e.widget as Text).data;
    expect(r.top, greaterThanOrEqualTo(box.top - .5), reason: '"$label" top, $title, $reason');
    expect(r.bottom, lessThanOrEqualTo(box.bottom + .5), reason: '"$label" bottom, $title, $reason');
    expect(r.left, greaterThanOrEqualTo(box.left - .5), reason: '"$label" left, $title, $reason');
    expect(r.right, lessThanOrEqualTo(box.right + .5), reason: '"$label" right, $title, $reason');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text scale $scale, 360 dp';

      group('Journey mosaic — $s', () {
        testWidgets('no overflow; every title and line fully inside its tile', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host((c) => mosaic(c), dark: dark, reduce: true));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s);
          for (final t in ['Chanting', 'Books', 'Association', 'Devotional Service', 'Expeditions', 'RDUA Modules', 'RDUA Friends', 'Podcast Modules']) {
            insideTile(tester, t, s);
          }
        });

        testWidgets('two columns, 12 dp gaps; tiles at least 112 / 236 dp tall', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host((c) => mosaic(c), dark: dark, reduce: true));
          await tester.pumpAndSettle();
          final chanting = rectOf(tester, 'Chanting');
          final assoc = rectOf(tester, 'Association');
          final books = rectOf(tester, 'Books');
          final service = rectOf(tester, 'Devotional Service');
          final trips = rectOf(tester, 'Expeditions');
          final rdua = rectOf(tester, 'RDUA Modules');
          final friends = rectOf(tester, 'RDUA Friends');
          final podcast = rectOf(tester, 'Podcast Modules');
          // columns: left x 20..174, right x 186..340
          for (final r in [chanting, service, rdua]) {
            expect(r.left, 20);
            expect(r.width, closeTo(154, .5));
          }
          for (final r in [assoc, books, trips]) {
            expect(r.right, 340);
            expect(r.width, closeTo(154, .5));
          }
          expect(friends.left, 20);
          expect(friends.width, closeTo(154, .5));
          expect(podcast.right, 340);
          // sides: Chanting LEFT, Books/Association RIGHT; RDUA/Friends LEFT, Podcast RIGHT
          expect(chanting.left, lessThan(assoc.left));
          expect(rdua.left, lessThan(podcast.left));
          // gaps
          expect(assoc.left - chanting.right, closeTo(12, .5));
          expect(books.top - assoc.bottom, closeTo(12, .5), reason: 'Association above Books');
          expect(trips.left - service.right, closeTo(12, .5));
          expect(podcast.left - rdua.right, closeTo(12, .5));
          expect(friends.top - rdua.bottom, closeTo(12, .5));
          expect(service.top - chanting.bottom, closeTo(12, .5), reason: 'row 3 under row 2');
          // minimums
          for (final r in [assoc, books, service, trips, rdua, friends]) {
            expect(r.height, greaterThanOrEqualTo(kJourneyShortMin));
          }
          expect(chanting.height, greaterThanOrEqualTo(kJourneyTallMin));
          expect(podcast.height, greaterThanOrEqualTo(kJourneyTallMin));
        });

        testWidgets('the tall tile is exactly the two short tiles and the gap, in both mirrored rows', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host((c) => mosaic(c), dark: dark, reduce: true));
          await tester.pumpAndSettle();
          final chanting = rectOf(tester, 'Chanting');
          final assoc = rectOf(tester, 'Association');
          final books = rectOf(tester, 'Books');
          expect(chanting.top, closeTo(assoc.top, .5));
          expect(chanting.bottom, closeTo(books.bottom, .5), reason: 'row 2, $s');
          expect(chanting.height, closeTo(assoc.height + 12 + books.height, .5));
          final podcast = rectOf(tester, 'Podcast Modules');
          final rdua = rectOf(tester, 'RDUA Modules');
          final friends = rectOf(tester, 'RDUA Friends');
          expect(podcast.top, closeTo(rdua.top, .5));
          expect(podcast.bottom, closeTo(friends.bottom, .5), reason: 'row 4, $s');
          expect(podcast.height, closeTo(rdua.height + 12 + friends.height, .5));
          // Devotional Service and Expeditions are the same height
          expect(rectOf(tester, 'Devotional Service').height, closeTo(rectOf(tester, 'Expeditions').height, .5));
        });

        testWidgets('long progress lines and huge lifetime numbers still fit', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host(
              (c) => mosaic(c, lifetime: 123456789, reading: 'Currently reading: The Nectar of Devotion, Part Two, Volume Three'),
              dark: dark,
              reduce: true));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s);
          insideTile(tester, 'Chanting', s);
          insideTile(tester, 'Books', s);
          final chanting = rectOf(tester, 'Chanting');
          expect(rectOf(tester, 'Books').bottom, closeTo(chanting.bottom, .5));
        });
      });

      group('Journey sections, squares, dividers — $s', () {
        testWidgets('RDUA Modules and RDUA Friends are square and equal; Podcast = both + the gap', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host((c) => mosaic(c), dark: dark, reduce: true));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s);
          final rdua = rectOf(tester, 'RDUA Modules');
          final friends = rectOf(tester, 'RDUA Friends');
          final podcast = rectOf(tester, 'Podcast Modules');
          expect(rdua.width, closeTo(154, .5));
          expect(friends.width, closeTo(154, .5));
          // Never shorter than wide; at 1.0 exactly square (they grow only when text needs more room).
          expect(rdua.height, greaterThanOrEqualTo(rdua.width - .5), reason: s);
          expect(friends.height, greaterThanOrEqualTo(friends.width - .5), reason: s);
          if (scale == 1.0) {
            expect(rdua.height, closeTo(rdua.width, .5), reason: 'square at 1.0');
            expect(friends.height, closeTo(friends.width, .5), reason: 'square at 1.0');
            expect(rdua.height, closeTo(friends.height, .5), reason: 'equal squares');
          }
          expect(podcast.height, closeTo(rdua.height + 12 + friends.height, .5));
          expect(friends.top - rdua.bottom, closeTo(12, .5));
          expect(podcast.left - rdua.right, closeTo(12, .5));
          insideTile(tester, 'RDUA Modules', s);
          insideTile(tester, 'RDUA Friends', s);
        });

        testWidgets('dividers end at the 20 dp content edges; the label is centred with equal space', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host((c) => mosaic(c), dark: dark, reduce: true));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s);
          final abcde = find.widgetWithText(SectionDivider, 'ABCDE');
          final modules = find.widgetWithText(SectionDivider, 'MODULES');
          expect(abcde, findsOneWidget);
          expect(modules, findsOneWidget);
          for (final d in [abcde, modules]) {
            final box = tester.getRect(d);
            expect(box.left, 20, reason: 'left edge, $s');
            expect(box.right, 340, reason: 'right edge, $s');
            final label = tester.getRect(find.descendant(of: d, matching: find.byType(Text)));
            expect(label.center.dx, closeTo(180, .5), reason: 'label centred');
            expect(label.center.dy, closeTo(box.center.dy, .5), reason: 'equal space above and below');
            final lines = find.descendant(of: d, matching: find.byType(Container));
            final first = tester.getRect(lines.first);
            expect(first.left, 20, reason: 'line starts at the content edge');
            expect(tester.getRect(lines.last).right, 340, reason: 'line ends at the content edge');
            expect(first.height, 1);
            // 26 dp of space above and below the label row.
            expect(label.top - box.top, greaterThanOrEqualTo(26 - .5));
            expect(box.bottom - label.bottom, greaterThanOrEqualTo(26 - .5));
          }
          expect(tester.getRect(abcde).bottom, lessThanOrEqualTo(rectOf(tester, 'Chanting').top + .5));
          expect(rectOf(tester, 'Devotional Service').bottom, lessThanOrEqualTo(tester.getRect(modules).top + .5));
          expect(tester.getRect(modules).bottom, lessThanOrEqualTo(rectOf(tester, 'RDUA Modules').top + .5));
        });

        testWidgets('divider line is the primary text colour (ink in light, cream in dark), fading outward', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host((c) => mosaic(c), dark: dark, reduce: true));
          await tester.pumpAndSettle();
          final d = find.widgetWithText(SectionDivider, 'ABCDE');
          final ink = tester.element(d).folk.text;
          final line = tester.widget<Container>(find.descendant(of: d, matching: find.byType(Container)).first);
          final gradient = (line.decoration! as BoxDecoration).gradient! as LinearGradient;
          final strong = gradient.colors.last;
          expect(strong.r, closeTo(ink.r, .01));
          expect(strong.g, closeTo(ink.g, .01));
          expect(strong.b, closeTo(ink.b, .01));
          expect(gradient.colors.first.a, 0);
        });
      });

      group('Journey greeting — $s', () {
        testWidgets('loaded, loading and empty name: no overflow; the loading ghost is as tall as the name', (tester) async {
          phone(tester, scale);
          double heightFor(bool loading, String? name) => 0;
          Future<double> measure(bool loading, String? name) async {
            await tester.pumpWidget(host((c) => JourneyGreeting(firstName: name, loading: loading), dark: dark, reduce: true));
            await tester.pump();
            expect(tester.takeException(), isNull, reason: '$s loading=$loading name=$name');
            return tester.getSize(find.byType(JourneyGreeting)).height;
          }

          final loadedHeight = await measure(false, 'Krishna');
          final ghostHeightNow = await measure(true, null);
          expect(find.text('Hare Krishna,'), findsOneWidget);
          expect(ghostHeightNow, greaterThanOrEqualTo(loadedHeight - 1), reason: 'no jump when the name arrives');
          await measure(false, '');
          expect(find.text('Hare Krishna,'), findsOneWidget);
          await measure(false, 'Venkateshwarananda');
          expect(find.text('Venkateshwarananda'), findsOneWidget);
          final r = tester.getRect(find.text('Venkateshwarananda'));
          expect(r.right, lessThanOrEqualTo(340.5), reason: 'a long first name scales down instead of overflowing');
          expect(heightFor(false, null), 0);
        });
      });
    }
  }

  test('colour table: every feature maps to the approved gradient', () {
    expect(FolkFeatureGradients.association, FolkGradientStyle.green);
    expect(FolkFeatureGradients.books, FolkGradientStyle.violet);
    expect(FolkFeatureGradients.chanting, FolkGradientStyle.coral);
    expect(FolkFeatureGradients.devotionalService, FolkGradientStyle.green);
    expect(FolkFeatureGradients.expeditions, FolkGradientStyle.saffron);
    expect(FolkFeatureGradients.rduaModules, FolkGradientStyle.violet);
    expect(FolkFeatureGradients.rduaFriends, FolkGradientStyle.saffron);
    expect(FolkFeatureGradients.podcastModules, FolkGradientStyle.coral);
    expect(FolkFeatureGradients.weeklyPerformance, FolkGradientStyle.green);
    expect(FolkFeatureGradients.monthlyPerformance, FolkGradientStyle.coral);
    expect(FolkFeatureGradients.bestPerformer, FolkGradientStyle.violet);
  });

  test('Journey screen source: greeting, message, ABCDE divider, five cards, MODULES divider, modules', () {
    final src = File('lib/pages/ABCDEScreen.dart').readAsStringSync();
    final order = [
      'JourneyGreeting(',
      'JourneyTodayMessage(',
      "label: 'ABCDE'",
      'title: "Chanting"',
      'title: "Association"',
      'title: "Books"',
      'title: "Devotional Service"',
      'title: "Expeditions"',
      "label: 'MODULES'",
      'Phase7Section()',
    ];
    var at = -1;
    for (final key in order) {
      final i = src.indexOf(key, at + 1);
      expect(i, greaterThan(at), reason: '$key comes after the previous item');
      at = i;
    }
    final phase7 = File('lib/pages/Phase7Placeholders.dart').readAsStringSync();
    var p = -1;
    for (final key in ['top: _rduaCard', 'bottom: _rduaFriendsCard', 'right: _podcastCard']) {
      final i = phase7.indexOf(key, p + 1);
      expect(i, greaterThan(p), reason: key);
      p = i;
    }
  });

  testWidgets('reduce motion: the lifetime number is simply there, no ticker', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host((c) => mosaic(c, lifetime: 4321), reduce: true));
    await tester.pump();
    expect(find.text('4321'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
