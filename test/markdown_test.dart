import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/AssistantScreen.dart' show ChatTurn, chatBubble;
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SimpleMarkdown.dart';
import 'package:folk_app/widgets/DailyMessageCard.dart';
import 'package:folk_app/widgets/MarkdownText.dart';

import 'text_scale_test.dart' show scales, loadAppFonts;

// The assistant's markdown, with the real app fonts loaded (FontLoader, via
// `loadAppFonts`): the parser, and how it is drawn.
List<MdSpan> inline(String s) => parseInline(s);

String joined(List<MdSpan> spans) => spans.map((s) => s.text).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('inline', () {
    test('bold, italic (* and _), bold italic, nested', () {
      expect(inline('a **b** c'), const [MdSpan('a '), MdSpan('b', bold: true), MdSpan(' c')]);
      expect(inline('a *b* c'), const [MdSpan('a '), MdSpan('b', italic: true), MdSpan(' c')]);
      expect(inline('a _b_ c'), const [MdSpan('a '), MdSpan('b', italic: true), MdSpan(' c')]);
      expect(inline('a __b__ c'), const [MdSpan('a '), MdSpan('b', bold: true), MdSpan(' c')]);
      expect(inline('***b***'), const [MdSpan('b', bold: true, italic: true)]);
      expect(inline('**bold *and italic* bold**'), const [
        MdSpan('bold ', bold: true),
        MdSpan('and italic', bold: true, italic: true),
        MdSpan(' bold', bold: true),
      ]);
      expect(inline('*it **bold** it*'), const [
        MdSpan('it ', italic: true),
        MdSpan('bold', bold: true, italic: true),
        MdSpan(' it', italic: true),
      ]);
    });

    test('well-formed markup leaves no stray asterisks', () {
      for (final s in ['**Note:** text', 'See *this* and **that**.', '(**bold**)', '"**bold**"', '**a** **b**', 'x *y*, *z*']) {
        expect(joined(inline(s)).contains('*'), isFalse, reason: s);
      }
    });

    test('asterisks and underscores inside words stay text', () {
      expect(inline('5*3 = 15'), const [MdSpan('5*3 = 15')]);
      expect(inline('2 * 3 * 4'), const [MdSpan('2 * 3 * 4')]);
      expect(inline('use snake_case_name here'), const [MdSpan('use snake_case_name here')]);
      expect(inline('a*b*c'), const [MdSpan('a*b*c')]);
      expect(inline('price: 5**2'), const [MdSpan('price: 5**2')]);
    });

    test('unclosed, empty and lone markers stay as written (a reply still streaming in)', () {
      expect(inline('**bold wor'), const [MdSpan('**bold wor')]);
      expect(inline('hello *ita'), const [MdSpan('hello *ita')]);
      expect(inline('****'), const [MdSpan('****')]);
      expect(inline('** **'), const [MdSpan('** **')]);
      expect(inline('end *'), const [MdSpan('end *')]);
      expect(inline('**a** and **b'), const [MdSpan('a', bold: true), MdSpan(' and **b')]);
      expect(inline(''), isEmpty);
    });

    test('a backslash escapes a marker', () {
      expect(inline(r'\*not italic\*'), const [MdSpan('*not italic*')]);
    });

    test('Hindi, Gujarati and Telugu text with bold and italic', () {
      expect(inline('यह **श्रीकृष्ण** का नाम है'), const [MdSpan('यह '), MdSpan('श्रीकृष्ण', bold: true), MdSpan(' का नाम है')]);
      expect(inline('આ **ભગવાન** છે, *સરસ* છે'), const [
        MdSpan('આ '),
        MdSpan('ભગવાન', bold: true),
        MdSpan(' છે, '),
        MdSpan('સરસ', italic: true),
        MdSpan(' છે'),
      ]);
      expect(inline('ఇది **కృష్ణ నామం** అని'), const [MdSpan('ఇది '), MdSpan('కృష్ణ నామం', bold: true), MdSpan(' అని')]);
      // a marker glued to a word of the same script is text, as with Latin letters
      expect(inline('శబ్ద*కోశం*'), const [MdSpan('శబ్ద*కోశం*')]);
    });

    test('NEVER throws and never loses text: every prefix of a long mixed reply (streaming), and odd inputs', () {
      const full = 'Hare Krishna! **Chanting** is *simple*:\n\n- Start with **4 rounds**\n- Add one more _each week_\n\n1. Rise early\n2. Chant with ***attention***\n\n## Tip\n5*3 stays. यह **श्रीकृष्ण** है.';
      for (var i = 0; i <= full.length; i++) {
        final prefix = full.substring(0, i);
        final blocks = parseMarkdown(prefix);
        // all letters of the prefix survive (only markers and list/heading syntax may go)
        final letters = RegExp(r'[\p{L}]', unicode: true); // list numbers are syntax, not text
        final before = letters.allMatches(prefix).length;
        final after = blocks.map((b) => b.plain).join().split('').where((c) => letters.hasMatch(c)).length;
        expect(after, before, reason: 'letters lost at prefix length $i: "$prefix"');
        if (prefix.contains('**Chanting**')) {
          expect(blocks.first.plain.contains('**'), isFalse, reason: 'closed bold is formatted at $i');
        }
      }
      for (final odd in ['', '#', '# ', '-', '- ', '1.', '* ', '**', '*', '_', '\\', '```', '\u0000', '\n\n\n', '- - - -', '# # #', '**\n**']) {
        expect(() => parseMarkdown(odd), returnsNormally, reason: odd);
      }
    });

    test('a very long reply parses fast', () {
      final text = List.generate(2000, (i) => '- item $i with **bold $i** and *italic* text, plus 5*3').join('\n');
      final sw = Stopwatch()..start();
      final blocks = parseMarkdown(text);
      expect(blocks.length, 2000);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('blocks', () {
    test('bullets (- * •), numbered lines, headings (# ## ### and deeper), paragraphs and blank lines', () {
      final blocks = parseMarkdown('# Big\n## Medium\n### Small\n#### Deeper\nplain line\nsecond line\n\n- one\n* two\n• three\n1. first\n2) second\n10. tenth');
      expect(blocks.map((b) => b.kind).toList(), [
        MdKind.heading, MdKind.heading, MdKind.heading, MdKind.heading,
        MdKind.paragraph,
        MdKind.bullet, MdKind.bullet, MdKind.bullet,
        MdKind.numbered, MdKind.numbered, MdKind.numbered,
      ]);
      expect(blocks.take(4).map((b) => b.level).toList(), [1, 2, 3, 3]);
      expect(blocks[0].plain, 'Big', reason: 'no "#" shown');
      expect(blocks[4].plain, 'plain line\nsecond line', reason: 'a line break inside a paragraph is kept');
      expect(blocks[5].spaceBefore, isTrue, reason: 'a blank line made a paragraph break');
      expect(blocks[6].spaceBefore, isFalse);
      expect(blocks.skip(8).map((b) => b.number).toList(), [1, 2, 10]);
      expect(blocks[5].plain, 'one');
    });

    test('markup inside list items and headings is formatted; text that only looks like a list stays', () {
      final blocks = parseMarkdown('- **Bold** item\n## A *tip*\n#hashtag\n-not a bullet\n3.5 rounds');
      expect(blocks[0].spans.first, const MdSpan('Bold', bold: true));
      expect(blocks[1].spans.every((s) => s.bold), isTrue);
      expect(blocks[2].kind, MdKind.paragraph);
      expect(blocks[2].plain, '#hashtag\n-not a bullet\n3.5 rounds');
    });
  });

  // ------------------------------------------------------------------ drawing
  group('MarkdownText on screen', () {
    Widget host(Widget child, {bool dark = false, double width = 360}) => MaterialApp(
          theme: dark ? FolkTheme.dark : FolkTheme.light,
          builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: c!),
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(child: child))),
        );

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

    const base = TextStyle(fontFamily: 'DM Sans', fontSize: 15, height: 1.5, color: Colors.black);

    // Every drawn run of text as (text, weight, style).
    List<(String, FontWeight?, FontStyle?)> runs(WidgetTester tester) {
      final out = <(String, FontWeight?, FontStyle?)>[];
      for (final rt in tester.widgetList<RichText>(find.descendant(of: find.byType(MarkdownText), matching: find.byType(RichText)))) {
        rt.text.visitChildren((span) {
          if (span is TextSpan && (span.text ?? '').isNotEmpty) out.add((span.text!, span.style?.fontWeight, span.style?.fontStyle));
          return true;
        });
      }
      return out;
    }

    testWidgets('bold is bold (w700), italic is italic, both together; no asterisks are drawn', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const MarkdownText('Plain **strong** and *slanted* and ***both***.', style: base)));
      final r = runs(tester);
      expect(r.firstWhere((x) => x.$1 == 'strong').$2, FontWeight.w700);
      expect(r.firstWhere((x) => x.$1 == 'slanted').$3, FontStyle.italic);
      final both = r.firstWhere((x) => x.$1 == 'both');
      expect((both.$2, both.$3), (FontWeight.w700, FontStyle.italic));
      expect(r.map((x) => x.$1).join().contains('*'), isFalse);
      expect(find.textContaining('*', findRichText: true), findsNothing);
    });

    testWidgets('bullets hang: the second line of a long bullet starts under its text, not under the bullet', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const MarkdownText('- This is a rather long bullet point that must wrap onto a second line at 360 dp wide\n1. Numbered line that also is long enough to wrap onto a second line when drawn', style: base)));
      final rows = find.descendant(of: find.byType(MarkdownText), matching: find.byType(Row));
      expect(rows, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final row = rows.at(i);
        final marker = tester.getRect(find.descendant(of: row, matching: find.byType(Text)).first);
        final body = find.descendant(of: row, matching: find.byType(RichText)).last;
        final bodyRect = tester.getRect(body);
        expect(bodyRect.left, greaterThan(marker.left + 8), reason: 'the text is indented past the marker');
        final para = tester.renderObject<RenderParagraph>(body);
        expect(para.size.height, greaterThan(15 * 1.5 * 1.5), reason: 'it wrapped to a second line');
        expect(bodyRect.left, closeTo(tester.getTopLeft(body).dx, .1), reason: 'every line of the item starts at the same x');
      }
      expect(find.text('•'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
    });

    testWidgets('headings are bold and larger, and show no "#"', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(host(const MarkdownText('# Big\n## Medium\n### Small\nbody', style: base)));
      expect(find.textContaining('#', findRichText: true), findsNothing);
      double size(String t) {
        final rt = tester.widgetList<RichText>(find.byType(RichText)).firstWhere((r) => r.text.toPlainText() == t);
        // Text.rich wraps our span in the default style; ours is the child's parent
        final inner = (rt.text as TextSpan).children!.single as TextSpan;
        return inner.style!.fontSize!;
      }

      expect(size('Big'), closeTo(15 * 1.25, .01));
      expect(size('Medium'), closeTo(15 * 1.15, .01));
      expect(size('Small'), closeTo(15 * 1.08, .01));
      expect(size('body'), 15);
      expect(runs(tester).firstWhere((x) => x.$1 == 'Big').$2, FontWeight.w700);
    });

    testWidgets('streaming: partial text never crashes and an unclosed marker is plain until it closes', (tester) async {
      phone(tester, 1.0);
      const full = 'Chant **with attention** every day, *gently*.';
      for (var i = 1; i <= full.length; i++) {
        await tester.pumpWidget(host(MarkdownText(full.substring(0, i), style: base)));
        expect(tester.takeException(), isNull, reason: 'prefix $i');
      }
      await tester.pumpWidget(host(const MarkdownText('Chant **with atten', style: base)));
      expect(runs(tester).every((x) => x.$2 != FontWeight.w700), isTrue, reason: 'nothing is bold while the marker is open');
      expect(find.textContaining('**with atten', findRichText: true), findsOneWidget);
      await tester.pumpWidget(host(const MarkdownText('Chant **with attention**', style: base)));
      expect(runs(tester).where((x) => x.$2 == FontWeight.w700).map((x) => x.$1), ['with attention']);
    });

    testWidgets('with a line limit (Journey card) it is ONE paragraph, ends in an ellipsis, bullets as "•"', (tester) async {
      phone(tester, 1.0);
      final text = '## Today\n- **First** thing to do today at home\n- Second thing\n- Third thing\n- Fourth thing\n- Fifth thing\n' * 3;
      await tester.pumpWidget(host(MarkdownText(text, style: base, maxLines: 4, overflow: TextOverflow.ellipsis)));
      final para = tester.renderObject<RenderParagraph>(find.descendant(of: find.byType(MarkdownText), matching: find.byType(RichText)));
      expect(para.didExceedMaxLines, isTrue);
      expect(para.text.toPlainText().contains('•'), isTrue);
      expect(find.descendant(of: find.byType(MarkdownText), matching: find.byType(Row)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chat bubbles: the assistant is formatted, the student stays plain', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(MaterialApp(
        theme: FolkTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(children: [
              chatBubble(context, const ChatTurn('Reply with **bold** and a list:\n- one\n- two', fromStudent: false)),
              chatBubble(context, const ChatTurn('My question has **stars** too', fromStudent: true)),
            ]),
          ),
        ),
      ));
      expect(find.textContaining('My question has **stars** too'), findsOneWidget, reason: 'the student bubble is plain');
      expect(find.textContaining('Reply with **bold**', findRichText: true), findsNothing);
      expect(runs(tester).any((x) => x.$1 == 'bold' && x.$2 == FontWeight.w700), isTrue);
      expect(find.text('•'), findsNWidgets(2));
    });

    testWidgets('the daily message card (Ask and history) shows the formatting; the Journey card keeps its 4 lines', (tester) async {
      phone(tester, 1.0);
      await tester.pumpWidget(MaterialApp(
        theme: FolkTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              DailyMessageCard(text: 'You kept **your promise**.\n\n- Keep going\n- Be steady'),
              DailyMessageCard(text: 'You kept **your promise**. Keep going with *attention* and steadiness every single day, and let every round be an offering to Krishna with love and care.', maxLines: 4),
            ]),
          ),
        ),
      ));
      final full = tester.widgetList<MarkdownText>(find.byType(MarkdownText)).toList();
      expect(full.length, 2);
      expect(full.first.maxLines, isNull);
      expect(full.last.maxLines, 4);
      expect(find.text('•'), findsNWidgets(2), reason: 'the list is drawn on the full card');
      expect(find.textContaining('**', findRichText: true), findsNothing);
    });

    for (final dark in [false, true]) {
      for (final scale in scales) {
        testWidgets('${dark ? 'dark' : 'light'}, text scale $scale at 360 dp: a long mixed reply (English, Hindi, Gujarati, Telugu) draws without overflow', (tester) async {
          phone(tester, scale);
          const reply = '# Chanting tips\nHare Krishna! **Chanting** is *simple* and **very powerful** when done with attention.\n\n'
              '- Start with **4 rounds** a day and add one more each week, keeping it steady\n'
              '- यह **श्रीकृष्ण** का नाम है — इसे ध्यान से सुनें और धीरे-धीरे जप बढ़ाएँ\n'
              '- આ **ભગવાન** નું નામ છે, *સરસ* રીતે અને ધ્યાનથી જપ કરો\n'
              '- ఇది **కృష్ణ నామం** — శ్రద్ధగా జపం చేయండి\n\n'
              '1. Rise early\n2. Chant with ***full attention***\n10. Reflect at night\n\n'
              '## Remember\nA long paragraph of plain words that keeps going so that it has to wrap across several lines on a narrow phone screen without ever being cut off.';
          await tester.pumpWidget(host(const MarkdownText(reply, style: base), dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'dark=$dark scale=$scale');
          // nothing wider than the 320 dp column
          for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
            final r = tester.getRect(find.byWidget(rt));
            expect(r.right, lessThanOrEqualTo(340.5));
          }
          expect(find.textContaining('**', findRichText: true), findsNothing);
          // numbered markers do not wrap ("10." stays on one line)
          final ten = tester.renderObject<RenderParagraph>(find.text('10.'));
          expect(ten.size.height, lessThan(15 * 1.5 * scale * 1.6));
        });
      }
    }
  });
}
