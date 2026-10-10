import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'BookDocParser.dart';

// Opens a book fast.
//
//  1. A book opened before is read straight from its parsed copy on the device
//     (a small JSON file next to the downloaded .docx): no download, no unzip,
//     no XML parse. It opens at once.
//  2. A book opened for the first time is downloaded, then unzipped and parsed
//     on a background isolate, never on the UI thread. The first chapter is sent
//     the moment it is complete, so it can be shown while the rest is still being
//     read; the finished book follows.
//  3. The parsed copy is saved for next time. It is keyed by the downloaded
//     file's size and date, so a book the guide replaces is read afresh.

// What the loader reports. [complete] is false while only the first chapter has
// been read.
class BookLoadUpdate {
  const BookLoadUpdate(this.book, {required this.complete, this.fromCache = false});

  final ParsedBook book;
  final bool complete;
  final bool fromCache;
}

// Where the files live. The app uses the cache manager; tests use a folder.
abstract class BookFileStore {
  // The downloaded .docx if this device already has it (even a stale copy).
  Future<File?> cachedRaw(String url);

  // Downloads (or revalidates) the .docx.
  Future<File> fetchRaw(String url);

  // True when the cached .docx is old enough to be checked again.
  Future<bool> rawIsStale(String url);

  Future<File?> cachedParsed(String key);
  Future<void> saveParsed(String key, Uint8List bytes);
}

class CacheManagerBookStore implements BookFileStore {
  CacheManagerBookStore([CacheManager? manager])
      : _cm = manager ?? DefaultCacheManager();

  final CacheManager _cm;

  @override
  Future<File?> cachedRaw(String url) async =>
      (await _cm.getFileFromCache(url))?.file;

  @override
  Future<File> fetchRaw(String url) => _cm.getSingleFile(url);

  @override
  Future<bool> rawIsStale(String url) async {
    final info = await _cm.getFileFromCache(url);
    return info == null || info.validTill.isBefore(DateTime.now());
  }

  @override
  Future<File?> cachedParsed(String key) async =>
      (await _cm.getFileFromCache(key))?.file;

  @override
  Future<void> saveParsed(String key, Uint8List bytes) async {
    await _cm.putFile(key, bytes,
        key: key, maxAge: const Duration(days: 90), fileExtension: 'json');
  }
}

String _parsedKey(String url, File raw) {
  final stat = raw.statSync();
  return 'parsed$kParsedBookVersion|$url|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
}

Stream<BookLoadUpdate> loadBook({
  required String url,
  required String fallbackTitle,
  BookFileStore? store,
  // Tests: parse inline instead of on an isolate.
  bool useIsolate = true,
}) {
  final controller = StreamController<BookLoadUpdate>();
  () async {
    final files = store ?? CacheManagerBookStore();
    try {
      // 1. A copy parsed on an earlier visit.
      final cachedRaw = await files.cachedRaw(url);
      if (cachedRaw != null) {
        final key = _parsedKey(url, cachedRaw);
        final parsed = await files.cachedParsed(key);
        if (parsed != null) {
          try {
            final book = await _decodeOffThread(parsed.path, useIsolate);
            controller.add(BookLoadUpdate(book, complete: true, fromCache: true));
            // Quietly look for a newer file when the downloaded one is old.
            if (await files.rawIsStale(url)) {
              unawaited(_refreshInBackground(files, url, fallbackTitle, key, useIsolate));
            }
            return;
          } catch (_) {
            // A damaged cached copy: read the book again below.
          }
        }
      }

      // 2. Download (or reuse the downloaded file) and parse off the UI thread.
      final raw = await files.fetchRaw(url);
      final key = _parsedKey(url, raw);
      final bytes = await raw.readAsBytes();
      await for (final update in _parseOffThread(bytes, fallbackTitle, key, files, useIsolate)) {
        controller.add(update);
      }
    } catch (e, s) {
      controller.addError(e, s);
    } finally {
      await controller.close();
    }
  }();
  return controller.stream;
}

Future<void> _refreshInBackground(BookFileStore files, String url,
    String fallbackTitle, String knownKey, bool useIsolate) async {
  try {
    final raw = await files.fetchRaw(url);
    final key = _parsedKey(url, raw);
    if (key == knownKey) return; // unchanged
    final bytes = await raw.readAsBytes();
    await for (final _ in _parseOffThread(bytes, fallbackTitle, key, files, useIsolate)) {}
  } catch (_) {
    // Offline or a bad file: the copy on the device stays in use.
  }
}

// ---------------------------------------------------------------- off-thread

Future<ParsedBook> _decodeOffThread(String path, bool useIsolate) async {
  if (!useIsolate) return _decodeFile(path);
  return Isolate.run(() => _decodeFile(path));
}

ParsedBook _decodeFile(String path) =>
    ParsedBook.decode(utf8.decode(File(path).readAsBytesSync()));

class _ParseJob {
  _ParseJob(this.port, this.bytes, this.title);
  final SendPort port;
  final TransferableTypedData bytes;
  final String title;
}

void _parseEntry(_ParseJob job) {
  try {
    final data = job.bytes.materialize().asUint8List();
    final book = parseDocx(
      data,
      fallbackTitle: job.title,
      onFirstChapter: (first, media) =>
          job.port.send(['first', ParsedBook([first], media)]),
    );
    final json = TransferableTypedData.fromList(
        [Uint8List.fromList(utf8.encode(book.encode()))]);
    job.port.send(['done', book, json]);
  } catch (e) {
    job.port.send(['error', e.toString()]);
  }
}

Stream<BookLoadUpdate> _parseOffThread(Uint8List bytes, String title,
    String key, BookFileStore files, bool useIsolate) async* {
  if (!useIsolate) {
    ParsedBook? first;
    final book = parseDocx(bytes,
        fallbackTitle: title,
        onFirstChapter: (c, media) => first = ParsedBook([c], media));
    if (first != null && book.chapters.length > 1) {
      yield BookLoadUpdate(first!, complete: false);
    }
    yield BookLoadUpdate(book, complete: true);
    await files.saveParsed(key, Uint8List.fromList(utf8.encode(book.encode())));
    return;
  }

  final port = ReceivePort();
  final isolate = await Isolate.spawn(
    _parseEntry,
    _ParseJob(port.sendPort, TransferableTypedData.fromList([bytes]), title),
    errorsAreFatal: true,
  );
  try {
    await for (final message in port) {
      final m = message as List;
      switch (m[0]) {
        case 'first':
          yield BookLoadUpdate(m[1] as ParsedBook, complete: false);
        case 'done':
          final book = m[1] as ParsedBook;
          yield BookLoadUpdate(book, complete: true);
          final json = (m[2] as TransferableTypedData).materialize().asUint8List();
          await files.saveParsed(key, json);
          return;
        case 'error':
          throw FormatException(m[1] as String);
      }
    }
  } finally {
    port.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
