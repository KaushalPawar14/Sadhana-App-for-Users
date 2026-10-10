import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/services/DailyMessageService.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/ThemeModeController.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FloatingPillNavBar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_scale_test.dart' show loadAppFonts;

// Master fix, Parts 3 and 4: today's message service, and the tab host (keep
// the four tabs alive; a theme switch keeps the current tab).
void phone(WidgetTester tester, [double scale = 1.0]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

// ----------------------------------------------------------------- the service
class Rig {
  Rig({
    this.uid = 'u1',
    this.accepted = true,
    this.existing,
    this.generated = 'You kept your promise to Krishna yesterday.',
    this.fail = false,
    this.date = '09-10-2026',
  });

  String uid;
  bool accepted;
  String? existing;
  String generated;
  bool fail;
  String date;

  int calls = 0;
  int disclosureReads = 0;
  int existingReads = 0;
  Completer<void>? gate; // holds the callable open until completed
  Completer<bool>? disclosureGate;

  DailyMessageService build() => DailyMessageService(
        currentUid: () => uid,
        today: () => date,
        callGenerate: () async {
          calls++;
          if (gate != null) await gate!.future;
          if (fail) throw StateError('offline');
          return {'isNew': true, 'text': generated, 'replyDocId': 'r1'};
        },
        readDisclosure: (u) async {
          disclosureReads++;
          if (disclosureGate != null) return disclosureGate!.future;
          return accepted;
        },
        readExisting: (u, d) async {
          existingReads++;
          return existing;
        },
      );
}

Future<String?> cachedRaw() async =>
    (await SharedPreferences.getInstance()).getString('dailyMessage.cache');

// A service that only counts how often the tab host starts it.
class CountingService extends DailyMessageService {
  int opened = 0;
  @override
  Future<void> onAppOpened() async => opened++;
}

// ------------------------------------------------------------- tab probes
final Map<String, int> inits = {};
final Map<String, int> disposals = {};
final Map<String, int> builds = {};

class Probe extends StatefulWidget {
  const Probe(this.name, {super.key, this.ticking = false});
  final String name;
  final bool ticking;

  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int taps = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    inits[widget.name] = (inits[widget.name] ?? 0) + 1;
    if (widget.ticking) _c.repeat();
  }

  @override
  void dispose() {
    disposals[widget.name] = (disposals[widget.name] ?? 0) + 1;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds[widget.name] = (builds[widget.name] ?? 0) + 1;
    return EntryAnimation(
      index: 0,
      child: GestureDetector(
        onTap: () => setState(() => taps++),
        child: Text('${widget.name} taps=$taps'),
      ),
    );
  }
}

Widget host({
  DailyMessageService? service,
  bool reduce = true,
  bool dark = false,
  bool ticking = false,
}) =>
    MaterialApp(
      theme: dark ? FolkTheme.dark : FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: navBar(service: service, ticking: ticking),
    );

Widget navBar({DailyMessageService? service, bool ticking = false}) => CurvedNavBar(
      'Stay at Hostel',
      loadUser: () async => (name: 'Asha', role: 'Stay at Hostel'),
      buildScreens: (n, r) => [
        Probe('insights', ticking: ticking),
        const Probe('journey'),
        const Probe('sadhana'),
        const Probe('profile'),
      ],
      journeyUnseen: Stream<bool>.value(false),
      dailyMessage: service ?? CountingService(),
    );

// Taps a tab in the pill by its icon (selected and unselected forms).
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
  fail('tab $index not found');
}

