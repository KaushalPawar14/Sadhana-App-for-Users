import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BottomNavBar.dart' show hostHeader, hostNavItems, kHostTabTitles;
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:folk_app/widgets/NavHostGhost.dart';
import 'package:folk_app/widgets/StartupWaiting.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// What is drawn while the app waits to learn where to go: the tab host's own
// ghost frame when signed in, the plain themed background when not; never the
// old mala loader, never a spinner. Real app fonts, 360 dp.
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

Widget host(Widget home, {bool dark = false, bool reduce = false}) => MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: home,
    );

Finder anySpinner() => find.byWidgetPredicate((w) =>
    w is CircularProgressIndicator ||
    w is LinearProgressIndicator ||
    w is RefreshProgressIndicator ||
    w.runtimeType.toString() == 'CustomLoader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    for (final scale in scales) {
      for (final reduce in [false, true]) {
        final s = '${dark ? 'dark' : 'light'}, text $scale, reduce motion $reduce';

        testWidgets('signed in: the tab host\'s ghost frame, no loader, nothing overflows — $s', (tester) async {
          phone(tester, scale);
          await tester.pumpWidget(host(const StartupWaiting(signedIn: true), dark: dark, reduce: reduce));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byType(NavHostGhost), findsOneWidget);
          expect(anySpinner(), findsNothing);
          final pill = tester.widget<FloatingPillNavBar>(find.byType(FloatingPillNavBar));
          expect(pill.currentIndex, 2);
          expect(pill.items.map((i) => i.label).toList(), kHostTabTitles);
          // the pill is on screen and cannot be tapped yet
          expect(tester.getRect(find.byType(FloatingPillNavBar)).bottom, lessThanOrEqualTo(800));
          expect(find.ancestor(of: find.byType(FloatingPillNavBar), matching: find.byType(IgnorePointer)), findsWidgets);
        });
      }
    }
  }

  testWidgets("the ghost sits exactly where it sits inside the tab host: below the title bar's room, so nothing jumps", (tester) async {
    for (final scale in scales) {
      phone(tester, scale);
      // the title bar's height, drawn by the very function the tab host uses
      await tester.pumpWidget(host(Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            ColoredBox(key: const Key('bar'), color: Colors.transparent, child: Builder(builder: (c) => hostHeader(c, 2))),
          ]),
        ),
      )));
      final bar = tester.getRect(find.byKey(const Key('bar')));
      await tester.pumpWidget(host(const StartupWaiting(signedIn: true)));
      await tester.pump();
      expect(tester.getTopLeft(find.byType(NavHostGhost)).dy, closeTo(bar.bottom, 0.6), reason: 'text $scale');
    }
  });

  testWidgets('the hidden title bar draws nothing and is not read out', (tester) async {
    phone(tester, 1.0);
    await tester.pumpWidget(host(const StartupWaiting(signedIn: true)));
    await tester.pump();
    // the title bar is kept as room only: its Visibility is off, so it is neither painted nor read out
    final vis = tester.widget<Visibility>(find.byType(Visibility));
    expect(vis.visible, isFalse);
    expect(vis.maintainSize, isTrue);
  });

  for (final dark in [false, true]) {
    testWidgets('signed out: only the themed page background, no ghost, no pill, no spinner — ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const StartupWaiting(signedIn: false), dark: dark));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavHostGhost), findsNothing);
      expect(find.byType(FloatingPillNavBar), findsNothing);
      expect(anySpinner(), findsNothing);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.body, isNull);
      expect(scaffold.backgroundColor, (dark ? FolkColors.dark : FolkColors.light).pageBackground);
    });
  }

  test('main.dart: the waiting state is StartupWaiting; no loader import; the routing is untouched', () {
    final src = File('lib/main.dart').readAsStringSync();
    expect(src.contains('CustomLoader'), isFalse);
    expect(src.contains('MalaLoading'), isFalse);
    expect(File('lib/utils/MalaLoading.dart').existsSync(), isFalse, reason: 'the old loader is deleted');
    expect(src.contains('CircularProgressIndicator'), isFalse);
    expect(src, contains('return StartupWaiting(signedIn: currentUser != null);'));

    // Everything that DECIDES where to go, exactly as it was before this change.
    const decision = '''             if (snapshot.connectionState == ConnectionState.waiting) {''';
    expect(src, contains(decision));
    final from = src.indexOf('} else if (snapshot.hasData) {');
    final to = src.indexOf(': WelcomePage(),', from) + ': WelcomePage(),'.length;
    final block = src.substring(from, to).replaceAll(RegExp(r'\s+'), ' ');
    expect(
      block,
      '} else if (snapshot.hasData) { if (snapshot.data == null) { '
      '// Name missing → WelcomePage return WelcomePage(); } else if (snapshot.data == true) { '
      '// Data complete → pass role to CurvedNavBar return CurvedNavBar(role); } else { '
      '// Missing some fields → CompleteProfilePage return CompleteProfilePage(); } } else { '
      '// Fallback → WelcomePage return WelcomePage(); } }, ) : WelcomePage(),',
    );
    expect(src, contains('home: currentUser != null'));
    expect(src, contains('future: _dataComplete,'));
    expect(src, contains('_dataComplete = isUserDataComplete();'));
    expect(src, contains('if (currentUser == null) return false;'));
  });

  test('no loader is left on the launch path: SplashScreen, AnimatedLogin, WelcomePage and the tab host', () {
    for (final f in ['lib/pages/SplashScreen.dart', 'lib/main.dart', 'lib/pages/Welcome.dart', 'lib/utils/BottomNavBar.dart', 'lib/widgets/StartupWaiting.dart', 'lib/widgets/NavHostGhost.dart']) {
      final src = File(f).readAsStringSync();
      for (final w in ['CustomLoader', 'CircularProgressIndicator', 'LinearProgressIndicator', 'CupertinoActivityIndicator']) {
        expect(src.contains(w), isFalse, reason: '$f uses $w');
      }
    }
    expect(hostNavItems, isNotNull);
  });
}
