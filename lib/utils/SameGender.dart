import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

// A student sees ONLY students of their own gender, everywhere in the app
// (hostel, localite and FOLK alike).
//
// A user with no `gender` counts as male (every existing user was backfilled
// male), so "female" is the only value that is ever looked for: a student is
// female when `gender == 'female'`, and male otherwise.
//
// Some data is keyed by a student's NAME (the leaderboards, the competition
// scores, contributions), some by uid (friends, voice rooms). [GenderDirectory]
// answers "is this person the same gender as me?" for both, from the least that
// is needed: my own user document and ONE query for the female users. It is read
// once per signed-in student and kept for the session.

const String kFemale = 'female';
const String kMale = 'male';

// The gender of a users document's data: 'female' only when it says so.
String genderOfData(Map<String, dynamic>? data) =>
    data != null && data['gender'] == kFemale ? kFemale : kMale;

class GenderDirectory {
  const GenderDirectory({
    required this.mine,
    required this.femaleNames,
    required this.femaleUids,
  });

  // The signed-in student's gender: 'male' or 'female'.
  final String mine;
  final Set<String> femaleNames;
  final Set<String> femaleUids;

  bool get iAmFemale => mine == kFemale;

  // True for a student of my gender. A name or uid nobody knows is treated as male
  // (it is not a known female), so a female student never sees it.
  bool sameByName(String? name) {
    final isFemale = name != null && femaleNames.contains(name);
    return iAmFemale ? isFemale : !isFemale;
  }

  bool sameByUid(String? uid) {
    final isFemale = uid != null && femaleUids.contains(uid);
    return iAmFemale ? isFemale : !isFemale;
  }

  // The gender of a users document's data, compared with mine.
  bool sameByData(Map<String, dynamic>? data) => genderOfData(data) == mine;

  // [entries] kept only where [nameOf] is a student of my gender.
  List<T> sameGenderByName<T>(Iterable<T> entries, String? Function(T) nameOf) =>
      [for (final e in entries) if (sameByName(nameOf(e))) e];

  List<T> sameGenderByUid<T>(Iterable<T> entries, String? Function(T) uidOf) =>
      [for (final e in entries) if (sameByUid(uidOf(e))) e];

  // Reads the signed-in student's directory (once per student, then cached).
  static Future<GenderDirectory> forCurrentUser() {
    final override = _loaderForTests;
    if (override != null) return override();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future.error(StateError('No signed-in student'));
    }
    return _cache.putIfAbsent(uid, () => _load(uid)).catchError((Object e) {
      // A failed read is not kept: the next call tries again.
      _cache.remove(uid);
      throw e;
    });
  }

  static final Map<String, Future<GenderDirectory>> _cache = {};

  @visibleForTesting
  static Future<GenderDirectory> Function()? _loaderForTests;

  @visibleForTesting
  static void useForTests(Future<GenderDirectory> Function()? loader) {
    _loaderForTests = loader;
    _cache.clear();
  }

  // Forget everything (on sign-out).
  static void reset() => _cache.clear();

  static Future<GenderDirectory> _load(String uid) async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('users').doc(uid).get(),
      db.collection('users').where('gender', isEqualTo: kFemale).get(),
    ]);
    final me = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final females = results[1] as QuerySnapshot<Map<String, dynamic>>;
    return GenderDirectory(
      mine: genderOfData(me.data()),
      femaleNames: {
        for (final d in females.docs)
          if ((d.data()['name'] ?? '').toString().isNotEmpty)
            d.data()['name'].toString(),
      },
      femaleUids: {for (final d in females.docs) d.id},
    );
  }
}

// Every scorecard document (the leaderboards' data), keyed by the student's NAME.
// Tests hand in their own reader.
typedef ScorecardReader = Future<Map<String, Map<String, dynamic>>> Function();

Future<Map<String, Map<String, dynamic>>> readScorecardDocs() async {
  final snap = await FirebaseFirestore.instance.collection('scorecard').get();
  return {for (final d in snap.docs) d.id: d.data()};
}

// A student's place among students of their own gender only.
//
// [entries] are every competitor (name + score); only those of my gender are
// counted. Returns (rank, outOf): rank is 1-based and 0 when [myName] is not among
// them; outOf is how many students of my gender there are.
({int rank, int outOf}) positionAmongSameGender(
  GenderDirectory directory,
  Iterable<({String name, double score})> entries,
  String myName,
) {
  final mine = directory.sameGenderByName(entries, (e) => e.name).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return (rank: mine.indexWhere((e) => e.name == myName) + 1, outOf: mine.length);
}

// The top [count] of each gender from every competitor (for the weekly and
// monthly winners): a map with 'male' and 'female' lists, best first.
Map<String, List<T>> topByGender<T>(
  Iterable<T> all, {
  required String Function(T) nameOf,
  required double Function(T) scoreOf,
  required Set<String> femaleNames,
  int count = 3,
}) {
  final out = <String, List<T>>{kMale: [], kFemale: []};
  final sorted = all.toList()..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
  for (final e in sorted) {
    final g = femaleNames.contains(nameOf(e)) ? kFemale : kMale;
    if (out[g]!.length < count) out[g]!.add(e);
  }
  return out;
}

// The winners a student is shown, from a finalized week's or month's document:
// the list kept for their own gender (`topUsersMale` / `topUsersFemale`). A
// document from before those lists existed has only `topUsers`, which is then
// filtered to their gender.
List<Map<String, dynamic>> winnersForMe(
    Map<String, dynamic>? doc, GenderDirectory directory) {
  final own = doc?[directory.iAmFemale ? 'topUsersFemale' : 'topUsersMale'];
  if (own is List) {
    return [for (final u in own) Map<String, dynamic>.from(u as Map)];
  }
  final legacy = doc?['topUsers'];
  if (legacy is! List) return [];
  return [
    for (final u in legacy)
      if (directory.sameByName((u as Map)['name']?.toString()))
        Map<String, dynamic>.from(u),
  ];
}
