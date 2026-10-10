import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The data behind the Books list, loaded so it opens fast.
//
// What the list waits on is two Firestore reads: the `books` collection (the
// titles of each level, and the Dropbox links in every language) and this
// student's `booksRead` documents (their progress). They used to be read one
// after the other — the second read only started once the screen had been built
// from the first, because it lived in a StreamBuilder inside the first one's
// builder. Here both are listened to at once, as soon as the screen opens, and
// each is shown as soon as it arrives:
//
//   - the titles first (the level sections can be drawn without any progress),
//   - then the progress (the "Current books" strip and each book's status).
//
// The titles and links change rarely, so the last copy is also kept on the
// device and shown at once on the next visit, then replaced by the live read.
// The student's own progress is never cached here: it always comes from
// Firestore, so a status is never shown out of date.
typedef BookDocs = Map<String, Map<String, dynamic>>;

class BookLibrary extends ChangeNotifier {
  BookLibrary({
    required Stream<BookDocs> booksStream,
    required Stream<List<Map<String, dynamic>>> entriesStream,
    Future<SharedPreferences> Function()? loadPrefs,
  }) : _loadPrefs = loadPrefs ?? SharedPreferences.getInstance {
    _booksSub = booksStream.listen(
      (docs) {
        _books = docs;
        _booksFromCache = false;
        _booksError = null;
        notifyListeners();
        _saveCache(docs);
      },
      onError: (Object e) {
        _booksError = e;
        notifyListeners();
      },
    );
    _entriesSub = entriesStream.listen(
      (list) {
        _entries = list;
        notifyListeners();
      },
      onError: (Object e) {
        _entriesError = e;
        notifyListeners();
      },
    );
    _readCache();
  }

  static const String _kCache = 'bookLibrary.docs.v1';

  final Future<SharedPreferences> Function() _loadPrefs;
  StreamSubscription<BookDocs>? _booksSub;
  StreamSubscription<List<Map<String, dynamic>>>? _entriesSub;

  BookDocs? _books;
  bool _booksFromCache = false;
  Object? _booksError;
  List<Map<String, dynamic>>? _entries;
  Object? _entriesError;

  // The level / links documents, or null until the first copy (cached or live).
  BookDocs? get books => _books;
  bool get booksFromCache => _booksFromCache;
  Object? get booksError => _booksError;

  // This student's progress documents, or null until they have been read.
  List<Map<String, dynamic>>? get entries => _entries;
  Object? get entriesError => _entriesError;
  bool get entriesLoaded => _entries != null;

  Future<void> _readCache() async {
    try {
      final raw = (await _loadPrefs()).getString(_kCache);
      if (raw == null || _books != null) return; // a live copy already arrived
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _books = {
        for (final e in decoded.entries)
          e.key: Map<String, dynamic>.from(e.value as Map),
      };
      _booksFromCache = true;
      notifyListeners();
    } catch (_) {
      // No cached copy, or an unreadable one: wait for the live read.
    }
  }

  Future<void> _saveCache(BookDocs docs) async {
    try {
      // Titles and links are plain strings; anything else is left out.
      final plain = {
        for (final d in docs.entries)
          d.key: {
            for (final f in d.value.entries)
              if (f.value is String) f.key: f.value,
          },
      };
      await (await _loadPrefs()).setString(_kCache, jsonEncode(plain));
    } catch (_) {}
  }

  @override
  void dispose() {
    _booksSub?.cancel();
    _entriesSub?.cancel();
    super.dispose();
  }
}
