import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;

/// Reads a student's sadhana report HISTORY from the collection of his CURRENT category ONLY.
///
/// ---------------------------------------------------------------------------
/// ⚠️ Reports are CATEGORY-SEPARATED (product-owner decision; it replaces the earlier
/// "merge both collections so history survives a residence change" rule)
/// ---------------------------------------------------------------------------
/// A report lives in `sadhana-reports` (FOLK) or `hostel-sadhana` (Hostel / Localite) depending on the
/// student's category when he filed it. A student's data is read ONLY from the collection of his
/// CURRENT category: the calendar, the days-submitted and streak tiles, the day pop-up, the Insights
/// graphs and statistics. The other category's reports are simply not read: those days show as not
/// submitted, and everything counts from zero. NOTHING is deleted or moved, so when a guide switches
/// him back, that category's saved reports show again.
///
/// The category follows the student's profile LIVE ([ReportCategory]): when a guide changes it, every
/// screen reading through this file switches at once - no restart.
///
/// Not affected: the all-time best figures on the Profile (best rounds / best reading) stay all-time.
const String kFolkReports = 'sadhana-reports';
const String kHostelReports = 'hostel-sadhana';

/// The report collection of a category, from the residence role: Hostel and Localite -> `hostel-sadhana`;
/// everyone else (FOLK, or no role yet) -> `sadhana-reports`.
String reportCollectionForRole(String? role) {
  final r = (role ?? '').trim();
  return r == 'Stay at Hostel' || r == 'Stay at Localite' ? kHostelReports : kFolkReports;
}

/// The signed-in student's CURRENT report collection, kept live from `users/{uid}.role`.
/// Screens read [collection] and listen to this notifier to reload when a guide changes the category.
class ReportCategory extends ChangeNotifier {
  ReportCategory._();
  static final ReportCategory instance = ReportCategory._();

  String? _role;
  String? _uid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Completer<void>? _first;

  /// `sadhana-reports` or `hostel-sadhana`.
  String get collection => reportCollectionForRole(_role);
  bool get isHostelLocalite => collection == kHostelReports;
  String? get role => _role;

  /// Starts following the signed-in student's profile (once per sign-in; safe to call again).
  void start({FirebaseFirestore? firestore, String? uid}) {
    try {
      final id = uid ?? FirebaseAuth.instance.currentUser?.uid;
      if (id == null) return;
      if (_sub != null && _uid == id) return;
      _sub?.cancel();
      _uid = id;
      _first = Completer<void>();
      _sub = (firestore ?? FirebaseFirestore.instance).collection('users').doc(id).snapshots().listen((snap) {
        _apply(snap.data()?['role']?.toString());
        if (!(_first?.isCompleted ?? true)) _first!.complete();
      }, onError: (Object _) {
        if (!(_first?.isCompleted ?? true)) _first!.complete();
      });
    } catch (_) {
      // Firebase is not up (a test, or very early start-up): the role this screen was built with is used.
      _sub = null;
      _first = null;
    }
  }

  /// Waits (briefly) for the first answer, so a first read already uses the right collection.
  Future<void> ready({Duration timeout = const Duration(seconds: 3)}) async {
    if (_sub == null) start();
    final f = _first?.future;
    if (f == null) return;
    await f.timeout(timeout, onTimeout: () {});
  }

  void _apply(String? role) {
    final before = collection;
    _role = role;
    if (collection != before) notifyListeners();
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _role = null;
  }

  /// Tests set the category directly (and may change it to simulate a guide switching it).
  @visibleForTesting
  void debugSetRole(String? role) {
    _sub?.cancel();
    _sub = null;
    _first = Completer<void>()..complete();
    _apply(role);
  }

  @visibleForTesting
  void debugReset() {
    stop();
    _first = null;
    _role = null;
  }
}

CollectionReference<Map<String, dynamic>> _datesRef(
  String collection,
  String studentName,
) {
  return FirebaseFirestore.instance
      .collection(collection)
      .doc(studentName)
      .collection('dates');
}

/// Every date-doc for [studentName] in his CURRENT category's collection (one read). [collection] is for
/// tests; the app lets the live category decide.
Future<Map<String, Map<String, dynamic>>> fetchDateReports(
  String studentName, {
  String? collection,
}) async {
  final merged = <String, Map<String, dynamic>>{};
  if (studentName.isEmpty) return merged;
  if (collection == null) await ReportCategory.instance.ready();
  final snap = await _datesRef(collection ?? ReportCategory.instance.collection, studentName).get();
  for (final doc in snap.docs) {
    merged[doc.id] = doc.data();
  }
  return merged;
}

/// One specific date's report from his CURRENT category's collection - null if he has none there (a report
/// filed under the other category does not count).
Future<Map<String, dynamic>?> fetchDateReport(
  String studentName,
  String dateId, {
  String? collection,
}) async {
  if (studentName.isEmpty) return null;
  if (collection == null) await ReportCategory.instance.ready();
  final doc = await _datesRef(collection ?? ReportCategory.instance.collection, studentName).doc(dateId).get();
  return doc.exists ? doc.data() : null;
}

/// Live "which dates have a report" set from his CURRENT category's collection, for the calendar's
/// day-colouring. It FOLLOWS the category: when a guide changes it, the stream switches to the new
/// collection by itself (the other category's days turn red, the new category's saved days appear).
///
/// An error from the collection's stream is forwarded to the listener (`onError`), so the Calendar shows
/// its Retry instead of sitting on its loading ghost. [snapshotsFor] is for tests only; the app never passes it.
Stream<Set<String>> availableDatesStream(
  String studentName, {
  @visibleForTesting
  Stream<QuerySnapshot<Map<String, dynamic>>> Function(String collection)? snapshotsFor,
}) {
  if (studentName.isEmpty) {
    return Stream<Set<String>>.value(<String>{});
  }
  late StreamController<Set<String>> controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? inner;
  String? current;

  void listenCollection() {
    final collection = ReportCategory.instance.collection;
    if (collection == current && inner != null) return;
    current = collection;
    inner?.cancel();
    inner = (snapshotsFor?.call(collection) ?? _datesRef(collection, studentName).snapshots()).listen((snap) {
      controller.add(snap.docs.map((d) => d.id).toSet());
    }, onError: (Object error, StackTrace stackTrace) {
      controller.addError(error, stackTrace);
    });
  }

  controller = StreamController<Set<String>>.broadcast(
    onListen: () {
      if (snapshotsFor == null) ReportCategory.instance.start();
      ReportCategory.instance.addListener(listenCollection);
      listenCollection();
    },
    onCancel: () {
      ReportCategory.instance.removeListener(listenCollection);
      inner?.cancel();
      inner = null;
      current = null;
    },
  );
  return controller.stream;
}
