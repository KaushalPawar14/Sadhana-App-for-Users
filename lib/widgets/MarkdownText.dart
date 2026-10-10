import 'package:flutter/material.dart';

import '../utils/SimpleMarkdown.dart';

// The assistant's reply text with its simple markdown shown properly (see
// `utils/SimpleMarkdown.dart` for what is understood): bold, italic, bullets
// with a hanging indent, numbered lines, headings (bold, a little larger, no "#")
// and paragraph spacing. The theme's own style is passed in, so fonts, colours
// and sizes are exactly what they were for plain text; only bold, italic and
// the heading sizes change.
//
// With [maxLines] (the Journey card's four lines) the reply is flattened into
// ONE paragraph — bullets as "• " lines — so a single line limit and ellipsis
// can apply to all of it.
//
// Only assistant text goes through this. What the student typed stays plain.
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  static const double _h1 = 1.25;
  static const double _h2 = 1.15;
  static const double _h3 = 1.08;

  static double headingScale(int level) =>
      level <= 1 ? _h1 : (level == 2 ? _h2 : _h3);

  TextSpan _spans(List<MdSpan> spans, {TextStyle? base}) {
    final b = base ?? style;
    return TextSpan(
      style: b,
      children: [
        for (final s in spans)
          TextSpan(
            text: s.text,
            style: TextStyle(
              fontWeight: s.bold ? FontWeight.w700 : null,
              fontStyle: s.italic ? FontStyle.italic : null,
            ),
          ),
      ],
    );
  }

  // Everything as one paragraph (for a line limit).
  TextSpan _flat(List<MdBlock> blocks) {
    final children = <InlineSpan>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(TextSpan(text: b.spaceBefore ? '\n\n' : '\n'));
      switch (b.kind) {
        case MdKind.bullet:
          children.add(const TextSpan(text: '•  '));
        case MdKind.numbered:
          children.add(TextSpan(text: '${b.number}. '));
        case MdKind.heading:
        case MdKind.paragraph:
          break;
      }
      children.add(_spans(b.spans,
          base: b.kind == MdKind.heading
              ? style.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: (style.fontSize ?? 15) * headingScale(b.level))
              : null));
    }
    return TextSpan(style: style, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(text);
    if (blocks.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    if (maxLines != null) {
      return Text.rich(
        _flat(blocks),
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.ellipsis,
      );
    }

    final fontSize = style.fontSize ?? 15;
    // The marker column follows the student's text size, so "1." never wraps.
    final scaledSize = MediaQuery.textScalerOf(context).scale(fontSize);
    final gap = fontSize * .45;
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(SizedBox(height: b.spaceBefore ? gap * 2 : gap));
      switch (b.kind) {
        case MdKind.paragraph:
          children.add(Text.rich(_spans(b.spans)));
        case MdKind.heading:
          children.add(Text.rich(_spans(
            b.spans,
            base: style.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: fontSize * headingScale(b.level),
            ),
          )));
        case MdKind.bullet:
        case MdKind.numbered:
          final marker = b.kind == MdKind.bullet ? '•' : '${b.number}.';
          // The marker column is as wide as its text needs (a "10." is wider than
          // a "1.") and never narrower than a bullet, so the lines hang.
          final markerWidth = b.kind == MdKind.bullet
              ? scaledSize * 1.1
              : scaledSize * (marker.length <= 2 ? 1.5 : 2.0);
          children.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: markerWidth,
                child: Text(marker, style: style, softWrap: false),
              ),
              Expanded(child: Text.rich(_spans(b.spans))),
            ],
          ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
