import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/AssistantScreen.dart' show ChatTurn, chatBubble;
import 'package:folk_app/services/DailyMessageService.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/widgets/DailyMessageCard.dart';
import 'package:folk_app/widgets/GradientCard.dart';
import 'package:folk_app/widgets/Group2Widgets.dart';

import 'text_scale_test.dart' show loadAppFonts;

// Today's message and the Profile name card wear the sky-blue token (#CDE8FF ->
// #8EC5F5, 135 degrees), the same in light and dark; the text on it stays ink.
// Nothing else changed colour. Real app fonts loaded.
const _skyColors = [Color(0xFFCDE8FF), Color(0xFF8EC5F5)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  Widget app(Widget child, bool dark) => MaterialApp(
        theme: dark ? FolkTheme.dark : FolkTheme.light,
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true), child: w!),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  // The gradient of the nearest decorated container above [of].
  LinearGradient gradientAbove(WidgetTester tester, Finder of) {
    for (final e in find.ancestor(of: of, matching: find.byType(Container)).evaluate()) {
      final d = (e.widget as Container).decoration;
      if (d is BoxDecoration && d.gradient is LinearGradient) return d.gradient as LinearGradient;
    }
    fail('no gradient above ${of.describeMatch(Plurality.one)}');
  }

  test('the token: #CDE8FF -> #8EC5F5 at 135 degrees (top-left to bottom-right)', () {
    expect(FolkGradients.sky.colors, _skyColors);
    expect(FolkGradients.sky.begin, Alignment.topLeft);
    expect(FolkGradients.sky.end, Alignment.bottomRight);
    expect(FolkGradients.of(FolkGradientStyle.sky), FolkGradients.sky);
  });

  test('no other gradient changed', () {
    expect(FolkGradients.green.colors, const [Color(0xFFC4EED8), Color(0xFF82D3A8)]);
    expect(FolkGradients.violet.colors, const [Color(0xFFDDD2FF), Color(0xFFAE95F7)]);
    expect(FolkGradients.saffron.colors, const [Color(0xFFFFE48F), Color(0xFFFFB65A)]);
    expect(FolkGradients.coral.colors, const [Color(0xFFFFCFC6), Color(0xFFFF9E98)]);
    expect(FolkGradients.warm.colors, const [Color(0xFFFFE9B8), Color(0xFFFFC978)]);
    expect(FolkGradients.profileMenuIcon.colors, FolkGradients.saffron.colors);
    expect(FolkGradients.insightToday.colors, const [Color(0xFFFFCB7A), Color(0xFFFFA94D)]);
    expect(FolkGradients.calendarSubmitted.colors, const [Color(0xFF8FE0A8), Color(0xFF4FBF7F)]);
    expect(FolkColors.onGradient, const Color(0xFF1E1B2E));
    expect(FolkColors.onGradientSecondary, const Color.fromRGBO(30, 27, 46, .78));
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('1. Journey card ($mode): sky blue, radius 28, ink text', (tester) async {
      await tester.pumpWidget(app(
        const JourneyTodayMessage(
            state: DailyMessageState(DailyMessageStatus.ready, text: 'You kept **your promise**.'), onTap: _noop),
        dark,
      ));
      final card = find.byType(DailyMessageCard);
      expect(gradientAbove(tester, find.descendant(of: card, matching: find.byType(RichText)).first).colors, _skyColors);
      final deco = tester
          .widgetList<Container>(find.descendant(of: card, matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.gradient != null);
      expect((deco.borderRadius as BorderRadius).topLeft.x, 28);
      final span = (tester.widget<RichText>(find.descendant(of: card, matching: find.byType(RichText)).last).text as TextSpan);
      expect(_colourOf(span), FolkColors.onGradient);
    });

    testWidgets('2. Ask card ($mode): sky blue, ink text', (tester) async {
      await tester.pumpWidget(app(
        Builder(builder: (c) => chatBubble(c, const ChatTurn('You kept your promise.', fromStudent: false, isDailyMessage: true))),
        dark,
      ));
      final text = find.descendant(of: find.byType(DailyMessageCard), matching: find.byType(RichText)).last;
      expect(gradientAbove(tester, text).colors, _skyColors);
      expect(_colourOf(tester.widget<RichText>(text).text as TextSpan), FolkColors.onGradient);
    });

    testWidgets('3. History card ($mode): sky blue, ink text', (tester) async {
      await tester.pumpWidget(app(const DailyHistoryCard(label: 'Today', text: 'You kept your promise.'), dark));
      expect(gradientAbove(tester, find.text('You kept your promise.')).colors, _skyColors);
      expect(tester.widget<Text>(find.text('You kept your promise.')).style!.color, FolkColors.onGradient);
    });

    testWidgets('5. a GradientCard in the sky style (the Profile name card) paints the token ($mode)', (tester) async {
      await tester.pumpWidget(app(
        const GradientCard(style: FolkGradientStyle.sky, decorate: false, child: Text('Name')),
        dark,
      ));
      expect(gradientAbove(tester, find.text('Name')).colors, _skyColors);
    });
  }

  // 4 and 5 need Firebase to build on screen, so the wiring is checked in the source.
  test('4. the "Preparing today\'s message" banner and 5. the Profile name card use the sky token', () {
    final ask = File('lib/pages/AssistantScreen.dart').readAsStringSync();
    final banner = ask.substring(ask.indexOf('if (_preparingDailyMessage)'));
    expect(banner.substring(0, 400), contains('FolkGradients.sky'));
    final profile = File('lib/pages/Profile.dart').readAsStringSync();
    final card = profile.substring(profile.indexOf('/// Profile header'));
    expect(card.substring(0, 300), contains('FolkGradientStyle.sky'));
  });

  test('the warm token is still used only where it was (nothing else moved)', () {
    final uses = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final l in f.readAsLinesSync()) {
        if (l.contains('FolkGradients.warm') || l.contains('FolkGradientStyle.warm,') || l.contains('FolkGradientStyle.warm)')) {
          uses.add(f.path.replaceAll('\\', '/').split('/').last);
        }
      }
    }
    expect(uses.where((u) => u != 'FolkTokens.dart').toList(), ['ServiceBankScreen.dart']);
  });
}

void _noop() {}

// The message is rich text: Text.rich wraps the widget's own span, whose style
// carries the colour.
Color? _colourOf(TextSpan root) => (root.children!.single as TextSpan).style?.color;
