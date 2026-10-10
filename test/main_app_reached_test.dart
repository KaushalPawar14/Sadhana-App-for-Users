import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/AssistantScreen.dart' show kAssistantRouteName;
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/AssistantRouteVisibility.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/FloatingAssistantOverlay.dart';
import 'package:folk_app/utils/MainAppReached.dart';
import 'package:folk_app/utils/VoiceRoomOverlay.dart';

// The floating AI button (and the voice-room button) must not appear while a new
// student is still registering: signed in is not enough, they show only once the
// tab host (CurvedNavBar) is on screen.
final navKey = GlobalKey<NavigatorState>();

Widget page(String name) => Scaffold(body: Center(child: Text(name)));

Route<void> route(String name, {String? routeName}) =>
    MaterialPageRoute<void>(settings: RouteSettings(name: routeName), builder: (_) => page(name));

Route<void> tabHost() => MaterialPageRoute<void>(
      builder: (_) => CurvedNavBar(
        'Stay at Hostel',
        loadUser: () async => (name: 'Asha', role: 'Stay at Hostel'),
        buildScreens: (n, r) => [for (var i = 0; i < 4; i++) Text('tab $i')],
        journeyUnseen: Stream<bool>.value(false),
      ),
    );

Widget app(StreamController<String?> users) => MaterialApp(
      theme: FolkTheme.light,
      navigatorKey: navKey,
      navigatorObservers: [AssistantRouteVisibility.instance],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        // The same nesting as `AnimatedLogin`'s builder.
        child: FloatingAssistantOverlay(
          userIds: users.stream,
          buttonBuilder: (uid, hidden) => Positioned(
            right: 10,
            bottom: 100,
            child: Offstage(offstage: hidden, child: Text('AI-BUTTON $uid', key: const ValueKey('ai'))),
          ),
          child: VoiceRoomOverlay(
            userIds: users.stream,
            watcherBuilder: (uid) => Positioned(left: 10, bottom: 100, child: Text('VOICE-BUTTON $uid')),
            child: child!,
          ),
        ),
      ),
      home: page('Welcome'),
    );

Finder get ai => find.byKey(const ValueKey('ai'));
Finder get voice => find.textContaining('VOICE-BUTTON');

// The AI button is "visible" when it is in the tree and not hidden behind Offstage.
bool aiVisible(WidgetTester tester) =>
    ai.evaluate().isNotEmpty &&
    !tester.widget<Offstage>(find.ancestor(of: ai, matching: find.byType(Offstage)).first).offstage;

