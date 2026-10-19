import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/BookDocParser.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/utils/ReaderContrast.dart';

// Book reader: the DOCX parser, the readability rule, and the loader (isolate,
// device cache, first chapter first).
const _w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

String run(String text, {bool bold = false, bool italic = false, String? color, int? size}) =>
    '<w:r><w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}${color != null ? '<w:color w:val="$color"/>' : ''}${size != null ? '<w:sz w:val="$size"/>' : ''}</w:rPr><w:t xml:space="preserve">$text</w:t></w:r>';

String para(String runs, {String? style, String? fill, String? border, bool center = false}) {
  final ppr = '<w:pPr>${style != null ? '<w:pStyle w:val="$style"/>' : ''}'
      '${fill != null ? '<w:shd w:val="clear" w:fill="$fill"/>' : ''}'
      '${border != null ? '<w:pBdr><w:top w:val="single" w:sz="24" w:color="$border"/><w:bottom w:val="single" w:sz="24" w:color="$border"/></w:pBdr>' : ''}'
      '${center ? '<w:jc w:val="center"/>' : ''}</w:pPr>';
  return '<w:p>$ppr$runs</w:p>';
}

Uint8List docx(String body) {
  final xml = '<?xml version="1.0" encoding="UTF-8"?><w:document $_w><w:body>$body</w:body></w:document>';
  final archive = Archive()..addFile(ArchiveFile('word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List bigDocx(int chapters, int paragraphsPerChapter) {
  final b = StringBuffer();
  for (var c = 0; c < chapters; c++) {
    b.write(para(run('Chapter ${c + 1}', bold: true), style: 'Heading1', fill: '008080', border: '800000'));
    for (var p = 0; p < paragraphsPerChapter; p++) {
      b.write(para(run('Paragraph $p of chapter $c, the quick brown fox ', color: '000000') + run('jumps over the lazy dog. ', italic: true) + run('Kṛṣṇa ', bold: true, color: '000080', size: 28)));
    }
  }
  return docx(b.toString());
}

// A folder-backed store, standing in for the cache manager.
class FolderStore implements BookFileStore {
  FolderStore(this.dir, this.bytes);
  final Directory dir;
  Uint8List bytes;
  int fetches = 0;
  bool stale = false;
  final Map<String, File> parsed = {};

  File get rawFile => File('${dir.path}/raw.docx');

  @override
  Future<File?> cachedRaw(String url) async => rawFile.existsSync() ? rawFile : null;

  @override
  Future<File> fetchRaw(String url) async {
    fetches++;
    if (!rawFile.existsSync()) rawFile.writeAsBytesSync(bytes);
    return rawFile;
  }

  @override
  Future<bool> rawIsStale(String url) async => stale;

  @override
  Future<File?> cachedParsed(String key) async => parsed[key];

  @override
  Future<void> saveParsed(String key, Uint8List data) async {
    final f = File('${dir.path}/p${parsed.length}.json')..writeAsBytesSync(data);
    parsed[key] = f;
  }
}

// A connection that connects and then says nothing.
class _StalledStore implements BookFileStore {
  @override
  Future<File?> cachedRaw(String url) async => null;
  @override
  Future<File> fetchRaw(String url) => Completer<File>().future;
  @override
  Future<bool> rawIsStale(String url) async => false;
  @override
  Future<File?> cachedParsed(String key) async => null;
  @override
  Future<void> saveParsed(String key, Uint8List data) async {}
}

void main() {
  group('parseDocx', () {
    test('chapters split on Heading 1; runs keep bold, italic, colour, size; blank paragraphs dropped', () {
      final book = parseDocx(
        docx(
          para(run('Preface text before any heading')) +
              para(run('One', bold: true), style: 'Heading1') +
              para(run('Alpha ') + run('beta', italic: true, color: 'FF0000') + run(' gamma', size: 28)) +
              para(run('   ')) +
              para('<w:r><w:t>x</w:t><w:br/><w:t>y</w:t><w:tab/></w:r>') +
              para(run('Two'), style: 'Heading 1') +
              para(run('Last paragraph')),
        ),
        fallbackTitle: 'My Book',
      );
      expect(book.chapters.length, 3);
      expect(book.chapters[0].title, 'My Book', reason: 'text before the first heading is its own chapter');
      expect(book.chapters[1].title, 'One');
      expect(book.chapters[2].title, 'Two');
      final p = book.chapters[1].paragraphs;
      expect(p.length, 2, reason: 'the whitespace-only paragraph is dropped');
      final r = p[0].cast<TextRun>();
      expect(r[0].text, 'Alpha ');
      expect(r[1].italic, isTrue);
      expect(r[1].color, 0xFFFF0000);
      expect(r[2].size, 14.0);
      expect(p[1].map((e) => (e as TextRun).text).join(), 'x\ny\t');
    });

    test('a heading banner keeps its shading, borders and centring', () {
      final book = parseDocx(
        docx(para(run('Banner'), style: 'Heading1', fill: '008080', border: '800000', center: true) + para(run('body'))),
        fallbackTitle: 't',
      );
      final d = book.chapters.single.titleDecoration!;
      expect(d.fill, 0xFF008080);
      expect(d.top!.color, 0xFF800000);
      expect(d.top!.width, 3.0);
      expect(d.centered, isTrue);
      expect(book.chapters.single.titleRuns.length, 1);
    });

    test('a document with no heading is one chapter; an empty one still has a chapter', () {
      expect(parseDocx(docx(para(run('only'))), fallbackTitle: 'T').chapters.length, 1);
      final empty = parseDocx(docx(''), fallbackTitle: 'T');
      expect(empty.chapters.single.paragraphs, isEmpty);
    });

    test('JSON round trip is exact', () {
      final book = parseDocx(bigDocx(3, 20), fallbackTitle: 'x');
      final back = ParsedBook.decode(book.encode());
      expect(back.encode(), book.encode());
      expect(back.chapters.length, 3);
    });

    test('the first chapter is handed over before the rest has been read', () {
      final seen = <int>[];
      final book = parseDocx(bigDocx(4, 5), fallbackTitle: 'x', onFirstChapter: (c, m) => seen.add(c.paragraphs.length));
      expect(seen, [5], reason: 'called once, with the complete first chapter');
      expect(book.chapters.length, 4);
    });

    test('a file that is not a docx fails cleanly', () {
      expect(() => parseDocx(Uint8List.fromList([1, 2, 3, 4]), fallbackTitle: 'x'), throwsA(anything));
    });
  });

  group('readability rule (WCAG 4.5:1)', () {
    test('contrast ratios are the WCAG values', () {
      expect(contrastRatio(kBlackArgb, kWhiteArgb), closeTo(21, .01));
      expect(contrastRatio(kWhiteArgb, kWhiteArgb), closeTo(1, .001));
      expect(contrastRatio(0xFF767676, kWhiteArgb), closeTo(4.54, .02));
    });

    test('black on Dark is replaced by the mode text colour; a passing colour is kept', () {
      final bg = kReaderModeColors['dark']!.background;
      expect(readableColor(0xFF000000, mode: 'dark', background: bg), kReaderModeColors['dark']!.text);
      expect(readableColor(0xFFFFCC00, mode: 'dark', background: bg), 0xFFFFCC00, reason: 'yellow reads on dark');
    });

    test('white on Light (a hidden drop-cap) and cyan on Sepia are fixed', () {
      final light = kReaderModeColors['light']!.background;
      expect(contrastRatio(readableColor(0xFFFFFFFF, mode: 'light', background: light), light), greaterThanOrEqualTo(4.5));
      final sepia = kReaderModeColors['sepia']!.background;
      expect(contrastRatio(readableColor(0xFF00FFFF, mode: 'sepia', background: sepia), sepia), greaterThanOrEqualTo(4.5));
    });

    test('an unstyled run keeps the reader default (dark grey in Light, mode text elsewhere)', () {
      expect(readableColor(null, mode: 'light', background: 0xFFFFFFFF), kReaderDefaultTextArgb);
      expect(readableColor(null, mode: 'dark', background: 0xFF121212), kReaderModeColors['dark']!.text);
      expect(readableColor(null, mode: 'sepia', background: 0xFFF4ECD8), kReaderModeColors['sepia']!.text);
    });

    test('on a mid-tone banner even the mode colours can fall short: black or white decides', () {
      const banner = 0xFF808080;
      for (final mode in ['light', 'dark', 'sepia']) {
        final c = readableColor(0xFF808080, mode: mode, background: banner, onBanner: true);
        expect(contrastRatio(c, banner), greaterThanOrEqualTo(4.5), reason: mode);
      }
    });

    test('after the rule, no colour on any background fails (20,000 random pairs, all three modes)', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 20000; i++) {
        final fg = 0xFF000000 | rnd.nextInt(0xFFFFFF);
        final bg = 0xFF000000 | rnd.nextInt(0xFFFFFF);
        for (final mode in ['light', 'dark', 'sepia']) {
          final c = readableColor(fg, mode: mode, background: bg, onBanner: i.isEven);
          expect(contrastRatio(c, bg), greaterThanOrEqualTo(4.5), reason: '$mode ${fg.toRadixString(16)} on ${bg.toRadixString(16)}');
        }
      }
    });

    test('the reader palettes match the colour source', () {
      expect(kReaderModeColors['light']!.background, 0xFFFFFFFF);
      expect(kReaderModeColors['dark']!.background, 0xFF121212);
      expect(kReaderModeColors['sepia']!.background, 0xFFF4ECD8);
      expect(kReaderModeColors['sepia']!.text, 0xFF4B3621);
    });
  });

  group('loadBook', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('book_loader'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a download that never answers ends with a TimeoutException (the reader says "taking too long") instead of waiting for ever', () async {
      final store = _StalledStore();
      final sw = Stopwatch()..start();
      await expectLater(
        loadBook(url: 'u', fallbackTitle: 'x', store: store, downloadTimeout: const Duration(milliseconds: 150)).toList(),
        throwsA(isA<TimeoutException>()),
      );
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(kBookDownloadTimeout, const Duration(seconds: 40), reason: 'the real limit');
    });

    test('first open: downloads once, parses off the UI thread, first chapter first, then saves the parsed copy', () async {
      final store = FolderStore(dir, bigDocx(5, 30));
      final updates = await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      expect(store.fetches, 1);
      expect(updates.first.complete, isFalse);
      expect(updates.first.book.chapters.length, 1, reason: 'the first chapter arrives on its own');
      expect(updates.last.complete, isTrue);
      expect(updates.last.book.chapters.length, 5);
      expect(updates.last.fromCache, isFalse);
      expect(store.parsed.length, 1, reason: 'the parsed copy is saved for next time');
    });

    test('reopened: read from the parsed copy, no download, no parse', () async {
      final store = FolderStore(dir, bigDocx(5, 30));
      await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      final fetches = store.fetches;
      final second = await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      expect(store.fetches, fetches, reason: 'nothing downloaded');
      expect(second.length, 1);
      expect(second.single.fromCache, isTrue);
      expect(second.single.complete, isTrue);
      expect(second.single.book.chapters.length, 5);
    });

    test('a book the guide replaced (different file) is read afresh', () async {
      final store = FolderStore(dir, bigDocx(2, 3));
      await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      store.rawFile.writeAsBytesSync(bigDocx(6, 3)); // new file on the device
      final again = await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      expect(again.last.fromCache, isFalse);
      expect(again.last.book.chapters.length, 6);
    });

    test('a damaged parsed copy falls back to reading the book again', () async {
      final store = FolderStore(dir, bigDocx(3, 3));
      await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      store.parsed.values.first.writeAsStringSync('{not json');
      final again = await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      expect(again.last.book.chapters.length, 3);
      expect(again.last.fromCache, isFalse);
    });

    test('a file that is not a docx is reported as an error, not swallowed', () async {
      final store = FolderStore(dir, Uint8List.fromList(List.filled(50, 7)));
      expect(loadBook(url: 'u', fallbackTitle: 'x', store: store).toList(), throwsA(anything));
    });

    test('the isolate result equals the inline result', () async {
      final bytes = bigDocx(4, 12);
      final a = await loadBook(url: 'u', fallbackTitle: 'x', store: FolderStore(Directory.systemTemp.createTempSync('a'), bytes)).toList();
      final b = await loadBook(url: 'u', fallbackTitle: 'x', store: FolderStore(Directory.systemTemp.createTempSync('b'), bytes), useIsolate: false).toList();
      expect(a.last.book.encode(), b.last.book.encode());
    });

    test('TIMING: parsing on the UI thread blocks it for the whole parse; on an isolate it does not; reopening is near instant', () async {
      final bytes = bigDocx(40, 120); // about 4,800 paragraphs
      final sw = Stopwatch()..start();
      final inline = parseDocx(bytes, fallbackTitle: 'x');
      final syncMs = sw.elapsedMilliseconds;
      expect(inline.chapters.length, 40);

      // Longest gap a main-isolate timer sees while each path runs.
      Future<int> longestGap(Future<void> Function() work) async {
        var last = Stopwatch()..start();
        var worst = 0;
        final t = Timer.periodic(const Duration(milliseconds: 2), (_) {
          worst = math.max(worst, last.elapsedMilliseconds);
          last = Stopwatch()..start();
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        worst = 0;
        await work();
        await Future<void>.delayed(const Duration(milliseconds: 15)); // let the timer report the gap
        t.cancel();
        return worst;
      }

      final blockedSync = await longestGap(() async => parseDocx(bytes, fallbackTitle: 'x'));
      final dir2 = Directory.systemTemp.createTempSync('t');
      addTearDown(() => dir2.deleteSync(recursive: true));
      final store = FolderStore(dir2, bytes);
      var isolateMs = 0;
      final blockedIsolate = await longestGap(() async {
        final s = Stopwatch()..start();
        await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
        isolateMs = s.elapsedMilliseconds;
      });
      final reopen = Stopwatch()..start();
      await loadBook(url: 'u', fallbackTitle: 'x', store: store).toList();
      final reopenMs = reopen.elapsedMilliseconds;

      // ignore: avoid_print
      print('TIMING (4,800-paragraph book, test VM, debug): parse inline ${syncMs} ms; '
          'longest UI-thread stall inline ${blockedSync} ms vs on isolate ${blockedIsolate} ms; '
          'first open via isolate ${isolateMs} ms; reopen from the parsed copy ${reopenMs} ms');
      expect(blockedSync, greaterThan(syncMs ~/ 2), reason: 'inline parsing stalls the thread for about the whole parse');
      expect(blockedIsolate, lessThan(blockedSync ~/ 2), reason: 'the isolate leaves the UI thread free');
      expect(reopenMs, lessThan(syncMs), reason: 'the parsed copy opens faster than parsing');
    });
  });
}
