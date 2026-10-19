import 'package:cloud_firestore/cloud_firestore.dart';

// The reading history (Books -> History): one row per DAY the student read, with the total minutes and each book's minutes.
//
// ---------------------------------------------------------------------------------------------------------
// Why a NEW collection (Rule 12)
// ---------------------------------------------------------------------------------------------------------
// `readingDays/{uid}_{yyyyMMdd}`. The existing `users/{uid}/dailyReading/{date}` holds ONE number per day (`secondsToday`,
// the whole day's total, which feeds the sadhana report's reading minutes) and is readable by the student's guide through
// the `users` sub-collection rule; the history needs the day split BY BOOK, and must be private to the student (owner-only
// rules, no admin branch). So it is its own small collection and the existing totals are not touched: how reports and
// scores use reading minutes is unchanged (`BookPageList._recordReadingSession` still writes exactly what it wrote).
//
// A document: uid, dayKey ('dd-MM-yyyy'), dayStamp (yyyyMMdd, for ordering), totalSeconds, books
// { '<level>__<bookKey>': {title, level, bookKey, seconds} }, updatedAt. Written by the reader's own timer: when the reader
// closes with N seconds read, those seconds are added to that day and that book. A day on which nothing was read creates no
// document. The server keeps the newest 30 days: when a 31st day is created, the oldest is deleted (`functions/readingLog.js`).

/// A session shorter than this is not a reading day (opening a book by accident must not create a history row, or push
/// the oldest real day out).
const int kReadingLogMinSeconds = 30;

/// The most days kept (the server enforces it; the screen shows no more than this either).
const int kReadingLogDays = 30;

/// 20261019
int dayStampOf(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

String dayKeyOf(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

String bookIdOf(String level, String bookKey) => '${level}__$bookKey';

/// Adds a finished reading session to today's reading day. Returns false (and writes nothing) for a session too short
/// to count. Never throws: a history that cannot be written must not get in the way of reading.
Future<bool> recordReadingDay({
  required FirebaseFirestore db,
  required String uid,
  required String level,
  required String bookKey,
  required String title,
  required int seconds,
  DateTime? now,
}) async {
  if (uid.isEmpty || seconds < kReadingLogMinSeconds) return false;
  final today = now ?? DateTime.now();
  try {
    await db.collection('readingDays').doc('${uid}_${dayStampOf(today)}').set({
      'uid': uid,
      'dayKey': dayKeyOf(today),
      'dayStamp': dayStampOf(today),
      'totalSeconds': FieldValue.increment(seconds),
      'books': {
        bookIdOf(level, bookKey): {
          'title': title,
          'level': level,
          'bookKey': bookKey,
          'seconds': FieldValue.increment(seconds),
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  } catch (_) {
    return false;
  }
}

class ReadingBookTime {
  const ReadingBookTime({required this.title, required this.seconds});

  final String title;
  final int seconds;
}

class ReadingDay {
  const ReadingDay({required this.stamp, required this.dayKey, required this.totalSeconds, required this.books});

  final int stamp;
  final String dayKey;
  final int totalSeconds;

  /// Most-read first.
  final List<ReadingBookTime> books;

  DateTime get date => DateTime(stamp ~/ 10000, (stamp ~/ 100) % 100, stamp % 100);
}

/// Whole minutes, at least 1 for any reading at all ("0 min" would be wrong for 40 seconds).
int minutesOf(int seconds) => seconds <= 0 ? 0 : ((seconds + 30) ~/ 60).clamp(1, 1 << 30);

String minutesText(int seconds) => '${minutesOf(seconds)} min';

/// The student's reading days, newest first, never more than [kReadingLogDays]. A damaged document is skipped.
List<ReadingDay> parseReadingDays(Iterable<Map<String, dynamic>> docs) {
  final out = <ReadingDay>[];
  for (final d in docs) {
    final stamp = d['dayStamp'];
    final total = d['totalSeconds'];
    if (stamp is! num || total is! num || total <= 0) continue;
    final books = <ReadingBookTime>[];
    final raw = d['books'];
    if (raw is Map) {
      for (final b in raw.values) {
        if (b is! Map) continue;
        final s = b['seconds'];
        if (s is! num || s <= 0) continue;
        books.add(ReadingBookTime(title: (b['title'] ?? 'Book').toString(), seconds: s.toInt()));
      }
    }
    books.sort((a, b) => b.seconds.compareTo(a.seconds));
    out.add(ReadingDay(
      stamp: stamp.toInt(),
      dayKey: (d['dayKey'] ?? '').toString(),
      totalSeconds: total.toInt(),
      books: books,
    ));
  }
  out.sort((a, b) => b.stamp.compareTo(a.stamp));
  return out.length > kReadingLogDays ? out.sublist(0, kReadingLogDays) : out;
}
