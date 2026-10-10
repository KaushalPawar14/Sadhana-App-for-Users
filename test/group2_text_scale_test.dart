import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/FolkCard.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/Group2Widgets.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// Phase 11b group 2: the pieces the Profile and Insights destinations are built
// from, at 360 dp, text scale 1.0 / 1.3 / 1.6, in light and dark. The screens
// need Firebase, so each piece is rendered on its own with the screens' labels.
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

Widget page(Widget child, {bool dark = false, bool reduce = false, bool scroll = true}) {
  return MaterialApp(
    theme: dark ? FolkTheme.dark : FolkTheme.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: Scaffold(
          body: GhostScope(
            child: scroll
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: child,
                  )
                : child,
          ),
        ),
      ),
    ),
  );
}

// Every Text under [outer] lies inside it (top and bottom).
void inside(WidgetTester tester, Finder outer, String reason) {
  final box = tester.getRect(outer.first);
  for (final e in find.descendant(of: outer.first, matching: find.byType(Text)).evaluate()) {
    final r = tester.getRect(find.byWidget(e.widget).first);
    expect(r.top, greaterThanOrEqualTo(box.top - .5), reason: '${(e.widget as Text).data} top, $reason');
    expect(r.bottom, lessThanOrEqualTo(box.bottom + .5), reason: '${(e.widget as Text).data} bottom, $reason');
  }
}

