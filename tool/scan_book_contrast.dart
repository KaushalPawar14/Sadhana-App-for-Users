// Scans every book the app can open and counts, per reader mode (Light, Dark,
// Sepia), the text runs whose colour does not reach WCAG 4.5:1 against the
// background they sit on, BEFORE and AFTER the reader's readability rule.
//
// Read-only: it only reads the downloaded .docx files (D:\tmp-fl\books, listed in
// D:\tmp-fl\book_manifest.json) and never writes to a book or to Firestore.
//
//   dart run tool/scan_book_contrast.dart [manifest.json]
//
// It runs the very same parser and colour rules as the app
// (lib/utils/BookDocParser.dart, lib/utils/ReaderContrast.dart).
import 'dart:convert';
import 'dart:io';

import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/ReaderContrast.dart';

String hex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'
    '${((c >> 24) & 0xFF) == 0xFF ? '' : '@${(((c >> 24) & 0xFF) / 255).toStringAsFixed(2)}'}';

class Example {
  Example(this.book, this.chapter, this.mode, this.where, this.text, this.fg, this.bg, this.ratio);
  final String book;
  final String chapter;
  final String mode;
  final String where;
  final String text;
  final int fg;
  final int bg;
  final double ratio;
  Map<String, Object?> toJson() => {
        'book': book,
        'chapter': chapter,
        'mode': mode,
        'where': where,
        'text': text,
        'text_colour': hex(fg),
        'background': hex(bg),
        'contrast': double.parse(ratio.toStringAsFixed(2)),
      };
}

void main(List<String> args) {
  final manifestPath = args.isNotEmpty ? args.first : 'D:/tmp-fl/book_manifest.json';
  final manifest = (jsonDecode(File(manifestPath).readAsStringSync()) as List).cast<Map<String, dynamic>>();

  const modes = ['light', 'dark', 'sepia'];
  var books = 0, chapters = 0, runs = 0, bannerRuns = 0;
  final before = {for (final m in modes) m: 0};
  final after = {for (final m in modes) m: 0};
  final beforeBookmarked = {for (final m in modes) m: 0};
  final afterBookmarked = {for (final m in modes) m: 0};
  final changed = {for (final m in modes) m: 0}; // runs whose colour the rule replaced
  final examples = <Example>[];
  final colourHistogram = {for (final m in modes) m: <String, int>{}};
  final perBook = <String, Map<String, int>>{};
  final failedFiles = <String>[];

  for (final m in manifest) {
    final file = File(m['file'] as String? ?? '');
    if (!file.existsSync()) {
      failedFiles.add('${m['kind']}/${m['level']}/${m['lang']}/${m['key']}: file missing');
      continue;
    }
    ParsedBook book;
    try {
      book = parseDocx(file.readAsBytesSync(), fallbackTitle: (m['title'] ?? '').toString());
    } catch (e) {
      failedFiles.add('${m['kind']}/${m['level']}/${m['lang']}/${m['key']}: $e');
      continue;
    }
    books++;
    final bookLabel = '${m['level']}/${m['lang']}/${m['key']} ${m['title']}';
    final counts = perBook.putIfAbsent(bookLabel, () => {'runs': 0, 'before': 0});

    void check(TextRun run, String chapterTitle, String where, {int? bannerFill, bool bannerHeading = false}) {
      if (run.text.trim().isEmpty) return; // whitespace is not drawn
      runs++;
      counts['runs'] = counts['runs']! + 1;
      if (bannerHeading) bannerRuns++;
      for (final mode in modes) {
        final bg = backgroundFor(mode, bannerFill: bannerFill);
        final fgBefore = effectiveColorBefore(run.color, mode: mode, onBanner: bannerHeading);
        final ratioBefore = contrastRatio(fgBefore, bg);
        if (ratioBefore < kReaderMinContrast) {
          before[mode] = before[mode]! + 1;
          colourHistogram[mode]!.update(hex(fgBefore), (v) => v + 1, ifAbsent: () => 1);
          counts['before'] = counts['before']! + 1;
          examples.add(Example(bookLabel, chapterTitle, mode, where, run.text.trim().length > 30 ? run.text.trim().substring(0, 30) : run.text.trim(), fgBefore, bg, ratioBefore));
        }
        final fgAfter = readableColor(run.color, mode: mode, background: bg, onBanner: bannerHeading);
        if (fgAfter != fgBefore) changed[mode] = changed[mode]! + 1;
        if (contrastRatio(fgAfter, bg) < kReaderMinContrast) after[mode] = after[mode]! + 1;

        if (bannerFill == null && !bannerHeading) {
          // the same run inside a bookmarked paragraph (page + 7 % purple tint)
          final tinted = backgroundFor(mode, bookmarked: true);
          if (contrastRatio(fgBefore, tinted) < kReaderMinContrast) beforeBookmarked[mode] = beforeBookmarked[mode]! + 1;
          final fgT = readableColor(run.color, mode: mode, background: tinted);
          if (contrastRatio(fgT, tinted) < kReaderMinContrast) afterBookmarked[mode] = afterBookmarked[mode]! + 1;
        }
      }
    }

    for (final ch in book.chapters) {
      chapters++;
      final fill = ch.titleDecoration?.fill;
      for (final r in ch.titleRuns) {
        if (r is TextRun) check(r, ch.title, 'heading', bannerFill: fill, bannerHeading: fill != null);
      }
      for (final p in ch.paragraphs) {
        for (final r in p) {
          if (r is TextRun) check(r, ch.title, 'paragraph');
        }
      }
    }
  }

  examples.sort((a, b) => a.ratio.compareTo(b.ratio));
  final worst = <Example>[];
  final seen = <String>{};
  for (final e in examples) {
    final key = '${e.book}|${e.mode}|${hex(e.fg)}|${hex(e.bg)}';
    if (seen.add(key)) worst.add(e);
    if (worst.length == 10) break;
  }

  final out = {
    'scanned_files': manifest.length,
    'books_parsed': books,
    'unreadable_or_missing': failedFiles,
    'chapters': chapters,
    'text_runs_checked': runs,
    'heading_runs_on_banner': bannerRuns,
    'failing_runs_before': before,
    'failing_runs_after': after,
    'runs_recoloured_by_the_rule': changed,
    'bookmarked_paragraph_failing_before': beforeBookmarked,
    'bookmarked_paragraph_failing_after': afterBookmarked,
    'failing_text_colours_before': {
      for (final m in modes)
        m: Map.fromEntries((colourHistogram[m]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(8)),
    },
    'worst_10_before': [for (final e in worst) e.toJson()],
    'books_with_failing_runs_before_count': perBook.values.where((v) => v['before']! > 0).length,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
