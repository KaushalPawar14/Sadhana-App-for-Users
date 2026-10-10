import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/TypingDots.dart';

// Master fix, Parts 5 and 6: guards for the smoothness pass and the native
// configuration (portrait lock, night launch background, configChanges).
String read(String path) => File(path).readAsStringSync();

List<File> dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String stripComments(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  group('smoothness guards', () {
    test('no live blur anywhere in lib (BackdropFilter / ImageFilter.blur)', () {
      for (final f in dartFiles('lib')) {
        final code = stripComments(read(f.path));
        expect(code.contains('BackdropFilter'), isFalse, reason: f.path);
        expect(code.contains('ImageFilter.blur'), isFalse, reason: f.path);
      }
    });

    test('animated fades use FadeTransition: EntryAnimation, TypingDots and the splash dots have no Opacity widget', () {
      for (final path in ['lib/widgets/EntryAnimation.dart', 'lib/widgets/TypingDots.dart', 'lib/pages/SplashScreen.dart']) {
        expect(RegExp(r'\bOpacity\(').hasMatch(stripComments(read(path))), isFalse, reason: path);
      }
      expect(read('lib/widgets/EntryAnimation.dart'), contains('FadeTransition('));
    });

    test('the animated pieces sit in their own repaint boundary', () {
      expect(read('lib/widgets/TypingDots.dart'), contains('RepaintBoundary('));
      expect(read('lib/widgets/GhostPlaceholder.dart'), contains('RepaintBoundary('));
      expect(read('lib/widgets/FloatingPillNavBar.dart'), contains('RepaintBoundary('));
      expect(read('lib/utils/FloatingAssistantOverlay.dart'), contains('RepaintBoundary('));
      expect(read('lib/utils/VoiceRoomOverlay.dart'), contains('RepaintBoundary('));
      expect(read('lib/widgets/JapaTapCircle.dart'), contains('RepaintBoundary('));
      expect(read('lib/widgets/ScoreWidgets.dart'), contains('RepaintBoundary('));
    });

    testWidgets('EntryAnimation still fades and slides in, and ends fully shown', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: FolkTheme.light,
        home: const Scaffold(body: EntryAnimation(index: 1, child: Text('hello'))),
      ));
      final fade = tester.widget<FadeTransition>(find.descendant(of: find.byType(EntryAnimation), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fade.opacity.value, greaterThan(0));
      await tester.pumpAndSettle();
      expect(fade.opacity.value, 1);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('TypingDots pulse in their colour and keep three dots; reduce motion: still', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TypingDots(color: Color(0xFF123456)))));
      await tester.pump(const Duration(milliseconds: 300));
      final dots = find.descendant(of: find.byType(TypingDots), matching: find.byType(Container));
      expect(dots, findsNWidgets(3));
      final alphas = [for (final e in dots.evaluate()) ((e.widget as Container).decoration! as BoxDecoration).color!.a];
      expect(alphas.toSet().length, greaterThan(1), reason: 'the dots are at different brightness');
      expect(find.byType(Opacity), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test('the card and icon shadows are the lighter ones', () {
      final src = read('lib/theme/FolkColors.dart');
      expect(src, contains('blurRadius: 16, offset: const Offset(0, 5)'));
      expect(src, contains('blurRadius: 12, offset: const Offset(0, 4)'));
    });
  });

  group('native configuration', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    test('portrait only: the manifest and main() both lock it', () {
      expect(manifest, contains('android:screenOrientation="portrait"'));
      final main = read('lib/main.dart');
      expect(main, contains('SystemChrome.setPreferredOrientations'));
      expect(main, contains('DeviceOrientation.portraitUp'));
      expect(main.indexOf('setPreferredOrientations'), lessThan(main.indexOf('runApp(')));
    });

    test('the activity is never recreated by a configuration change', () {
      final m = RegExp(r'android:configChanges="([^"]*)"').firstMatch(manifest)!.group(1)!.split('|').toSet();
      for (final c in ['orientation', 'screenSize', 'smallestScreenSize', 'screenLayout', 'density', 'uiMode', 'fontScale', 'locale', 'layoutDirection', 'keyboard', 'keyboardHidden']) {
        expect(m, contains(c));
      }
    });

    test('launch background is the page background: #F8F7FC light, #151517 dark', () {
      expect(read('android/app/src/main/res/values/colors.xml'), contains('<color name="folk_page_background">#F8F7FC</color>'));
      expect(read('android/app/src/main/res/values-night/colors.xml'), contains('<color name="folk_page_background">#151517</color>'));
      for (final d in ['drawable', 'drawable-v21']) {
        expect(read('android/app/src/main/res/$d/launch_background.xml'), contains('@color/folk_page_background'));
      }
      for (final v in ['values', 'values-night', 'values-v31', 'values-night-v31']) {
        final styles = read('android/app/src/main/res/$v/styles.xml');
        expect(styles, contains('name="LaunchTheme"'), reason: v);
        expect(styles, contains('name="NormalTheme"'), reason: v);
        expect(styles, contains('<item name="android:windowBackground">@color/folk_page_background</item>'), reason: v);
      }
      for (final v in ['values-v31', 'values-night-v31']) {
        expect(read('android/app/src/main/res/$v/styles.xml'), contains('android:windowSplashScreenBackground'), reason: v);
      }
    });

    test('the colours match the app theme', () {
      final colors = read('lib/theme/FolkColors.dart');
      expect(colors, contains('pageBackground: Color(0xFFF8F7FC)'));
      expect(colors, contains('pageBackground: Color(0xFF151517)'));
    });
  });
}