Future<void> go(WidgetTester tester, Route<void> r, {bool replace = false}) async {
  if (replace) {
    navKey.currentState!.pushReplacement(r);
  } else {
    navKey.currentState!.push(r);
  }
  await tester.pump();
  // the page transition (~300 ms) has to finish before the old route is gone
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> pumpNone(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late StreamController<String?> users;
  setUp(() => users = StreamController<String?>.broadcast());
  tearDown(() => users.close());

  testWidgets('hidden on every entry screen, signed in or not, including mid-registration after the mobile confirm', (tester) async {
    await tester.pumpWidget(app(users));
    users.add('u1'); // signed in the moment they pick a Google account / enter their email
    await pumpNone(tester);
    expect(find.text('Welcome'), findsOneWidget);
    expect(ai, findsNothing, reason: 'Welcome');
    expect(voice, findsNothing, reason: 'Welcome');

    for (final screen in [
      'Splash',
      'Email sign-in',
      'CompleteProfile step 1: name, gender, mobile',
      'Mobile confirm dialog done, CompleteProfile step 2: date of birth, rounds, residence',
      'ForceUpdateScreen',
      'Register',
    ]) {
      await go(tester, route(screen));
      expect(find.text(screen), findsOneWidget);
      expect(ai, findsNothing, reason: screen);
      expect(voice, findsNothing, reason: screen);
    }
    expect(MainAppReached.instance.reached.value, isFalse);
  });

  testWidgets('visible on the tab host; hides on Ask; reappears on History; saved behaviour above the pill is untouched', (tester) async {
    await tester.pumpWidget(app(users));
    users.add('u1');
    await go(tester, route('CompleteProfile step 2'));
    expect(ai, findsNothing);
    await go(tester, tabHost(), replace: true); // registration done -> main app
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('tab 2'), findsOneWidget, reason: 'the tab host is showing (Sadhana)');
    expect(ai, findsOneWidget, reason: 'the AI button is there');
    expect(aiVisible(tester), isTrue);
    expect(voice, findsOneWidget);

    await go(tester, route('Ask', routeName: kAssistantRouteName));
    expect(aiVisible(tester), isFalse, reason: 'hidden on Ask');
    await go(tester, route('History'));
    expect(aiVisible(tester), isTrue, reason: 'reappears on History (the route on top is no longer Ask)');
    navKey.currentState!.pop(); // History
    await pumpNone(tester);
    navKey.currentState!.pop(); // Ask
    await pumpNone(tester);
    expect(aiVisible(tester), isTrue, reason: 'back on the tab host');
    expect(find.text('tab 2'), findsOneWidget);
  });

  testWidgets('sign-out hides it again; the next sign-in follows the same rule', (tester) async {
    await tester.pumpWidget(app(users));
    users.add('u1');
    await go(tester, tabHost(), replace: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai, findsOneWidget);

    // sign out: the tab host is replaced by Welcome and the user goes away
    users.add(null);
    await go(tester, route('Welcome'), replace: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai, findsNothing, reason: 'signed out');
    expect(voice, findsNothing);
    expect(MainAppReached.instance.reached.value, isFalse);

    // a different student signs in and is mid-registration: still hidden
    users.add('u2');
    await go(tester, route('CompleteProfile step 1'));
    expect(ai, findsNothing);
    expect(voice, findsNothing);

    // ... and only appears when THEY reach the tab host
    await go(tester, tabHost(), replace: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('AI-BUTTON u2'), findsOneWidget);
  });

  testWidgets('even if the tab host goes away while still signed in, the button goes with it', (tester) async {
    await tester.pumpWidget(app(users));
    users.add('u1');
    await go(tester, tabHost(), replace: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai, findsOneWidget);
    await go(tester, route('Welcome'), replace: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai, findsNothing);
  });

  testWidgets('one tab host replacing another never flickers the button off', (tester) async {
    await tester.pumpWidget(app(users));
    users.add('u1');
    await go(tester, tabHost(), replace: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai, findsOneWidget);
    await go(tester, tabHost(), replace: true); // new host mounts before the old one is disposed
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai, findsOneWidget);
    expect(MainAppReached.instance.reached.value, isTrue);
  });

  test('no entry or onboarding screen builds the tab host before registration is complete (source check of every construction site)', () {
    // Every place the tab host is built, and what has to be true first.
    final sites = {
      'lib/main.dart': 'snapshot.data == true',
      'lib/pages/CompleteProfile.dart': 'CurvedNavBar(resolvedRole)',
      'lib/services/PostAuthRouter.dart': 'CurvedNavBar(role)',
    };
    for (final e in sites.entries) {
      expect(File(e.key).readAsStringSync(), contains(e.value), reason: e.key);
    }
    final main = File('lib/main.dart').readAsStringSync();
    final tab = main.indexOf('return CurvedNavBar(role)');
    expect(main.lastIndexOf('snapshot.data == true', tab), greaterThan(main.lastIndexOf('snapshot.data == null', tab)));
    // Both overlays wait for the signal; neither reads Firestore before it.
    for (final f in ['lib/utils/FloatingAssistantOverlay.dart', 'lib/utils/VoiceRoomOverlay.dart']) {
      final src = File(f).readAsStringSync();
      expect(src, contains('MainAppReached.instance.reached'), reason: f);
    }
    final nav = File('lib/utils/BottomNavBar.dart').readAsStringSync();
    expect(nav, contains('MainAppReached.instance.enter()'));
    expect(nav, contains('MainAppReached.instance.leave()'));
  });
}
