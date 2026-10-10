import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/InsightTile.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:table_calendar/table_calendar.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The Submit Sadhana button: directly under the calendar, at the content width,
// scrolling with the page and clear of the floating pill; violet in both modes
// with ink text always. And every tab's last item clears the pill.
void size(WidgetTester tester, Size s, double scale, {double systemBottom = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = s;
  tester.view.padding = FakeViewPadding(bottom: systemBottom);
  tester.view.viewPadding = FakeViewPadding(bottom: systemBottom);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Widget host(Widget home, {bool dark = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

// A tab stand-in that pads its bottom exactly as the Journey and Profile tabs do.
Widget longTab(double extra) => Builder(
      builder: (context) => ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, FloatingPillNavBar.reservedHeight(context) + extra),
        children: [
          for (var i = 0; i < 30; i++) Container(height: 60, margin: const EdgeInsets.only(bottom: 8), color: Colors.grey),
          Container(key: const ValueKey('last'), height: 60, color: Colors.purple),
        ],
      ),
    );

Widget nav({int initial = 2, Widget? journey, Widget? profile}) => CurvedNavBar(
      'Stay at FOLK',
      loadUser: () async => (name: 'Asha', role: 'Stay at FOLK'),
      buildScreens: (n, r) => [
        CompetitionPage(role: 'Stay at FOLK', username: 'Asha', loadReports: (_) async => {}),
        journey ?? longTab(FolkSpace.lg),
        CalendarPage(username: 'Asha', role: 'Stay at FOLK', datesStream: Stream.value(<String>{})),
        profile ?? longTab(FolkSpace.lg),
      ],
      journeyUnseen: Stream<bool>.value(false),
    );

Rect pillTop(WidgetTester tester) => tester.getRect(find.descendant(of: find.byType(FloatingPillNavBar), matching: find.byType(Container)).first);

Future<void> tapTab(WidgetTester tester, int index) async {
  final icons = [
    [Icons.bar_chart_rounded],
    [Icons.spa, Icons.spa_outlined],
    [Icons.event_available_outlined],
    [Icons.person_rounded, Icons.person_outline_rounded],
  ][index];
  for (final icon in icons) {
    final f = find.descendant(of: find.byType(FloatingPillNavBar), matching: find.byIcon(icon));
    if (f.evaluate().isNotEmpty) {
      await tester.tap(f.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
}

// Scrolls to the end by dragging from the page margin (x = 8), outside any card:
// a vertical drag on the calendar itself belongs to the calendar.
Future<void> toEnd(WidgetTester tester, Finder scrollable) async {
  for (var i = 0; i < 6; i++) {
    await tester.dragFrom(const Offset(8, 300), const Offset(0, -2500));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  // ---------------------------------------------------------------- the button
  group('Submit Sadhana — violet in both modes, ink text, same in every state', () {
    Widget button({bool dark = false, VoidCallback? onPressed, bool loading = false, IconData? icon}) => host(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Builder(
                builder: (context) => PrimaryButton(
                  gradient: FolkGradients.submitSadhana,
                  label: '✨ Submit Sadhana',
                  onPressed: onPressed,
                  loading: loading,
                  icon: icon,
                ),
              ),
            ),
          ),
          dark: dark,
        );

    LinearGradient? gradientOf(WidgetTester tester) {
      final ink = tester.widget<Ink>(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(Ink)));
      return (ink.decoration as BoxDecoration?)?.gradient as LinearGradient?;
    }

    test('token: violet #DDD2FF -> #AE95F7 in both light and dark', () {
      expect(FolkGradients.submitSadhana.colors, const [Color(0xFFDDD2FF), Color(0xFFAE95F7)], reason: 'violet in both modes');
      expect(FolkColors.onGradient, const Color(0xFF1E1B2E));
    });

    for (final dark in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'}: gradient background; text, icon and spinner are #1E1B2E when enabled, loading and disabled', (tester) async {
        size(tester, const Size(360, 800), 1.0);
        for (final state in ['enabled', 'loading', 'disabled']) {
          await tester.pumpWidget(button(
            dark: dark,
            onPressed: state == 'disabled' ? null : () {},
            loading: state == 'loading',
            icon: Icons.edit_note,
          ));
          await tester.pump();
          final g = gradientOf(tester)!;
          expect(g.colors, const [Color(0xFFDDD2FF), Color(0xFFAE95F7)], reason: '$state: violet in ${dark ? 'dark' : 'light'}');
          final size0 = tester.getSize(find.byType(PrimaryButton));
          expect(size0.height, FolkShape.buttonHeight, reason: 'same size in every state');
          if (state == 'loading') {
            final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
            expect(spinner.color, FolkColors.onGradient);
          } else {
            expect(tester.widget<Text>(find.text('✨ Submit Sadhana')).style!.color, FolkColors.onGradient, reason: state);
            expect(tester.widget<Icon>(find.byIcon(Icons.edit_note)).color, FolkColors.onGradient, reason: state);
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }

    testWidgets('other PrimaryButtons are unchanged: ink on cream, cream on ink', (tester) async {
      size(tester, const Size(360, 800), 1.0);
      for (final dark in [false, true]) {
        await tester.pumpWidget(host(Scaffold(body: Center(child: PrimaryButton(label: 'Save', onPressed: () {}))), dark: dark));
        await tester.pumpAndSettle(); // the theme change eases over
        final colors = dark ? FolkColors.dark : FolkColors.light;
        expect(tester.widget<Text>(find.text('Save')).style!.color, colors.primaryFg);
        expect(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(Ink)), findsNothing, reason: 'the same structure as before');
      }
    });
  });

  // ------------------------------------------------------ the button: position
  group('Submit Sadhana — under the calendar, never behind the pill', () {
    const sizes = [Size(360, 640), Size(360, 800), Size(412, 915)];
    for (final s in sizes) {
      for (final systemBottom in [24.0, 48.0]) {
        for (final dark in [false, true]) {
          for (final scale in scales) {
            testWidgets('${s.width.toInt()}x${s.height.toInt()}, system bar $systemBottom, ${dark ? 'dark' : 'light'}, text $scale', (tester) async {
              size(tester, s, scale, systemBottom: systemBottom);
              await tester.pumpWidget(host(nav(), dark: dark));
              await tester.pump();
              await tester.pump();
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);

              final button = find.byWidgetPredicate((w) => w is PrimaryButton && w.gradient != null);
              expect(button, findsOneWidget);
              await toEnd(tester, find.byType(SingleChildScrollView));
              expect(tester.takeException(), isNull, reason: 'nothing overflows');

              final b = tester.getRect(button);
              final pill = pillTop(tester);
              expect(pill.bottom, closeTo(s.height - systemBottom - FolkShape.navInset, 1), reason: 'the pill sits above the system bar');
              expect(pill.top - b.bottom, greaterThanOrEqualTo(24 - .5),
                  reason: 'button bottom ${b.bottom} vs pill top ${pill.top} (needs at least 12; has 24)');

              // directly under the calendar card, normal card spacing, content width
              final card = tester.getRect(find.ancestor(of: find.byType(TableCalendar<dynamic>), matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).boxShadow != null)).first);
              expect(b.top - card.bottom, inInclusiveRange(12, 16), reason: 'directly below the calendar');
              expect(b.left, 20);
              expect(b.right, s.width - 20, reason: 'content width, never the full screen');
              expect(b.height, FolkShape.buttonHeight);
            });
          }
        }
      }
    }

    testWidgets('it scrolls with the page: it is not pinned to the bottom of the screen', (tester) async {
      size(tester, const Size(360, 640), 1.6, systemBottom: 48);
      await tester.pumpWidget(host(nav()));
      await tester.pumpAndSettle();
      final button = find.byWidgetPredicate((w) => w is PrimaryButton && w.gradient != null);
      final before = tester.getRect(button).top;
      await tester.dragFrom(const Offset(8, 300), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(tester.getRect(button).top, lessThan(before), reason: 'it moves when the page scrolls');
    });

    test('the cause is gone: the host keeps viewPadding (source check), and the Calendar pads by reservedHeight + 24', () {
      final nav = File('lib/utils/BottomNavBar.dart').readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join(' ');
      expect(nav.contains('MediaQuery.removePadding'), isFalse);
      expect(nav, contains('padding: MediaQuery.paddingOf(context).copyWith(bottom: 0)'));
      expect(File('lib/pages/Calendar.dart').readAsStringSync(), contains('FolkSpace.xxl + FloatingPillNavBar.reservedHeight(context)'));
    });

    testWidgets('ROOT CAUSE reproduced: with the old host (removePadding zeroes viewPadding) the last item ends 48 dp BEHIND the pill; with the fix it clears it', (tester) async {
      size(tester, const Size(360, 640), 1.0, systemBottom: 48);
      Widget pill() => FloatingPillNavBar(
            currentIndex: 0,
            onTap: (_) {},
            items: [
              for (final l in ['A', 'B']) FolkNavItem(label: l, iconBuilder: (c, sel, color) => Icon(Icons.circle, color: color)),
            ],
          );
      // the host as it was
      await tester.pumpWidget(host(Builder(
        builder: (outer) => Scaffold(
          extendBody: true,
          body: MediaQuery.removePadding(context: outer, removeBottom: true, child: longTab(0)),
          bottomNavigationBar: pill(),
        ),
      )));
      await tester.pumpAndSettle();
      await toEnd(tester, find.byType(ListView));
      final old = pillTop(tester).top - tester.getRect(find.byKey(const ValueKey('last'))).bottom;
      expect(old, closeTo(-48, 1), reason: 'the last item was 48 dp (the system bar) behind the pill');

      // the host as it is now
      await tester.pumpWidget(host(Builder(
        builder: (outer) => Scaffold(
          extendBody: true,
          body: MediaQuery(
            data: MediaQuery.of(outer).copyWith(padding: MediaQuery.paddingOf(outer).copyWith(bottom: 0)),
            child: longTab(0),
          ),
          bottomNavigationBar: pill(),
        ),
      )));
      await tester.pumpAndSettle();
      await toEnd(tester, find.byType(ListView));
      final fixed = pillTop(tester).top - tester.getRect(find.byKey(const ValueKey('last'))).bottom;
      expect(fixed, closeTo(0, 1), reason: 'with no extra padding the item ends exactly at the pill top');
    });
  });

  // ------------------------------------------------------------- the other tabs
  group('Every tab: the last item clears the pill by at least 12 dp (360x640, text 1.6)', () {
    for (final systemBottom in [0.0, 24.0, 48.0]) {
      testWidgets('Journey stand-in with the real padding formula, system bar $systemBottom', (tester) async {
        size(tester, const Size(360, 640), 1.6, systemBottom: systemBottom);
        await tester.pumpWidget(host(nav()));
        await tester.pumpAndSettle();
        await tapTab(tester, 1);
        await toEnd(tester, find.byType(ListView));
        expect(tester.takeException(), isNull);
        final last = tester.getRect(find.byKey(const ValueKey('last')));
        expect(pillTop(tester).top - last.bottom, greaterThanOrEqualTo(12 - .5));
      });

      testWidgets('Profile stand-in with the real padding formula, system bar $systemBottom', (tester) async {
        size(tester, const Size(360, 640), 1.6, systemBottom: systemBottom);
        await tester.pumpWidget(host(nav()));
        await tester.pumpAndSettle();
        await tapTab(tester, 3);
        await toEnd(tester, find.byType(ListView));
        final last = tester.getRect(find.byKey(const ValueKey('last')));
        expect(pillTop(tester).top - last.bottom, greaterThanOrEqualTo(12 - .5));
      });

      testWidgets('Insights (the real page): its last tile clears the pill, system bar $systemBottom', (tester) async {
        size(tester, const Size(360, 640), 1.6, systemBottom: systemBottom);
        await tester.pumpWidget(host(nav()));
        await tester.pumpAndSettle();
        await tapTab(tester, 0);
        await toEnd(tester, find.byType(ListView));
        expect(tester.takeException(), isNull);
        final tile = tester.getRect(find.byWidgetPredicate((w) => w is InsightTile && w.title == 'Want to improve?'));
        expect(pillTop(tester).top - tile.bottom, greaterThanOrEqualTo(12 - .5), reason: 'tile bottom ${tile.bottom}, pill top ${pillTop(tester).top}');
      });
    }

    test('the Journey and Profile tabs pad their bottom by reservedHeight plus at least 12 (source check of the real files)', () {
      final journey = File('lib/pages/ABCDEScreen.dart').readAsStringSync();
      expect(journey, contains('FloatingPillNavBar.reservedHeight(context) + FolkSpace.lg'));
      final profile = File('lib/pages/Profile.dart').readAsStringSync();
      expect(RegExp(r'FloatingPillNavBar\.reservedHeight\(context\) \+ FolkSpace\.lg').allMatches(profile).length, 2, reason: 'the page and its ghost');
      expect(File('lib/pages/Competition.dart').readAsStringSync(), contains('FloatingPillNavBar.reservedHeight(context) + 12'));
    });
  });
}
