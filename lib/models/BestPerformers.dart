import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/SameGender.dart';

// The weekly "Best performer" winners, decided on the server when the week is
// finalised (functions/bestPerformers.js), separately for each of the four
// rankings (FOLK / Hostel & Localite x boys / girls). They live on the ranking's
// own results document, `competition-results/weekly/weeks/{weekId}/byCategory/
// {category}_{gender}`, as `mostImproved` and `commitmentKeeper` (null when nobody
// qualified). A student reads ONLY their own category's and gender's document.

class BestWinner {
  const BestWinner({required this.name, required this.reason});

  final String name;

  // The short reason, written by the server: "+24 points vs last week" or
  // "kept 16 rounds on 6 of 7 days".
  final String reason;

  // Null when the stored value is not a winner (no winner that week).
  static BestWinner? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    var reason = (raw['reason'] ?? '').toString().trim();
    if (reason.isEmpty) {
      // A document without a ready-made reason: say it from the numbers.
      final inc = raw['increase'];
      final commitment = raw['commitment'];
      final met = raw['daysMet'];
      if (inc is num) {
        reason = '+${_plain(inc)} points vs last week';
      } else if (commitment is num && met is num) {
        reason = 'kept ${_plain(commitment)} rounds on ${_plain(met)} of ${raw['weekDays'] ?? 7} days';
      }
    }
    return BestWinner(name: name, reason: reason);
  }

  static String _plain(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

class BestWeek {
  const BestWeek({required this.weekId, this.mostImproved, this.commitmentKeeper});

  final String weekId;
  final BestWinner? mostImproved;
  final BestWinner? commitmentKeeper;

  bool get hasWinner => mostImproved != null || commitmentKeeper != null;

  static BestWeek fromDoc(String weekId, Map<String, dynamic>? data) => BestWeek(
        weekId: weekId,
        mostImproved: BestWinner.fromMap(data?['mostImproved']),
        commitmentKeeper: BestWinner.fromMap(data?['commitmentKeeper']),
      );
}

class BestPerformers {
  const BestPerformers({this.thisWeek, this.lastWeek});

  // The week finalised most recently ("this week's winners": announced on Sunday for
  // the week that just ended) and the one before it.
  final BestWeek? thisWeek;
  final BestWeek? lastWeek;

  bool get isEmpty => thisWeek == null && lastWeek == null;
}

// Reads the two most recent finalised weeks, from the student's OWN ranking
// document only. [firestore] is only for tests.
Future<BestPerformers> loadBestPerformers({FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final directory = await GenderDirectory.forCurrentUser();
  final weeks = await db
      .collection('competition-results')
      .doc('weekly')
      .collection('weeks')
      .orderBy('generatedAt', descending: true)
      .limit(2)
      .get();
  final out = <BestWeek>[];
  for (final week in weeks.docs) {
    final snap = await week.reference.collection('byCategory').doc(directory.rankingId).get();
    out.add(BestWeek.fromDoc(week.id, snap.data()));
  }
  return BestPerformers(
    thisWeek: out.isNotEmpty ? out[0] : null,
    lastWeek: out.length > 1 ? out[1] : null,
  );
}
