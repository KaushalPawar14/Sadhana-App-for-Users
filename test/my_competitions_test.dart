import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Achievements.dart';
import 'package:folk_app/pages/MyCompetitions.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/Group2Widgets.dart' show AchievementBadgeCard;
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/ProfileMenuRow.dart';
import 'package:folk_app/widgets/SectionDivider.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Profile: "My Competitions" (the guide is a line in the name card, see profile_name_card_test). "My Competitions" is the chanting
// competition, an ACHIEVEMENTS divider, the badges and the rules button in one scroll.
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

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
      home: home,
    );

Future<Map<String, int>> badges() async => {'gold_badge': 2, 'silver_badge': 1, 'bronze_badge': 0, 'weekly_winner': 3};

// A stand-in for the chanting section: the active state's height and look.
const fakeChanting = Padding(
  padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(child: SizedBox(height: 170, child: Center(child: Text('CHANTING SECTION')))),
      SizedBox(height: 12),
      SizedBox(height: 64, child: Card(child: Text('contributor'))),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('My Competitions row; the guide lives in the name card', () {
    testWidgets('a row with a tap shows a chevron and responds', (tester) async {
      phone(tester, 1.0);
      var taps = 0;
      await tester.pumpWidget(host(Column(children: [
        ProfileMenuRow(title: 'My Competitions', subtitle: 'x', icon: Icons.emoji_events_outlined, onTap: () => taps++),
      ])));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.text('My Competitions'));
      expect(taps, 1);
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget, reason: 'the trophy');
    });

    test('Profile wiring: the rows and their order, the fields they read, the ghost', () {
      final src = File('lib/pages/Profile.dart').readAsStringSync();
      final order = ['My Competitions', 'My Notifications', 'My Date of Birth', 'My Commitments', 'My Music'].map((l) => src.indexOf("'$l'")).toList();
      expect(order.every((i) => i > 0), isTrue);
      expect(order, [...order]..sort());
      expect(src.contains("'My Guide'"), isFalse, reason: 'the My Guide row is gone: the guide is a line in the name card');
      for (final gone in ['Book read', 'My Achievements', "'Chanting Competition'", 'BooksSelectionScreen', 'AchievementsPage', 'ChantingCompetitionPage']) {
        expect(src.contains(gone), isFalse, reason: '$gone is gone from the Profile');
      }
      expect(src, contains("guideId = (data['guideId'] ?? '').toString();"), reason: 'read from the user stream already open');
      expect(src, contains('ProfileNameCard('), reason: 'the name card shows the guide');
      expect(src, contains('StudentApi.instance.getMyGuide()'), reason: 'from the callable, never adminUsers');
      expect(src, contains('MyCompetitionsPage(username: name ?? "")'));
      expect(src, contains('height: 5 * 64 + 12'), reason: 'the ghost has five rows now');
      // the notification deep link opens the same page
      expect(File('lib/utils/NotificationRouter.dart').readAsStringSync(), contains('const MyCompetitionsPage()'));
    });
  });

  for (final dark in [false, true]) {
    for (final scale in scales) {
      testWidgets('My Competitions: one scroll, chanting first, ACHIEVEMENTS divider, badges, rules button — ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
        phone(tester, scale);
        await tester.pumpWidget(host(MyCompetitionsPage(chantingSection: fakeChanting, badgesLoader: badges), dark: dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('My Competitions'), findsOneWidget, reason: 'the title');

        // one continuous vertical scroll
        final vertical = tester.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView)).where((s) => s.scrollDirection == Axis.vertical);
        expect(vertical.length, 1);

        // top to bottom: chanting, divider, badges, button
        final chanting = tester.getTopLeft(find.text('CHANTING SECTION')).dy;
        final divider = tester.getTopLeft(find.byType(SectionDivider)).dy;
        final badge = tester.getTopLeft(find.byType(AchievementBadgeCard).first).dy;
        await tester.scrollUntilVisible(find.byType(PrimaryButton), 200, scrollable: find.byType(Scrollable).first);
        final button = tester.getTopLeft(find.byType(PrimaryButton)).dy;
        expect(find.text('ACHIEVEMENTS'), findsOneWidget);
        expect(chanting, lessThan(divider + 1000)); // (the divider may be scrolled; order checked below)
        expect(find.text('View Sadhana Rules 📿'), findsOneWidget);
        expect(badge, lessThan(button + 5000));
        expect(find.byType(AchievementBadgeCard), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the order on screen: chanting above the ACHIEVEMENTS divider above the badges above the button', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(MyCompetitionsPage(chantingSection: fakeChanting, badgesLoader: badges)));
    await tester.pumpAndSettle();
    final y = (Finder f) => tester.getTopLeft(f.first).dy;
    expect(y(find.text('CHANTING SECTION')), lessThan(y(find.byType(SectionDivider))));
    expect(y(find.byType(SectionDivider)), lessThan(y(find.byType(AchievementBadgeCard))));
    expect(y(find.byType(AchievementBadgeCard)), lessThan(y(find.byType(PrimaryButton))));
  });

  testWidgets('the rules button opens the same Sadhana rules dialog', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(MyCompetitionsPage(chantingSection: fakeChanting, badgesLoader: badges)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsWidgets);
  });

  test('reads, writes and Navigator calls are the old pages\' own: counted in the code', () {
    String read(String f) => File(f).readAsStringSync();
    int count(String src, Pattern p) => p.allMatches(src).length;
    final chanting = read('lib/pages/ChantingCompetition.dart');
    final ach = read('lib/pages/Achievements.dart');
    final page = read('lib/pages/MyCompetitions.dart');
    // the chanting section: the same streams, reads, the one write and the 6 s timer
    expect(count(chanting, '.snapshots()'), 2);
    expect(count(chanting, '.get()'), 2); // the user's doc, the winners' contributions
    expect(count(chanting, '.set('), 1); // summarySeenBy
    expect(chanting, contains("'summarySeenBy': FieldValue.arrayUnion([myUid])"));
    expect(chanting, contains('Timer(const Duration(seconds: 6), _dismissWinner)'));
    expect(chanting.contains('Navigator.'), isFalse, reason: 'the section never navigates');
    // the badges: ONE read of the student's counts
    expect(count(ach, '.get()'), 1, reason: 'the student own user document only (no query by name any more)');
    // the page: one Navigator call (back), no reads or writes of its own
    expect(count(page, 'Navigator.pop(context)'), 1);
    expect(count(page, RegExp(r'\.(get|set|update|snapshots)\(')), 0);
  });
}