// The visible tab (IndexedStack index).
int visibleTab(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    inits.clear();
    disposals.clear();
    builds.clear();
  });

  // ============================================================== Part 3
  group('DailyMessageService — one call per student per day', () {
    test('app open, disclosure accepted, no message yet: ONE call; loading then ready; cached', () async {
      final rig = Rig();
      final svc = rig.build();
      final seen = <DailyMessageStatus>[];
      svc.state.addListener(() => seen.add(svc.state.value.status));
      await svc.onAppOpened();
      expect(rig.calls, 1);
      expect(seen, contains(DailyMessageStatus.loading));
      expect(svc.state.value.status, DailyMessageStatus.ready);
      expect(svc.state.value.text, rig.generated);
      expect(await cachedRaw(), allOf(contains('"uid":"u1"'), contains('"date":"09-10-2026"'), contains(rig.generated)));
    });

    test('coming back to the app the same day makes no further call and no further reads', () async {
      final rig = Rig();
      final svc = rig.build();
      await svc.onAppOpened();
      final reads = rig.disclosureReads + rig.existingReads;
      await svc.onAppOpened();
      await svc.onAppOpened();
      expect(rig.calls, 1);
      expect(rig.disclosureReads + rig.existingReads, reads);
    });

    test('Journey and Ask share one in-flight call (Ask joins the open-time call)', () async {
      final rig = Rig()..gate = Completer<void>();
      final svc = rig.build();
      final opening = svc.onAppOpened();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(rig.calls, 1, reason: 'started in the background on open');
      final fromAsk = svc.ensureToday('u1'); // Ask opens while it is generating
      final again = svc.ensureToday('u1');
      expect(rig.calls, 1, reason: 'joined, not a second call');
      rig.gate!.complete();
      final a = await fromAsk;
      await again;
      await opening;
      expect(rig.calls, 1);
      expect(a.isNew, isTrue, reason: 'Ask reloads its transcript');
      expect(a.failed, isFalse);
      expect(svc.state.value.text, rig.generated);
    });

    test('Ask first, then the app-open check: still one call', () async {
      final rig = Rig()..gate = Completer<void>();
      final svc = rig.build();
      final fromAsk = svc.ensureToday('u1');
      final opening = svc.onAppOpened();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      rig.gate!.complete();
      await fromAsk;
      await opening;
      expect(rig.calls, 1);
    });

    test('disclosure not accepted: nothing is generated, state says so', () async {
      final rig = Rig(accepted: false);
      final svc = rig.build();
      await svc.onAppOpened();
      expect(rig.calls, 0);
      expect(svc.state.value.status, DailyMessageStatus.needsDisclosure);
      expect(await cachedRaw(), isNull);
    });

    test('a message already on the server is read, never regenerated', () async {
      final rig = Rig(existing: 'Already made earlier today.');
      final svc = rig.build();
      await svc.onAppOpened();
      expect(rig.calls, 0);
      expect(svc.state.value.status, DailyMessageStatus.ready);
      expect(svc.state.value.text, 'Already made earlier today.');
    });

    test('cached for today: ready at once (never loading), refreshed quietly after', () async {
      SharedPreferences.setMockInitialValues({
        'dailyMessage.cache': '{"uid":"u1","date":"09-10-2026","text":"From the device."}',
      });
      final rig = Rig(existing: 'From the device.')..disclosureGate = Completer<bool>();
      final svc = rig.build();
      final seen = <DailyMessageStatus>[];
      svc.state.addListener(() => seen.add(svc.state.value.status));
      final opening = svc.onAppOpened();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // the server check is still pending, yet the text is already there
      expect(svc.state.value.status, DailyMessageStatus.ready);
      expect(svc.state.value.text, 'From the device.');
      rig.disclosureGate!.complete(true);
      await opening;
      expect(seen, isNot(contains(DailyMessageStatus.loading)));
      expect(rig.calls, 0);
    });

    test('cached for yesterday or for another student is not used', () async {
      SharedPreferences.setMockInitialValues({
        'dailyMessage.cache': '{"uid":"u1","date":"08-10-2026","text":"Yesterday."}',
      });
      var rig = Rig();
      var svc = rig.build();
      final seen = <DailyMessageStatus>[];
      svc.state.addListener(() => seen.add(svc.state.value.status));
      await svc.onAppOpened();
      expect(seen.first, DailyMessageStatus.loading);
      expect(svc.state.value.text, rig.generated);

      SharedPreferences.setMockInitialValues({
        'dailyMessage.cache': '{"uid":"someone-else","date":"09-10-2026","text":"Not yours."}',
      });
      rig = Rig();
      svc = rig.build();
      await svc.onAppOpened();
      expect(rig.calls, 1);
      expect(svc.state.value.text, isNot('Not yours.'));
    });

    test('a failure shows failed (tap to open) and is tried again on the next app open', () async {
      final rig = Rig(fail: true);
      final svc = rig.build();
      await svc.onAppOpened();
      expect(rig.calls, 1);
      expect(svc.state.value.status, DailyMessageStatus.failed);
      expect(svc.state.value.text, isNull);
      // next open (the failure was not remembered as "done")
      rig.fail = false;
      await svc.onAppOpened();
      expect(rig.calls, 2);
      expect(svc.state.value.status, DailyMessageStatus.ready);
    });

    test('a day change while the app is open asks again (and only once)', () async {
      final rig = Rig();
      final svc = rig.build();
      await svc.onAppOpened();
      rig.date = '10-10-2026';
      rig.generated = 'A new day.';
      await svc.onAppOpened();
      await svc.onAppOpened();
      expect(rig.calls, 2);
      expect(svc.state.value.text, 'A new day.');
    });

    test('ensureToday when it is already ready makes no call; isNew only for the call made here', () async {
      final rig = Rig();
      final svc = rig.build();
      await svc.onAppOpened();
      final again = await svc.ensureToday('u1');
      expect(rig.calls, 1);
      expect(again.failed, isFalse);
      expect(again.text, rig.generated);
    });

    test('a failed call from Ask reports failed and leaves the state failed', () async {
      final rig = Rig(fail: true);
      final svc = rig.build();
      final r = await svc.ensureToday('u1');
      expect(r.failed, isTrue);
      expect(r.isNew, isFalse);
      expect(svc.state.value.status, DailyMessageStatus.failed);
    });
  });

  // ============================================================== Part 4
  group('Tab host — the four tabs stay alive', () {
    testWidgets('a tab is built on its first visit only, then kept (no rebuild, no refetch)', (tester) async {
      phone(tester);
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(visibleTab(tester), 2, reason: 'opens on Sadhana');
      expect(inits, {'sadhana': 1}, reason: 'only the visited tab is built');

      await tester.tap(find.text('sadhana taps=0'));
      await tester.pump();
      expect(find.text('sadhana taps=1'), findsOneWidget);

      await tapTab(tester, 1);
      expect(visibleTab(tester), 1);
      expect(inits, {'sadhana': 1, 'journey': 1});
      await tapTab(tester, 3);
      await tapTab(tester, 0);
      expect(inits, {'sadhana': 1, 'journey': 1, 'profile': 1, 'insights': 1});

      final buildsBefore = Map<String, int>.from(builds);
      for (final i in [2, 1, 3, 0, 2, 1]) {
        await tapTab(tester, i);
      }
      expect(inits, {'sadhana': 1, 'journey': 1, 'profile': 1, 'insights': 1}, reason: 'nothing recreated');
      expect(builds, buildsBefore, reason: 'switching tabs rebuilt no tab screen');
      await tapTab(tester, 2);
      expect(find.text('sadhana taps=1'), findsOneWidget, reason: 'its state survived');
      expect(disposals, isEmpty);
    });

    testWidgets('entry animations play on a tab\'s first visit only', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(reduce: false));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      await tapTab(tester, 1);
      await tester.pumpAndSettle();
      FadeTransition fade(String name) => tester.widget<FadeTransition>(find
          .descendant(of: find.widgetWithText(EntryAnimation, '$name taps=0', skipOffstage: false), matching: find.byType(FadeTransition))
          .first);
      expect(fade('journey').opacity.value, 1);
      await tapTab(tester, 2);
      // back on a visited tab: fully shown at once, no fade-in replay
      expect(fade('sadhana').opacity.value, 1);
      await tester.pump(const Duration(milliseconds: 10));
      expect(fade('sadhana').opacity.value, 1);
    });

    testWidgets('when the host is disposed every visited tab is disposed (streams and listeners cancel)', (tester) async {
      phone(tester);
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tapTab(tester, 1);
      await tapTab(tester, 3);
      expect(disposals, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(disposals, {'sadhana': 1, 'journey': 1, 'profile': 1});
      expect(inits.containsKey('insights'), isFalse, reason: 'never visited, never built');
    });

    testWidgets('a hidden tab does not tick; the visible one does', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(ticking: true));
      await tester.pump();
      await tester.pump();
      await tapTab(tester, 0); // Insights has the repeating controller
      expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'visible: ticking');
      await tapTab(tester, 2);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0, reason: 'hidden behind another tab: no ticker running');
      await tapTab(tester, 0);
      expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'ticks again when shown');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the Journey tab\'s header stays hidden and others show their title', (tester) async {
      phone(tester);
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(find.text('Sadhana'), findsWidgets);
      await tapTab(tester, 1);
      expect(find.text('Journey'), findsOneWidget, reason: 'only the pill label; Journey greets by name, no title bar');
      expect(find.descendant(of: find.byType(FloatingPillNavBar), matching: find.text('Journey')), findsOneWidget);
    });
  });

  group('Tab host — today\'s message starts when the app opens or resumes', () {
    testWidgets('started once on open, again on resume (the service decides if work is needed)', (tester) async {
      phone(tester);
      final svc = CountingService();
      await tester.pumpWidget(host(service: svc));
      await tester.pump();
      expect(svc.opened, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(svc.opened, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(svc.opened, 2);
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(svc.opened, 2, reason: 'observer removed with the host');
    });
  });

  // ---------------------------------------------------- Part 4a: theme switch
  group('Light / Dark / Auto keeps the current tab', () {
    // The same shape as AnimatedLogin: a FutureBuilder that decides what to
    // show, rebuilt by `context.watch<ThemeModeController>()`. `hoisted` is the
    // fix (the future is created once); `false` is the old code (a new future
    // on every build).
    Widget loginLike(ThemeModeController theme, {required bool hoisted}) => ChangeNotifierProvider<ThemeModeController>.value(
          value: theme,
          child: _LoginLike(hoisted: hoisted),
        );

    for (final startTab in [0, 1, 2, 3]) {
      testWidgets('switching theme from tab $startTab: the tab stays (fixed)', (tester) async {
        phone(tester);
        final theme = await ThemeModeController.load();
        await tester.pumpWidget(loginLike(theme, hoisted: true));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        if (startTab != 2) await tapTab(tester, startTab);
        expect(visibleTab(tester), startTab);
        final initsBefore = Map<String, int>.from(inits);

        for (final mode in [FolkThemeMode.dark, FolkThemeMode.light, FolkThemeMode.auto]) {
          await theme.setMode(mode);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(visibleTab(tester), startTab, reason: '$mode from tab $startTab');
          expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'no loader flash');
        }
        expect(inits, initsBefore, reason: 'no tab was recreated by the theme change');
      });
    }

    testWidgets('the old code reproduces the bug: a theme switch sent the student back to Sadhana', (tester) async {
      phone(tester);
      final theme = await ThemeModeController.load();
      await tester.pumpWidget(loginLike(theme, hoisted: false));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tapTab(tester, 1);
      expect(visibleTab(tester), 1);
      await theme.setMode(FolkThemeMode.dark);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(visibleTab(tester), 2, reason: 'recreated on its default tab');
    });
  });
}

// A stand-in for `AnimatedLogin`'s build: the FutureBuilder -> CurvedNavBar
// path, rebuilt by the theme controller.
class _LoginLike extends StatefulWidget {
  const _LoginLike({required this.hoisted});
  final bool hoisted;

  @override
  State<_LoginLike> createState() => _LoginLikeState();
}

class _LoginLikeState extends State<_LoginLike> {
  late final Future<bool?> _once = _complete();
  Future<bool?> _complete() async => true;

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeModeController>().themeMode;
    return MaterialApp(
      theme: FolkTheme.light,
      darkTheme: FolkTheme.dark,
      themeMode: mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: FutureBuilder<bool?>(
        future: widget.hoisted ? _once : _complete(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return navBar();
        },
      ),
    );
  }
}
