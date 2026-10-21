import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'BookReadingLog.dart';

// Reading time that is never lost (Books reader).
//
// ---------------------------------------------------------------------------------------------------------
// The problem
// ---------------------------------------------------------------------------------------------------------
// The reader counts seconds in memory and hands them over when it closes (`Navigator.pop(seconds)`); the book list then
// writes them (`issueReadingWrites`). If the app is killed while a book is open (swiped away, the phone ran out of memory or
// battery) those seconds were lost, and a reader left in the background kept counting.
//
// ---------------------------------------------------------------------------------------------------------
// How it works
// ---------------------------------------------------------------------------------------------------------
// 1. [ReadingTimer] only counts while the student is really reading (it is paused in the background and under another page;
//    see `BookReaderPage`). It adds up what a monotonic clock says, never a wall-clock difference across a pause.
// 2. While the timer runs, the reader keeps ONE [ReadingSession] on the phone (SharedPreferences) and refreshes it about every
//    12 s and on every pause. A session has a deterministic id (`uid_level_book_startMicros`).
// 3. A normal close marks the session `closing` and the book list writes the seconds as it always did; once those writes are
//    ISSUED it settles the session: the stored copy is removed and its id goes into a short list of "already saved" ids.
// 4. At the next app start [recoverLeftoverReading] finds any session of an EARLIER run that was never settled (the app was
//    killed), writes its seconds through the same path (`issueReadingWrites`) and settles it. A session whose id is in the
//    saved list is never written again, and [ReadingSessionStore.save] refuses to store a saved id, so a retry, a second
//    start, or a reader that flushes after the book list took over can never count a session twice.
// Offline: Firestore keeps writes made without a connection and sends them later. "Issued" therefore means "the write call
// was made" (we do not wait for the server), and only then is the session marked saved. If the calls could not even be made,
// the session stays and the next start tries again.

/// How often a running session is refreshed on the phone.
const Duration kReadingSaveEvery = Duration(seconds: 12);

/// How many "already saved" ids are remembered.
const int kReadingSavedIdsKept = 40;

/// Adds up reading time from a monotonic source (a `Stopwatch`'s elapsed time in the app; a hand-moved clock in tests): the
/// time between [start] and [pause] counts, the time between [pause] and the next [start] does not.
class ReadingTimer {
  ReadingTimer(this._elapsed);

  final Duration Function() _elapsed;
  Duration _banked = Duration.zero;
  Duration? _since;

  bool get running => _since != null;

  /// Whole seconds counted so far (including the stretch that is running now).
  int get seconds {
    final since = _since;
    final live = since == null ? Duration.zero : _elapsed() - since;
    final total = _banked + (live.isNegative ? Duration.zero : live);
    return total.inSeconds;
  }

  void start() => _since ??= _elapsed();

  void pause() {
    final since = _since;
    if (since == null) return;
    final live = _elapsed() - since;
    if (!live.isNegative) _banked += live;
    _since = null;
  }
}

/// One reading session as kept on the phone.
class ReadingSession {
  const ReadingSession({
    required this.id,
    required this.uid,
    required this.level,
    required this.bookKey,
    required this.title,
    required this.seconds,
    required this.when,
    required this.run,
    this.closing = false,
  });

  /// `uid_level_book_startMicros`: the same session always has the same id.
  final String id;
  final String uid;
  final String level;
  final String bookKey;
  final String title;
  final int seconds;

  /// When it was last refreshed: the day those seconds are written to.
  final DateTime when;

  /// The app run that owns the session (an earlier run's session is a leftover).
  final String run;

  /// True once the reader has handed the seconds to the book list.
  final bool closing;

  ReadingSession copyWith({int? seconds, DateTime? when, bool? closing}) => ReadingSession(
        id: id,
        uid: uid,
        level: level,
        bookKey: bookKey,
        title: title,
        seconds: seconds ?? this.seconds,
        when: when ?? this.when,
        run: run,
        closing: closing ?? this.closing,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'uid': uid,
        'level': level,
        'bookKey': bookKey,
        'title': title,
        'seconds': seconds,
        'when': when.millisecondsSinceEpoch,
        'run': run,
        'closing': closing,
      };

  /// Null for anything damaged (it is then simply dropped).
  static ReadingSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final uid = raw['uid'];
    final level = raw['level'];
    final bookKey = raw['bookKey'];
    final seconds = raw['seconds'];
    final when = raw['when'];
    if (id is! String || uid is! String || level is! String || bookKey is! String) return null;
    if (seconds is! num || when is! num) return null;
    return ReadingSession(
      id: id,
      uid: uid,
      level: level,
      bookKey: bookKey,
      title: (raw['title'] ?? '').toString(),
      seconds: seconds.toInt(),
      when: DateTime.fromMillisecondsSinceEpoch(when.toInt()),
      run: (raw['run'] ?? '').toString(),
      closing: raw['closing'] == true,
    );
  }
}

