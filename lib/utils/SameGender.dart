import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../services/StudentApi.dart';

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

// Competition categories. Students who stay at Hostel or Localite compete TOGETHER
// in one category, separate from FOLK; each category is ranked by gender too, so
// there are four independent rankings. The server decides the category (from the
// student's residence) and stamps it on the scorecard / competition documents.
const String kCategoryFolk = 'folk';
const String kCategoryHostelLocalite = 'hostel_localite';

String _categoryOf(String? c) =>
    c == kCategoryHostelLocalite ? kCategoryHostelLocalite : kCategoryFolk;

// The gender of a users document's data: 'female' only when it says so.
String genderOfData(Map<String, dynamic>? data) =>
    data != null && data['gender'] == kFemale ? kFemale : kMale;

class GenderDirectory {
  const GenderDirectory({
    required this.mine,
    required this.femaleNames,
    required this.femaleUids,
    this.category = kCategoryFolk,
  });

  // The signed-in student's gender: 'male' or 'female'.
  final String mine;

  // The signed-in student's competition category: 'folk' or 'hostel_localite'.
  final String category;
  final Set<String> femaleNames;
  final Set<String> femaleUids;

  bool get iAmFemale => mine == kFemale;

  bool get isHostelLocalite => category == kCategoryHostelLocalite;

  // Id of my own ranking in a finalized week's / month's results:
  // `folk_male`, `folk_female`, `hostel_localite_male`, `hostel_localite_female`.
  String get rankingId => '${category}_$mine';

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
    // The directory holds the student's category and gender, which a guide can change at
    // any time: it is read again after [_maxAge] instead of being kept for the whole session.
    final loadedAt = _loadedAt[uid];
    if (loadedAt != null && DateTime.now().difference(loadedAt) > _maxAge) {
      _cache.remove(uid);
    }
    return _cache.putIfAbsent(uid, () {
      _loadedAt[uid] = DateTime.now();
      return _load(uid);
    }).catchError((Object e) {
      // A failed read is not kept: the next call tries again.
      _cache.remove(uid);
      _loadedAt.remove(uid);
      throw e;
    });
  }

  static const Duration _maxAge = Duration(seconds: 60);
  static final Map<String, DateTime> _loadedAt = {};
  static final Map<String, Future<GenderDirectory>> _cache = {};

  @visibleForTesting
  static Future<GenderDirectory> Function()? _loaderForTests;

  @visibleForTesting
  static void useForTests(Future<GenderDirectory> Function()? loader) {
    _loaderForTests = loader;
    _cache.clear();
    _loadedAt.clear();
  }

  // Forget everything (on sign-out).
  static void reset() {
    _cache.clear();
    _loadedAt.clear();
  }

  @visibleForTesting
  static Future<GenderDirectory> forCurrentUserForTestsViaApi() => _load('test');

  static Future<GenderDirectory> _load(String uid) async {
    // One server call (functions/studentCallables.js `getGenderDirectory`): a
    // student cannot read other students' documents any more, so the list of
    // female names / uids is built on the server.
    final d = await StudentApi.instance.getGenderDirectory();
    return GenderDirectory(
      mine: d.mine == kFemale ? kFemale : kMale,
      category: _categoryOf(d.category),
      femaleNames: d.femaleNames,
      femaleUids: d.femaleUids,
    );
  }
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

// A finalized week's / month's results are split into one document per gender
// (`.../{id}/byGender/{male|female}`), so a student can only ever read their own
// gender's: [parent] is the result document (`competition-results/weekly/weeks/{id}`,
// `.../monthly/months/{id}`, or a `-participants` one) and [field] the list inside
// the gender document ('topUsers' or 'participants').
//
// Results are also split by category: `.../{id}/byCategory/{category}_{gender}`.
// That is read first (a student sees only their own category AND gender); a week
// finalized before categories existed has only `byGender`, which is FOLK, so a FOLK
// student falls back to it. A Hostel / Localite student never reads `byGender`.
Future<List<Map<String, dynamic>>> readMyGenderList(
  DocumentReference<Map<String, dynamic>> parent,
  String field,
) async {
  final directory = await GenderDirectory.forCurrentUser();
  var snap = await parent.collection('byCategory').doc(directory.rankingId).get();
  if (!snap.exists && !directory.isHostelLocalite) {
    snap = await parent.collection('byGender').doc(directory.mine).get();
  }
  final list = snap.data()?[field];
  if (list is! List) return [];
  return [for (final u in list) Map<String, dynamic>.from(u as Map)];
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