const longName = 'Bhaktivedanta Swami Prabhupada Das Anudas';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      final s = '${dark ? 'dark' : 'light'}, text scale $scale, 360 dp';

      group('Leaderboards — $s', () {
        testWidgets('rank rows 1-4 with a long name wrap, no overflow, text inside', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(Column(children: [
            for (var r = 1; r <= 4; r++)
              LeaderboardRankRow(rank: r, name: longName, valueLabel: '1234 rounds'),
          ]), dark: dark));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          for (final f in find.byType(LeaderboardRankRow).evaluate()) {
            inside(tester, find.byWidget(f.widget), s);
            expect(tester.getSize(find.byWidget(f.widget)).height, greaterThanOrEqualTo(48));
          }
        });

        testWidgets('podium of three: no overflow with long names and values', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(flex: 2, child: Padding(padding: const EdgeInsets.only(bottom: 20), child: LeaderboardPodiumPlace(gradient: FolkMedal.silver, name: longName, valueLabel: '12345 rounds', medal: '🥈', size: 65))),
                Flexible(flex: 3, child: Padding(padding: const EdgeInsets.only(bottom: 40), child: LeaderboardPodiumPlace(gradient: FolkMedal.gold, name: longName, valueLabel: '12345 rounds', medal: '🥇', size: 85))),
                Flexible(flex: 2, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: LeaderboardPodiumPlace(gradient: FolkMedal.bronze, name: longName, valueLabel: '12345 rounds', medal: '🥉', size: 55))),
              ],
            ),
            dark: dark,
            reduce: true,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
        });

        testWidgets('ghost rows do not overflow', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(const LeaderboardGhost(rows: 5), dark: dark, reduce: true, scroll: false));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
        });
      });

      group('Results and winners — $s', () {
        testWidgets('six stat tiles with their change wrap, no overflow', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(
            FolkCard(
              child: Wrap(spacing: 12, runSpacing: 12, children: [
                for (final l in ['💻 SB Class: 2.00', '🛕 Service: 14.50', '📿 Chanting: 120.00', '📚 Reading: 60.00', '🎧 Lecture: 0.00', '📅 Days: 7'])
                  ScoreStatTile(label: l, footer: const Text('+12.5%')),
              ]),
            ),
            dark: dark,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
        });

        testWidgets('winner card front and back at the real card size (223 x 340)', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(
            Row(children: [
              SizedBox(
                width: 223,
                height: 340,
                child: WinnerFrontCard(
                  width: 223,
                  gradient: FolkMedal.gold,
                  medal: const Icon(Icons.star, size: 100),
                  name: longName,
                  scoreLabel: '1234.50 pts',
                ),
              ),
            ]),
            dark: dark,
            reduce: true,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$s front');
          await tester.pumpWidget(page(
            SizedBox(
              width: 223,
              height: 340,
              child: WinnerBackCard(width: 223, name: longName, rows: [
                for (final k in ['Bhagavatam', 'Book Reading', 'Chanting Rounds', 'Daily Service', 'Extra Lecture', 'Japa Multiplier', 'Sleeping Multiplier', 'Temple Multiplier'])
                  (k, '12.50 pts'),
              ]),
            ),
            dark: dark,
            reduce: true,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$s back');
        });

        testWidgets('Journey-style bob: still with reduce motion, runs otherwise, pauses in the background', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(const IdleFloat(dy: 12, child: SizedBox(height: 40, child: Text('x'))), dark: dark, reduce: true));
          await tester.pump();
          expect(tester.binding.transientCallbackCount, 0, reason: 'reduce motion: no ticker');
          await tester.pumpWidget(page(const IdleFloat(dy: 12, child: SizedBox(height: 40, child: Text('x'))), dark: dark));
          await tester.pump();
          expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'runs');
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
          expect(tester.binding.transientCallbackCount, 0, reason: 'paused in background');
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pumpWidget(const SizedBox());
        });
      });

      group('Profile destinations — $s', () {
        testWidgets('achievement badges: a row of four scrolls, no overflow, text inside', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final b in ['gold_badge', 'silver_badge', 'bronze_badge', '1st_badge'])
                  AchievementBadgeCard(badgeName: b, count: 12),
              ]),
            ),
            dark: dark,
            reduce: true,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s);
          for (final f in find.byType(AchievementBadgeCard).evaluate()) {
            inside(tester, find.byWidget(f.widget), s);
          }
        });

        testWidgets('notification switch with a long explanation, busy and idle', (tester) async {
          phone(tester, scale);
          for (final busy in [false, true]) {
            await tester.pumpWidget(page(
              PrefSwitchTile(
                icon: Icons.notifications_active_outlined,
                title: 'Reminders from your guide',
                subtitle: 'When your guide personally nudges you about a report, once a day at most',
                value: true,
                busy: busy,
                onChanged: busy ? null : (_) {},
              ),
              dark: dark,
              reduce: true,
            ));
            await tester.pump();
            expect(tester.takeException(), isNull, reason: '$s busy=$busy');
            expect(tester.getSize(find.byType(SwitchListTile)).height, greaterThanOrEqualTo(56));
          }
        });

        testWidgets('chanting competition: summary, contribution rows, result card', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(
            Column(children: [
              const ChallengeSummaryCard(name: 'Hare Krishna Maha Yagya for the whole roster', dateText: '30 Oct 2026', total: 1234, target: 5000, fraction: .25),
              const SizedBox(height: 12),
              ContributionRow(name: longName, rounds: 123, fraction: .4),
              ContributionRow(name: '', rounds: 0, fraction: 0),
              ChallengeResultCard(
                achieved: true,
                name: 'Hare Krishna Maha Yagya',
                total: 5100,
                target: 5000,
                topStudents: const ['A Very Long Name Das', 'Another Very Long Name Das'],
                topRounds: 321,
                action: PrimaryButton(label: 'Continue', onPressed: () {}),
              ),
            ]),
            dark: dark,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          inside(tester, find.byType(ChallengeSummaryCard), s);
          inside(tester, find.byType(ChallengeResultCard), s);
        });

        testWidgets('scorecard tile with the longest title', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(
            ScoreCategoryCard(
              title: 'Bhagavatam Class',
              image: 'assets/images/SBclass.jpg',
              style: FolkGradientStyle.violet,
              onTap: () {},
            ),
            dark: dark,
            reduce: true,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          inside(tester, find.byType(ScoreCategoryCard), s);
        });

        testWidgets('history: a session tile with a long preview and a daily message card', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(page(
            Column(children: [
              HistorySessionTile(
                label: 'Wednesday, 08 Oct 2026',
                subtitle: 'How do I stay steady in my practice during exams and keep my chanting going?',
                onTap: () {},
              ),
              const DailyHistoryCard(
                label: 'Wednesday, 08 Oct 2026',
                text: 'You kept your promise to Krishna yesterday, and that steady faithfulness is beautiful. Keep going.',
              ),
            ]),
            dark: dark,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: s);
          inside(tester, find.byType(DailyHistoryCard), s);
        });
      });
    }
  }
}