/// The phone's copy of the running (and not yet written) reading sessions. Every method is serialised and never throws.
class ReadingSessionStore {
  ReadingSessionStore({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  static const _sessionsKey = 'readingSessions';
  static const _savedKey = 'readingSavedIds';

  /// Names this run of the app (a session of another run is a leftover). Tests may set their own.
  static String currentRun = DateTime.now().microsecondsSinceEpoch.toString();

  // One queue for the whole process: a read-change-write never interleaves with another one, and the reader's last refresh
  // is always applied before the book list settles the session.
  static Future<void>? _queue;

  /// Tests run each case on its own clock: a queue left over from another case must not hold this one up.
  @visibleForTesting
  static void debugResetQueue() => _queue = null;

  Future<T?> _run<T>(Future<T?> Function(SharedPreferences prefs) body) {
    final done = Completer<T?>();
    _queue = (_queue ?? Future<void>.sync(() {})).then((_) async {
      try {
        done.complete(await body(await _prefs()));
      } catch (_) {
        done.complete(null);
      }
    });
    return done.future;
  }

  List<ReadingSession> _read(SharedPreferences p) {
    final raw = p.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final item in list)
          if (ReadingSession.fromJson(item) case final s?) s,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(SharedPreferences p, List<ReadingSession> sessions) async {
    if (sessions.isEmpty) {
      await p.remove(_sessionsKey);
    } else {
      await p.setString(_sessionsKey, jsonEncode([for (final s in sessions) s.toJson()]));
    }
  }

  List<String> _saved(SharedPreferences p) => p.getStringList(_savedKey) ?? <String>[];

  /// Every stored session, oldest first.
  Future<List<ReadingSession>> pending() async => await _run((p) async => _read(p)) ?? [];

  /// Has this session already been written?
  Future<bool> isSaved(String id) async => await _run((p) async => _saved(p).contains(id)) ?? false;

  /// Adds or refreshes a session. A session that has already been written is refused (returns false).
  Future<bool> save(ReadingSession session) async =>
      await _run<bool>((p) async {
        if (_saved(p).contains(session.id)) return false;
        final all = _read(p);
        final i = all.indexWhere((s) => s.id == session.id);
        if (i < 0) {
          all.add(session);
        } else {
          all[i] = session;
        }
        await _write(p, all);
        return true;
      }) ??
      false;

  /// The reader is handing [session]'s seconds to the book list: kept (and marked) until the book list has issued the writes.
  Future<bool> markClosing(ReadingSession session) => save(session.copyWith(closing: true));

  /// The book list has issued the writes of the session just closed: it is taken off the phone and remembered as saved.
  Future<void> settleClosing({required String uid, required String level, required String bookKey}) async {
    await _run<bool>((p) async {
      final all = _read(p);
      final done = [
        for (final s in all)
          if (s.closing && s.uid == uid && s.level == level && s.bookKey == bookKey) s.id,
      ];
      if (done.isEmpty) return false;
      await _write(p, [
        for (final s in all)
          if (!done.contains(s.id)) s,
      ]);
      await p.setStringList(_savedKey, _withIds(_saved(p), done));
      return true;
    });
  }

  /// The writes of [id] have been issued: it leaves the phone's list and its id is remembered.
  Future<void> markSaved(String id) async {
    await _run<bool>((p) async {
      await _write(p, [
        for (final s in _read(p))
          if (s.id != id) s,
      ]);
      await p.setStringList(_savedKey, _withIds(_saved(p), [id]));
      return true;
    });
  }

  /// Takes a session off the phone WITHOUT writing it (too short to count): its id is remembered too.
  Future<void> discard(String id) => markSaved(id);

  List<String> _withIds(List<String> saved, List<String> ids) {
    final next = [...saved.where((s) => !ids.contains(s)), ...ids];
    return next.length > kReadingSavedIdsKept ? next.sublist(next.length - kReadingSavedIdsKept) : next;
  }
}

/// The id of a session that starts now.
String readingSessionId({required String uid, required String level, required String bookKey, required DateTime start}) =>
    '${uid}_${level}_${bookKey}_${start.microsecondsSinceEpoch}';

// ------------------------------------------------------------------------------------------------ the writes

/// Waits for a write only as long as the connection lets it: a write made without a connection is kept by Firestore and sent
/// later, so a timeout means "queued" (true), an error means "refused" (false).
Future<bool> _issued(Future<Object?> write, Duration wait) async {
  try {
    await write.timeout(wait);
    return true;
  } on TimeoutException {
    return true;
  } catch (_) {
    return false;
  }
}

/// Issues every write one reading session makes, in one place for both paths (a normal close and a recovered session):
///   users/{uid}.totalReadingSeconds            += seconds   (lifetime total)
///   users/{uid}/dailyReading/{dd-MM-yyyy}      += seconds   (that day's bucket)
///   readingDays/{uid}_{yyyyMMdd}               += seconds   (the Books -> History row; sessions under 30 s are not a day)
///
/// THE TIMER NEVER TOUCHES A SADHANA REPORT (or anything the points, leaderboards, best stats or the AI insights read):
/// those use only what the student types in the form. It used to add its minutes to the day's report `bookReading` on top of
/// the typed value (a typed 65 became 88); that write is gone for good, and a test keeps it gone. The reading log above is
/// only the student's Books -> History.
///
/// The writes are all issued before any is waited for, and none is waited for longer than [wait], so a missing connection can
/// never hold the rest back. Returns false when any write was refused (not merely slow); never throws.
Future<bool> issueReadingWrites({
  required FirebaseFirestore db,
  required String uid,
  required String level,
  required String bookKey,
  required String title,
  required int seconds,
  required DateTime when,
  Duration wait = const Duration(seconds: 6),
}) async {
  if (uid.isEmpty || seconds <= 0) return true;
  var ok = true;
  try {
    final dayKey = dayKeyOf(when);
    final userRef = db.collection('users').doc(uid);
    final dailyRef = userRef.collection('dailyReading').doc(dayKey);

    final writes = <Future<bool>>[
      _issued(userRef.set({'totalReadingSeconds': FieldValue.increment(seconds)}, SetOptions(merge: true)), wait),
      _issued(dailyRef.set({'secondsToday': FieldValue.increment(seconds)}, SetOptions(merge: true)), wait),
      // recordReadingDay never throws, and answers false for a session under 30 s (not a failure).
      recordReadingDay(db: db, uid: uid, level: level, bookKey: bookKey, title: title, seconds: seconds, now: when).then((_) => true),
    ];

    for (final r in await Future.wait(writes)) {
      if (!r) ok = false;
    }
  } catch (_) {
    ok = false;
  }
  return ok;
}

// ------------------------------------------------------------------------------------------------ the recovery

/// Writes the seconds of every session left behind by an EARLIER run of the app (killed while a book was open) of [uid], then
/// settles it. Returns how many sessions were written. Never throws.
///
/// * a session of this very run is skipped (its reader is alive and will hand it over);
/// * a session already in the saved list is only cleaned up, never written;
/// * a session under 30 s is dropped without writing (the same threshold as a normal close);
/// * [write] is called BEFORE the session is marked saved; if it throws, the session stays for the next start. [write] is
///   given [writeWait] to return; a write that has not answered by then is queued by Firestore (offline) and counts as issued.
Future<int> recoverReadingSessions({
  required String uid,
  required ReadingSessionStore store,
  required Future<void> Function(ReadingSession session) write,
  String? run,
  int minSeconds = kReadingLogMinSeconds,
  Duration writeWait = const Duration(seconds: 20),
}) {
  // One recovery at a time: a second call waits for the first and then finds nothing left to write.
  final done = (_recoveryTail ?? Future<void>.sync(() {})).then((_) => _recover(uid, store, write, run, minSeconds, writeWait));
  _recoveryTail = done.then((_) {}, onError: (Object _) {});
  return done;
}

Future<void>? _recoveryTail;

Future<int> _recover(
  String uid,
  ReadingSessionStore store,
  Future<void> Function(ReadingSession session) write,
  String? run,
  int minSeconds,
  Duration writeWait,
) async {
  var written = 0;
  try {
    final thisRun = run ?? ReadingSessionStore.currentRun;
    for (final s in await store.pending()) {
      if (s.uid != uid || s.run == thisRun) continue;
      if (await store.isSaved(s.id)) {
        await store.markSaved(s.id);
        continue;
      }
      if (s.seconds < minSeconds) {
        await store.discard(s.id);
        continue;
      }
      try {
        await write(s).timeout(writeWait, onTimeout: () {});
      } catch (_) {
        continue; // could not even be issued: stays on the phone for the next start
      }
      await store.markSaved(s.id);
      written++;
    }
  } catch (_) {}
  return written;
}

bool _recoveryStarted = false;

@visibleForTesting
void debugResetRecoveryStarted() {
  _recoveryStarted = false;
  _recoveryTail = null;
}

/// App start-up hook: once per run, as soon as a student is signed in, writes what a killed run left behind. Never blocks
/// start-up (call it without awaiting) and never throws.
Future<void> recoverLeftoverReading() async {
  if (_recoveryStarted) return;
  _recoveryStarted = true;
  try {
    final user = await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);
    final uid = user!.uid;
    final db = FirebaseFirestore.instance;
    final store = ReadingSessionStore();
    await recoverReadingSessions(
      uid: uid,
      store: store,
      // the reading log only (never a sadhana report: see `issueReadingWrites`)
      // (an `async` body, so the future the recovery waits on is a Future<void>, not the Future<bool> the writes answer with)
      write: (s) async {
        await issueReadingWrites(db: db, uid: uid, level: s.level, bookKey: s.bookKey, title: s.title, seconds: s.seconds, when: s.when);
      },
    );
  } catch (_) {}
}
