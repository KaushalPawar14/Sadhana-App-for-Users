// A small markdown reader for the assistant's replies — only what they use:
//
//   **bold**   __bold__   *italic*   _italic_   ***bold italic***
//   - item  /  * item  /  • item           bullet lines
//   1. item  /  1) item                    numbered lines
//   #  ##  ###  heading                    (shown bold, a little larger, no "#")
//   a blank line                           a paragraph break
//
// It never throws and never loses text: anything it does not recognise, an
// unclosed marker (a reply that is still streaming in), or a lone "*" stays
// exactly as it was written. An asterisk or underscore inside a word ("5*3",
// "snake_case") is text, not a marker. Pure Dart, so it is easy to test.

enum MdKind { paragraph, bullet, numbered, heading }

class MdSpan {
  const MdSpan(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is MdSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() => 'MdSpan(${bold ? 'B' : ''}${italic ? 'I' : ''}"$text")';
}

class MdBlock {
  const MdBlock(this.kind, this.spans, {this.level = 0, this.number = 0, this.spaceBefore = false});

  final MdKind kind;
  final List<MdSpan> spans;

  // Heading level (1-3).
  final int level;

  // The number of a numbered line.
  final int number;

  // True when a blank line came before this block.
  final bool spaceBefore;

  String get plain => spans.map((s) => s.text).join();
}

final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

bool _isWord(String ch) => _letterOrDigit.hasMatch(ch);

bool _isSpace(String ch) => ch.trim().isEmpty;

String _at(String s, int i) => i < 0 || i >= s.length ? '' : s[i];

// A marker of [len] characters at [i] can OPEN emphasis when the character after
// it is not a space and the one before it is not part of a word.
bool _canOpen(String s, int i, int len) {
  final next = _at(s, i + len);
  if (next.isEmpty || _isSpace(next)) return false;
  final prev = _at(s, i - 1);
  return prev.isEmpty || !_isWord(prev);
}

// ... and CLOSE it when the character before it is not a space and the one after
// it is not part of a word.
bool _canClose(String s, int k, int len) {
  final prev = _at(s, k - 1);
  if (prev.isEmpty || _isSpace(prev)) return false;
  final next = _at(s, k + len);
  return next.isEmpty || !_isWord(next);
}

int _findClose(String s, int from, String marker) {
  var k = from;
  while (k <= s.length - marker.length) {
    final ch = s[k];
    if (ch == r'\') {
      k += 2; // an escaped character cannot close
      continue;
    }
    if (s.startsWith(marker, k)) {
      // A single * or _ must not be half of a longer run.
      final single = marker.length == 1;
      final prevSame = single && _at(s, k - 1) == marker;
      final nextSame = single && _at(s, k + 1) == marker;
      if (!prevSame && !nextSame && _canClose(s, k, marker.length) && k > from) {
        return k;
      }
    }
    k++;
  }
  return -1;
}

List<MdSpan> _merge(List<MdSpan> spans) {
  final out = <MdSpan>[];
  for (final s in spans) {
    if (s.text.isEmpty) continue;
    if (out.isNotEmpty && out.last.bold == s.bold && out.last.italic == s.italic) {
      out[out.length - 1] = MdSpan(out.last.text + s.text, bold: s.bold, italic: s.italic);
    } else {
      out.add(s);
    }
  }
  return out;
}

// Inline emphasis in [s]; [bold] / [italic] are what the surrounding span already is.
List<MdSpan> parseInline(String s, {bool bold = false, bool italic = false}) {
  final out = <MdSpan>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      out.add(MdSpan(buf.toString(), bold: bold, italic: italic));
      buf.clear();
    }
  }

  var i = 0;
  while (i < s.length) {
    final ch = s[i];

    if (ch == r'\' && i + 1 < s.length && '*_#\\-`'.contains(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }

    if (ch == '*' || ch == '_') {
      // ***both***, **bold**, *italic*  (and the underscore forms)
      var handled = false;
      for (final len in const [3, 2, 1]) {
        final marker = ch * len;
        if (!s.startsWith(marker, i)) continue;
        // a longer run than the marker we are testing: leave it to the longer test
        if (len < 3 && _at(s, i + len) == ch && len == 1) continue;
        if (!_canOpen(s, i, len)) continue;
        final close = _findClose(s, i + len, marker);
        if (close < 0) continue;
        final inner = s.substring(i + len, close);
        if (inner.trim().isEmpty) continue;
        flush();
        out.addAll(parseInline(
          inner,
          bold: bold || len >= 2,
          italic: italic || len == 1 || len == 3,
        ));
        i = close + len;
        handled = true;
        break;
      }
      if (handled) continue;
    }

    buf.write(ch);
    i++;
  }
  flush();
  return _merge(out);
}

final RegExp _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
final RegExp _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');

// The blocks of [text], in order.
List<MdBlock> parseMarkdown(String text) {
  final blocks = <MdBlock>[];
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  var gap = false;
  final para = <String>[];

  void endParagraph() {
    if (para.isEmpty) return;
    final joined = para.join('\n');
    blocks.add(MdBlock(MdKind.paragraph, parseInline(joined), spaceBefore: gap && blocks.isNotEmpty));
    para.clear();
    gap = false;
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      endParagraph();
      gap = true;
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null && h.group(2)!.isNotEmpty) {
      endParagraph();
      blocks.add(MdBlock(MdKind.heading, parseInline(h.group(2)!, bold: true),
          level: h.group(1)!.length > 3 ? 3 : h.group(1)!.length, spaceBefore: gap && blocks.isNotEmpty));
      gap = false;
      continue;
    }
    final b = _bullet.firstMatch(line);
    if (b != null && b.group(1)!.trim().isNotEmpty) {
      endParagraph();
      blocks.add(MdBlock(MdKind.bullet, parseInline(b.group(1)!), spaceBefore: gap && blocks.isNotEmpty));
      gap = false;
      continue;
    }
    final n = _numbered.firstMatch(line);
    if (n != null && n.group(2)!.trim().isNotEmpty) {
      endParagraph();
      blocks.add(MdBlock(MdKind.numbered, parseInline(n.group(2)!),
          number: int.parse(n.group(1)!), spaceBefore: gap && blocks.isNotEmpty));
      gap = false;
      continue;
    }
    para.add(line);
  }
  endParagraph();
  return blocks;
}

// The reply as plain text, without the markers (for a screen reader).
String markdownToPlain(String text) {
  final blocks = parseMarkdown(text);
  if (blocks.isEmpty) return text;
  return blocks.map((b) {
    switch (b.kind) {
      case MdKind.bullet:
        return '• ${b.plain}';
      case MdKind.numbered:
        return '${b.number}. ${b.plain}';
      case MdKind.heading:
      case MdKind.paragraph:
        return b.plain;
    }
  }).join('\n');
}
