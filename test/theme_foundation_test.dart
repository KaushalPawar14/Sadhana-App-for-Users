import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/AssistantScreen.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/utils/AssistantRouteVisibility.dart';
import 'package:folk_app/utils/FloatingButtonInsets.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/MarkdownText.dart';
import 'package:folk_app/theme/ThemeModeController.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/JapaTapCircle.dart';
import 'package:folk_app/widgets/FolkSegmented.dart';
import 'package:folk_app/widgets/SadhanaDayCell.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:provider/provider.dart';
import 'package:folk_app/widgets/FolkChip.dart';
import 'package:folk_app/widgets/GhostPlaceholder.dart';
import 'package:folk_app/widgets/GradientCard.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/RoundIconButton.dart';
import 'package:folk_app/widgets/StatTile.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeModeController> _load(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  return ThemeModeController.load();
}

Widget _app(Widget child, {bool dark = false, bool reduce = false}) {
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(360, 800),
      disableAnimations: reduce,
    ),
    child: MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeController', () {
    test('no saved value and no legacy value -> auto, and it is saved', () async {
      final c = await _load({});
      expect(c.mode, FolkThemeMode.auto);
      expect(c.themeMode, ThemeMode.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeModeController.prefsKey), 'auto');
    });

    test('legacy isDarkMode=true -> dark', () async {
      final c = await _load({'isDarkMode': true});
      expect(c.mode, FolkThemeMode.dark);
      expect(c.isDark, isTrue);
    });

    test('legacy isDarkMode=false -> light (an explicit past choice)', () async {
      final c = await _load({'isDarkMode': false});
      expect(c.mode, FolkThemeMode.light);
      expect(c.themeMode, ThemeMode.light);
      expect(c.isDark, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeModeController.prefsKey), 'light');
    });

    test('a saved choice wins over the legacy value', () async {
      final c = await _load({'isDarkMode': true, ThemeModeController.prefsKey: 'light'});
      expect(c.mode, FolkThemeMode.light);
      expect(c.isDark, isFalse);
    });

    test('setMode persists and notifies', () async {
      final c = await _load({});
      var notified = 0;
      c.addListener(() => notified++);
      await c.setMode(FolkThemeMode.dark);
      expect(notified, 1);
      expect((await SharedPreferences.getInstance()).getString(ThemeModeController.prefsKey), 'dark');
      await c.setMode(FolkThemeMode.dark);
      expect(notified, 1, reason: 'same mode is a no-op');
    });

    test('ColorProvider follows the controller, and toggleColor goes through it', () async {
      final c = await _load({});
      await c.setMode(FolkThemeMode.light);
      final p = ColorProvider(loadLegacyPrefs: false)..bindTo(c);
      expect(p.color, Colors.white);
      await c.setMode(FolkThemeMode.dark);
      expect(p.color, Colors.black87);
      expect(p.secondColor, Colors.white);
      await p.toggleColor();
      expect(c.mode, FolkThemeMode.light);
      expect(p.color, Colors.white);
    });
  });

  group('tokens', () {
    test('palettes match the design values', () {
      expect(FolkColors.light.pageBackground, const Color(0xFFF8F7FC));
      expect(FolkColors.dark.pageBackground, const Color(0xFF151517));
      expect(FolkColors.dark.surface, const Color(0xFF222225));
      expect(FolkColors.onGradient, const Color(0xFF1E1B2E));
      expect(FolkGradients.green.colors, const [Color(0xFFC4EED8), Color(0xFF82D3A8)]);
      expect(FolkGradients.warm.colors, const [Color(0xFFFFE9B8), Color(0xFFFFC978)]);
    });

    test('lerp cross-fades between the two palettes', () {
      final mid = FolkColors.light.lerp(FolkColors.dark, .5);
      expect(mid.pageBackground, Color.lerp(FolkColors.light.pageBackground, FolkColors.dark.pageBackground, .5));
      expect(FolkColors.light.lerp(FolkColors.dark, 1).surface, FolkColors.dark.surface);
    });
  });

  group('EntryAnimation', () {
    double opacityOf(WidgetTester tester, String label) => tester
        .widget<FadeTransition>(find
            .ancestor(of: find.text(label), matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;

    double offsetOf(WidgetTester tester, String label) => tester
        .widget<Transform>(find
            .ancestor(of: find.text(label), matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .y;

    testWidgets('fades in and rises ~14 dp over ~300 ms, later items wait 50 ms each', (tester) async {
      await tester.pumpWidget(_app(const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EntryAnimation(index: 0, child: Text('first')),
          EntryAnimation(index: 3, child: Text('fourth')),
        ],
      )));
      expect(opacityOf(tester, 'first'), 0);
      expect(offsetOf(tester, 'first'), closeTo(FolkMotion.entryOffset, .01));

      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, 'first'), greaterThan(0));
      expect(opacityOf(tester, 'fourth'), 0, reason: 'index 3 waits 150 ms');

      await tester.pump(const Duration(milliseconds: 250));
      expect(opacityOf(tester, 'first'), 1);
      expect(offsetOf(tester, 'first'), 0);
      expect(opacityOf(tester, 'fourth'), greaterThan(0));

      await tester.pumpAndSettle();
      expect(opacityOf(tester, 'fourth'), 1);
    });

    testWidgets('reduce-motion: shown immediately, no motion', (tester) async {
      await tester.pumpWidget(_app(
        const EntryAnimation(index: 2, child: Text('now')),
        reduce: true,
      ));
      expect(opacityOf(tester, 'now'), 1);
      expect(offsetOf(tester, 'now'), 0);
    });
  });

  group('chatBubble (Ask) at 360 dp, both themes', () {
    const long = 'Why is chanting Hare Krishna so important for a student who is '
        'trying to stay steady in practice during a very busy exam season?';

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      final colors = dark ? FolkColors.dark : FolkColors.light;

      BoxDecoration decorationOf(WidgetTester tester, String label) =>
          tester
              .widget<Container>(find
                  .ancestor(of: find.text(label), matching: find.byType(Container))
                  .first)
              .decoration as BoxDecoration;

      testWidgets('student turn $theme: ink bubble, 22/22/6/22 corners', (tester) async {
        await tester.pumpWidget(_app(
          Builder(builder: (c) => chatBubble(c, const ChatTurn('Hi', fromStudent: true))),
          dark: dark,
        ));
        final d = decorationOf(tester, 'Hi');
        expect(d.color, colors.primaryBg);
        expect(tester.widget<Text>(find.text('Hi')).style!.color, colors.primaryFg);
        final r = d.borderRadius as BorderRadius;
        expect([r.topLeft.x, r.topRight.x, r.bottomRight.x, r.bottomLeft.x], [22, 22, 6, 22]);
      });

      testWidgets('reply turn $theme: surface bubble, 22/22/22/6 corners, wraps long text', (tester) async {
        await tester.pumpWidget(_app(
          Builder(builder: (c) => chatBubble(c, const ChatTurn(long, fromStudent: false))),
          dark: dark,
        ));
        final d = decorationOf(tester, long);
        expect(d.color, colors.surface);
        final r = d.borderRadius as BorderRadius;
        expect([r.topLeft.x, r.topRight.x, r.bottomRight.x, r.bottomLeft.x], [22, 22, 22, 6]);
        expect(tester.getSize(find.byType(Container).first).width, lessThanOrEqualTo(360 * .82 + .1));
        expect(tester.takeException(), isNull);
      });

      testWidgets("daily message $theme: sky-blue gradient card, label, ink text", (tester) async {
        await tester.pumpWidget(_app(
          SizedBox(
            width: 320,
            child: Builder(builder: (c) => chatBubble(
                c, const ChatTurn('You kept your promise.', fromStudent: false, isDailyMessage: true))),
          ),
          dark: dark,
        ));
        expect(find.text("TODAY'S MESSAGE"), findsOneWidget);
        final d = decorationOf(tester, 'You kept your promise.');
        expect((d.gradient as LinearGradient).colors, FolkGradients.sky.colors);
        // The message is drawn as rich text now (so **bold** can show); the colour
        // is on its span, unchanged.
        final rich = tester.widget<RichText>(find.descendant(
            of: find.byType(MarkdownText), matching: find.byType(RichText)));
        final span = (rich.text as TextSpan).children!.single as TextSpan;
        expect(span.style!.color, FolkColors.onGradient);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('floating buttons and the pill navigation', () {
    testWidgets('bottom inset clears the pill: 68 + 20 + system inset + 12 (was a fixed 96)', (tester) async {
      Future<double> insetWith(double systemBottom) async {
        late double inset;
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            viewPadding: EdgeInsets.only(bottom: systemBottom),
          ),
          child: Builder(builder: (context) {
            inset = floatingButtonBottomInset(context);
            return const SizedBox();
          }),
        ));
        return inset;
      }

      expect(await insetWith(0), 100);
      expect(await insetWith(24), 124);
      expect(await insetWith(48), 148, reason: '3-button navigation');
      // The pill's top edge sits at 68 + 20 + system inset; the inset is above it.
      expect(await insetWith(48), greaterThan(FolkShape.navHeight + FolkShape.navInset + 48));
    });

    testWidgets('a nav item decoration (the Journey dot) keeps its state across tab changes', (tester) async {
      var created = 0;
      var index = 1;
      await tester.pumpWidget(_app(
        StatefulBuilder(builder: (context, setState) {
          return FloatingPillNavBar(
            currentIndex: index,
            onTap: (i) => setState(() => index = i),
            items: [
              for (final label in ['Insights', 'Journey', 'Sadhana', 'Profile'])
                FolkNavItem(
                  label: label,
                  iconBuilder: (context, selected, color) => Icon(Icons.circle, size: 22, color: color),
                  decorate: label == 'Journey'
                      ? (context, icon) => _Probe(onCreate: () => created++, child: icon)
                      : null,
                ),
            ],
          );
        }),
      ));
      await tester.pumpAndSettle();
      expect(created, 1);
      await tester.tap(find.byType(GestureDetector).at(2)); // away from Journey
      await tester.pumpAndSettle();
      await tester.tap(find.byType(GestureDetector).at(1)); // back to Journey
      await tester.pumpAndSettle();
      expect(created, 1, reason: 'decoration state is not recreated when the tab is selected');
    });
  });

  group('AssistantRouteVisibility', () {
    testWidgets('true only while the assistant route is on top', (tester) async {
      final observer = AssistantRouteVisibility();
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('home')),
      ));
      await tester.pump();
      expect(observer.onAssistant.value, isFalse);

      navKey.currentState!.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: kAssistantRouteName),
        builder: (_) => const Scaffold(body: Text('ask')),
      ));
      await tester.pumpAndSettle();
      expect(observer.onAssistant.value, isTrue);

      navKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('history')),
      ));
      await tester.pumpAndSettle();
      expect(observer.onAssistant.value, isFalse, reason: 'a screen pushed over Ask is not Ask');

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(observer.onAssistant.value, isTrue);

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(observer.onAssistant.value, isFalse);
    });
  });

  group('Appearance selector (FolkSegmented bound to ThemeModeController)', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('$theme: 48 dp tall at 360 dp, tapping sets the mode and saves it on this device', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final controller = await ThemeModeController.load();
        await tester.pumpWidget(ChangeNotifierProvider<ThemeModeController>.value(
          value: controller,
          child: _app(
            SizedBox(
              width: 320,
              child: Builder(builder: (context) {
                final c = context.watch<ThemeModeController>();
                return FolkSegmented<FolkThemeMode>(
                  value: c.mode,
                  onChanged: c.setMode,
                  segments: const [
                    FolkSegment(value: FolkThemeMode.light, label: 'Light'),
                    FolkSegment(value: FolkThemeMode.dark, label: 'Dark'),
                    FolkSegment(value: FolkThemeMode.auto, label: 'Auto'),
                  ],
                );
              }),
            ),
            dark: dark,
          ),
        ));
        expect(tester.getSize(find.byType(FolkSegmented<FolkThemeMode>)).height, 48);
        expect(controller.mode, FolkThemeMode.auto, reason: 'no saved value -> Auto');

        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(controller.mode, FolkThemeMode.dark);
        expect((await SharedPreferences.getInstance()).getString(ThemeModeController.prefsKey), 'dark');

        await tester.tap(find.text('Light'));
        await tester.pumpAndSettle();
        expect(controller.mode, FolkThemeMode.light);
        expect((await SharedPreferences.getInstance()).getString(ThemeModeController.prefsKey), 'light');

        await tester.tap(find.text('Auto'));
        await tester.pumpAndSettle();
        expect(controller.mode, FolkThemeMode.auto);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('JapaTapCircle (Japa): counting never depends on animation', () {
    Future<void> pumpCircle(
      WidgetTester tester, {
      required ValueNotifier<int> taps,
      int rounds = 0,
      bool idle = true,
      bool reduce = false,
      int beadsOverride = -1,
    }) async {
      await tester.pumpWidget(_app(
        ValueListenableBuilder<int>(
          valueListenable: taps,
          builder: (context, count, _) => JapaTapCircle(
            beads: beadsOverride >= 0 ? beadsOverride : count % 108,
            rounds: rounds,
            idleEnabled: idle,
            onTap: () => taps.value++,
          ),
        ),
        reduce: reduce,
      ));
    }

    double idleScale(WidgetTester tester) => tester
        .widget<Transform>(find.byKey(const ValueKey<String>('japa-idle-scale')))
        .transform
        .getMaxScaleOnAxis();

    testWidgets('every tap counts at 25 taps per second (40 taps, ripples and ring running)', (tester) async {
      final taps = ValueNotifier<int>(0);
      await pumpCircle(tester, taps: taps);
      for (var i = 0; i < 40; i++) {
        await tester.tapAt(tester.getCenter(find.byType(JapaTapCircle)));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(taps.value, 40, reason: 'no tap was delayed, debounced or dropped');
      expect(find.text('40'), findsOneWidget, reason: 'the number shown is the true count');
      expect(tester.takeException(), isNull);
    });

    testWidgets('taps with no time between them (same frame) all count', (tester) async {
      final taps = ValueNotifier<int>(0);
      await pumpCircle(tester, taps: taps);
      final center = tester.getCenter(find.byType(JapaTapCircle));
      for (var i = 0; i < 30; i++) {
        await tester.tapAt(center);
      }
      expect(taps.value, 30);
    });

    testWidgets('the number always equals the true count while the ring is still easing', (tester) async {
      final taps = ValueNotifier<int>(0);
      await pumpCircle(tester, taps: taps);
      final center = tester.getCenter(find.byType(JapaTapCircle));
      for (var i = 1; i <= 12; i++) {
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 20)); // mid ring animation
        expect(find.text('$i'), findsOneWidget);
      }
    });

    testWidgets('the tap zone is the full content width and at least the circle row tall; taps in the corners and at both edges count', (tester) async {
      final taps = ValueNotifier<int>(0);
      await tester.pumpWidget(_app(
        SizedBox(
          width: 320,
          child: ValueListenableBuilder<int>(
            valueListenable: taps,
            builder: (context, count, _) => JapaTapCircle(
              beads: count % 108,
              rounds: 0,
              idleEnabled: false,
              onTap: () => taps.value++,
            ),
          ),
        ),
      ));
      final zone = tester.getRect(find.byType(JapaTapCircle));
      expect(zone.width, 320, reason: 'full width of the content area');
      expect(zone.height, greaterThanOrEqualTo(272), reason: 'at least the circle row');

      final points = <String, Offset>{
        'top-left corner': zone.topLeft + const Offset(2, 2),
        'top-right corner': zone.topRight + const Offset(-2, 2),
        'bottom-left corner': zone.bottomLeft + const Offset(2, -2),
        'bottom-right corner': zone.bottomRight + const Offset(-2, -2),
        'left edge, mid height': Offset(zone.left + 2, zone.center.dy),
        'right edge, mid height': Offset(zone.right - 2, zone.center.dy),
        'centre': zone.center,
      };
      var expected = 0;
      for (final entry in points.entries) {
        await tester.tapAt(entry.value);
        expected++;
        expect(taps.value, expected, reason: '${entry.key} must count');
      }
      // Just outside the zone does not count.
      await tester.tapAt(zone.topLeft + const Offset(-6, -6));
      expect(taps.value, expected);
    });

    testWidgets('no animation leaks: after rapid taps everything settles (one ripple controller, restarted)', (tester) async {
      final taps = ValueNotifier<int>(0);
      await pumpCircle(tester, taps: taps, idle: false);
      final center = tester.getCenter(find.byType(JapaTapCircle));
      for (var i = 0; i < 60; i++) {
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 15));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no ripple or ring ticker left running');
      expect(taps.value, 60);
    });

    testWidgets('idle pulse: runs when idle, stops while tapping, resumes ~1.5 s after the last tap', (tester) async {
      final taps = ValueNotifier<int>(0);
      await pumpCircle(tester, taps: taps);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(idleScale(tester), greaterThan(1.0), reason: 'pulsing while idle');

      await tester.tapAt(tester.getCenter(find.byType(JapaTapCircle)));
      await tester.pump(); // a ticker's first frame has zero elapsed time
      await tester.pump(const Duration(milliseconds: 400));
      expect(idleScale(tester), closeTo(1.0, 1e-9), reason: 'settled while tapping');
      await tester.pump(const Duration(milliseconds: 900));
      expect(idleScale(tester), closeTo(1.0, 1e-9), reason: 'still off before the resume delay');

      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 600));
      expect(idleScale(tester), greaterThan(1.0), reason: 'resumed after the pause in tapping');
    });

    testWidgets('idle pulse is off when the app is backgrounded (idleEnabled false) and with reduce-motion', (tester) async {
      final taps = ValueNotifier<int>(0);
      await pumpCircle(tester, taps: taps, idle: false);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(idleScale(tester), closeTo(1.0, 1e-9));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no ticker while backgrounded');

      await pumpCircle(tester, taps: taps, reduce: true);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(idleScale(tester), closeTo(1.0, 1e-9));
      await tester.tapAt(tester.getCenter(find.byType(JapaTapCircle)));
      expect(taps.value, 1, reason: 'counting still works with reduce-motion');
    });

    testWidgets('a natural round completion (107 -> 0, rounds + 1) shows the true 0 and settles', (tester) async {
      var rounds = 0;
      var beads = 107;
      late StateSetter setOuter;
      await tester.pumpWidget(_app(
        StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return JapaTapCircle(beads: beads, rounds: rounds, idleEnabled: false, onTap: () {});
        }),
      ));
      await tester.pumpAndSettle();
      setOuter(() {
        beads = 0;
        rounds = 1;
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('0'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Insights (CompetitionPage): four tiles, same role gating, no endless motion', () {
    Future<_PushCounter> pumpInsights(WidgetTester tester, String role, {bool dark = false}) async {
      final observer = _PushCounter();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<ColorProvider>(
        // The existing "Coming soon" snackbar helper reads ColorProvider.
        create: (_) => ColorProvider(loadLegacyPrefs: false),
        child: MaterialApp(
          theme: dark ? FolkTheme.dark : FolkTheme.light,
          navigatorObservers: [observer],
          home: CompetitionPage(role: role, username: 'Asha', loadReports: (_) async => {}),
        ),
      ));
      await tester.pumpAndSettle();
      observer.pushes = 0; // the home route itself
      return observer;
    }

    // The Graphical Analysis tile is gone (its graphs are in the card above).
    const titles = [
      'Leaderboard',
      'Weekly Performance',
      'Monthly Performance',
      'Best Performer',
    ];

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('$theme: all four tiles show at 360 dp without overflow, and nothing keeps animating', (tester) async {
        await pumpInsights(tester, 'Stay at FOLK', dark: dark);
        for (final t in titles) {
          await tester.scrollUntilVisible(find.text(t), 200, scrollable: find.byType(Scrollable).first);
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('Graphical Analysis'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0,
            reason: 'the endless bobbing (.repeat) is gone: every ticker has finished');
      });
    }

    // One tile per test, so a pushed screen is never built (no frame is pumped
    // after a push and the tree is torn down with the screen still unbuilt).
    // Leaderboard, Weekly and Monthly Performance are open to every residence (each
    // shows the student's own category and gender), and so is Best Performer.
    const open = {'Leaderboard', 'Weekly Performance', 'Monthly Performance', 'Best Performer'};
    final opensFor = <String, Set<String>>{
      'Stay at FOLK': open,
      'Stay at Hostel': open,
      'Stay at Localite': open,
    };
    for (final entry in opensFor.entries) {
      for (final title in titles) {
        final opens = entry.value.contains(title);
        testWidgets('${entry.key} / $title: ${opens ? "opens one screen" : "says Coming soon, opens nothing"}', (tester) async {
          final observer = await pumpInsights(tester, entry.key);
          await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(find.text(title));
          await tester.pump();
          await tester.tap(find.text(title));
          expect(observer.pushes, opens ? 1 : 0);
          if (!opens) {
            await tester.pump();
            expect(find.text('Coming soon'), findsWidgets);
            await tester.pump(const Duration(seconds: 5));
          }
        });
      }
    }
  });

  group('Sadhana calendar day states (SadhanaDayCell), light and dark at 360 dp', () {
    Widget cell(SadhanaDayState state, {bool selected = false, int day = 7}) => SizedBox(
          width: 360 / 7,
          height: 43,
          child: SadhanaDayCell(day: day, state: state, selected: selected),
        );

    Container innerCircle(WidgetTester tester, String label) => tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first);

    BoxDecoration deco(Container c) => c.decoration as BoxDecoration;
    TextStyle style(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style!;

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      final colors = dark ? FolkColors.dark : FolkColors.light;

      testWidgets('$theme: submitted = green gradient circle, bold dark text', (tester) async {
        await tester.pumpWidget(_app(cell(SadhanaDayState.submitted), dark: dark));
        final d = deco(innerCircle(tester, '7'));
        expect(d.shape, BoxShape.circle);
        expect((d.gradient as LinearGradient).colors, FolkGradients.calendarSubmitted.colors);
        expect(style(tester, '7').color, FolkColors.onGradient);
        expect(style(tester, '7').fontWeight, FontWeight.w700);
      });

      testWidgets('$theme: missed = soft red circle, dark red text', (tester) async {
        await tester.pumpWidget(_app(cell(SadhanaDayState.missed), dark: dark));
        final d = deco(innerCircle(tester, '7'));
        expect(d.color, colors.calendarMissedBg);
        expect(d.gradient, isNull);
        expect(style(tester, '7').color, colors.calendarMissedText);
      });

      testWidgets('$theme: today (not submitted) = filled ink circle, inverted text', (tester) async {
        await tester.pumpWidget(_app(cell(SadhanaDayState.today), dark: dark));
        final d = deco(innerCircle(tester, '7'));
        expect(d.color, colors.primaryBg);
        expect(style(tester, '7').color, colors.primaryFg);
        expect(style(tester, '7').fontWeight, FontWeight.w700);
      });

      testWidgets('$theme: today, submitted = green gradient circle with an ink ring', (tester) async {
        await tester.pumpWidget(_app(cell(SadhanaDayState.todaySubmitted), dark: dark));
        final d = deco(innerCircle(tester, '7'));
        expect((d.gradient as LinearGradient).colors, FolkGradients.calendarSubmitted.colors);
        final border = d.border as Border;
        expect(border.top.color, colors.primaryBg);
        expect(border.top.width, 2.5);
        expect(style(tester, '7').color, FolkColors.onGradient);
      });

      testWidgets('$theme: future = no fill, muted text', (tester) async {
        await tester.pumpWidget(_app(cell(SadhanaDayState.future), dark: dark));
        final d = deco(innerCircle(tester, '7'));
        expect(d.color, isNull);
        expect(d.gradient, isNull);
        expect(d.border, isNull);
        expect(style(tester, '7').color, colors.disabledText);
      });

      testWidgets('$theme: a selected day keeps its state colours and gains a violet ring, same size', (tester) async {
        for (final state in SadhanaDayState.values) {
          await tester.pumpWidget(_app(cell(state), dark: dark));
          final plain = tester.getSize(find.ancestor(of: find.text('7'), matching: find.byType(Container)).first);
          await tester.pumpWidget(_app(cell(state, selected: true), dark: dark));
          final selected = tester.getSize(find.ancestor(of: find.text('7'), matching: find.byType(Container)).first);
          expect(selected, plain, reason: '$state: selecting never changes the circle size');
          final outer = tester.widget<Container>(find
              .ancestor(of: find.text('7'), matching: find.byType(Container))
              .at(1));
          expect(((outer.decoration as BoxDecoration).border as Border).top.color, FolkCalendarTokens.selectedRing);
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('$theme: a month of every state at 360 dp, circles 33-43 dp and truly round, no overflow', (tester) async {
        const states = SadhanaDayState.values;
        await tester.pumpWidget(_app(
          SizedBox(
            width: 360,
            child: Table(
              children: [
                for (var week = 0; week < 5; week++)
                  TableRow(children: [
                    for (var d = 0; d < 7; d++)
                      SizedBox(
                        height: 43,
                        child: SadhanaDayCell(
                          day: week * 7 + d + 1,
                          state: states[(week * 7 + d) % states.length],
                          selected: week == 2 && d == 3,
                        ),
                      ),
                  ]),
              ],
            ),
          ),
          dark: dark,
        ));
        expect(tester.takeException(), isNull);
        final size = tester.getSize(find.ancestor(of: find.text('1'), matching: find.byType(Container)).first);
        expect(size.width, inInclusiveRange(33, 43));
        expect(size.width, size.height);
      });

      testWidgets('$theme: legend shows Submitted, Missed and Today', (tester) async {
        await tester.pumpWidget(_app(const SizedBox(width: 320, child: SadhanaLegend()), dark: dark));
        for (final label in ['Submitted', 'Missed', 'Today']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('table_calendar accepts the day builder, selects a day on tap, and months slide sideways', (tester) async {
      final today = DateTime.now();
      DateTime? picked;
      DateTime focused = today;
      await tester.pumpWidget(_app(
        StatefulBuilder(builder: (context, setState) {
          return SizedBox(
            width: 320,
            child: TableCalendar(
              focusedDay: focused,
              selectedDayPredicate: (d) => isSameDay(picked, d),
              onDaySelected: (selectedDay, focusedDay) => setState(() {
                picked = selectedDay;
                focused = focusedDay;
              }),
              onPageChanged: (d) => focused = d,
              firstDay: DateTime(today.year, today.month - 1, 1),
              lastDay: today,
              rowHeight: 320 * 0.12,
              calendarStyle: const CalendarStyle(outsideDaysVisible: false),
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              calendarBuilders: CalendarBuilders(
                prioritizedBuilder: (context, date, _) => SadhanaDayCell(
                  day: date.day,
                  state: isSameDay(date, today)
                      ? SadhanaDayState.today
                      : date.isAfter(today)
                          ? SadhanaDayState.future
                          : date.day.isEven
                              ? SadhanaDayState.submitted
                              : SadhanaDayState.missed,
                  selected: isSameDay(picked, date),
                ),
              ),
            ),
          );
        }),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SadhanaDayCell), findsWidgets);

      // Tap day 1 of this month (always in range): it becomes selected.
      await tester.tap(find.text('1').first);
      await tester.pumpAndSettle();
      expect(picked?.day, 1);

      // Months slide: a sideways swipe moves to the previous month.
      final month = DateFormat.yMMMM().format(today);
      expect(find.text(month), findsOneWidget);
      expect(find.byType(PageView), findsWidgets, reason: 'months live in a horizontal PageView');
      await tester.fling(find.byType(PageView).first, const Offset(300, 0), 1200);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final previous = DateFormat.yMMMM().format(DateTime(today.year, today.month - 1, 1));
      expect(find.text(previous), findsOneWidget, reason: 'swiping sideways paged to the previous month');
    });
  });

  group('components at 360 dp, both themes', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('PrimaryButton $theme: 56 tall, taps', (tester) async {
        var taps = 0;
        await tester.pumpWidget(_app(
          SizedBox(width: 320, child: PrimaryButton(label: 'Start', onPressed: () => taps++)),
          dark: dark,
        ));
        expect(tester.getSize(find.byType(PrimaryButton)).height, FolkShape.buttonHeight);
        await tester.tap(find.byType(PrimaryButton));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('RoundIconButton $theme: 48 dp target', (tester) async {
        var taps = 0;
        await tester.pumpWidget(_app(
          RoundIconButton(icon: Icons.add, semanticLabel: 'Add', onPressed: () => taps++),
          dark: dark,
        ));
        final size = tester.getSize(find.byType(RoundIconButton));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        await tester.tap(find.byType(RoundIconButton));
        expect(taps, 1);
      });

      testWidgets('FolkChip $theme: at least 48 dp tall', (tester) async {
        await tester.pumpWidget(_app(
          FolkChip(label: 'English', selected: true, selectedStyle: FolkGradientStyle.violet, onTap: () {}),
          dark: dark,
        ));
        expect(tester.getSize(find.byType(FolkChip)).height, greaterThanOrEqualTo(48));
      });

      testWidgets('GradientCard $theme: text is #1E1B2E in every style', (tester) async {
        for (final style in FolkGradientStyle.values) {
          await tester.pumpWidget(_app(
            SizedBox(width: 320, child: GradientCard(style: style, height: 112, child: const Text('Books'))),
            dark: dark,
          ));
          final text = tester.widget<Text>(find.text('Books'));
          final resolved = DefaultTextStyle.of(tester.element(find.text('Books'))).style.color;
          expect(text.style?.color ?? resolved, FolkColors.onGradient, reason: '$style');
        }
      });

      testWidgets('StatTile $theme renders', (tester) async {
        await tester.pumpWidget(_app(
          SizedBox(width: 160, child: StatTile(value: '12', label: 'rounds', style: FolkGradientStyle.coral)),
          dark: dark,
        ));
        expect(find.text('12'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('FloatingPillNavBar $theme: 68 tall, 4 tabs fit, label only on active', (tester) async {
        var index = 1;
        await tester.pumpWidget(_app(
          StatefulBuilder(builder: (context, setState) {
            return FloatingPillNavBar(
              currentIndex: index,
              onTap: (i) => setState(() => index = i),
              items: [
                for (final label in ['Insights', 'Journey', 'Sadhana', 'Profile'])
                  FolkNavItem(
                    label: label,
                    iconBuilder: (context, selected, color) => Icon(Icons.circle, size: 22, color: color),
                  ),
              ],
            );
          }),
          dark: dark,
        ));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(FloatingPillNavBar)).height, closeTo(FolkShape.navHeight + FolkShape.navInset, .1));
        expect(find.text('Journey'), findsOneWidget);
        expect(find.text('Sadhana'), findsNothing);
        await tester.tap(find.byType(GestureDetector).at(2));
        await tester.pumpAndSettle();
        expect(index, 2);
        expect(find.text('Sadhana'), findsOneWidget);
        expect(find.text('Journey'), findsNothing);
        expect(tester.takeException(), isNull, reason: 'no overflow at 360 dp');
      });
    }

    testWidgets('GhostPlaceholder breathes, and stays still with reduce-motion', (tester) async {
      Future<double> opacityAt(Duration t) async {
        await tester.pump(t);
        final box = tester.widget<Container>(find.descendant(of: find.byType(GhostPlaceholder), matching: find.byType(Container)).first);
        return (box.decoration as BoxDecoration).color!.a;
      }

      await tester.pumpWidget(_app(const GhostPlaceholder(width: 300, height: 120)));
      final a = await opacityAt(Duration.zero);
      final b = await opacityAt(const Duration(milliseconds: 900));
      expect(a, isNot(closeTo(b, 1e-4)), reason: 'pulses');
      expect(a, inInclusiveRange(.08 * .45 - .001, .08 + .001));
      expect(b, inInclusiveRange(.08 * .45 - .001, .08 + .001));

      await tester.pumpWidget(_app(const GhostPlaceholder(width: 300, height: 120), reduce: true));
      final c = await opacityAt(Duration.zero);
      final d = await opacityAt(const Duration(milliseconds: 900));
      expect(c, closeTo(d, 1e-6), reason: 'static with reduce motion');
    });

    testWidgets('PressScale shrinks to 0.97 while pressed, never with reduce-motion', (tester) async {
      Future<double> scaleWhilePressed({required bool reduce}) async {
        await tester.pumpWidget(_app(
          SizedBox(width: 200, child: PrimaryButton(label: 'Go', onPressed: () {})),
          reduce: reduce,
        ));
        final gesture = await tester.startGesture(tester.getCenter(find.byType(PrimaryButton)));
        await tester.pump(const Duration(milliseconds: 200));
        final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale;
        await gesture.up();
        await tester.pumpAndSettle();
        return scale;
      }

      expect(await scaleWhilePressed(reduce: false), FolkMotion.pressScale);
      expect(await scaleWhilePressed(reduce: true), 1);
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onCreate, required this.child});

  final VoidCallback onCreate;
  final Widget child;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// Counts pushes so a tile's tap can be checked without building the target screen.
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}
