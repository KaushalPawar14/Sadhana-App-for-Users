import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads a student's sadhana report HISTORY across both residence-scoped
/// collections, merged by date — Master Task 2026-09-11, "Read reports from
/// both collections so history survives a residence change."
///
/// ---------------------------------------------------------------------------
/// Why this exists
/// ---------------------------------------------------------------------------
/// A report lives in `sadhana-reports` (FOLK) or `hostel-sadhana` (Hostel /
/// Localite) depending on the student's residence AT THE TIME they submitted
/// it. Switching residence later (`Guides/.../StudentProfilePage.dart`) never
/// moves any existing report (Rule 14/15) — it only changes which collection
/// FUTURE reports land in. A read that picks ONE collection based on the
/// student's CURRENT role therefore silently loses every report filed under
/// the other one. Every place in this app that reads a student's report
/// HISTORY (as opposed to writing today's own report, or checking only
/// today's own date — those still only ever need today's own current-role
/// collection) must read BOTH and merge. This file is the ONE place that
/// merge logic lives, so the rule below is enforced in a single spot rather
/// than re-implemented at each read site.
///
/// ---------------------------------------------------------------------------
/// ⚠️ One report per date, never summed (Part 2 of that task)
/// ---------------------------------------------------------------------------
/// A student can only ever have submitted ONE report for a given calendar
/// day — whichever collection matched their role at the time. So a given
/// date-doc-id can only genuinely exist in ONE of these two collections for
/// one student; it is never legitimate for both to hold real data for the
/// same date. Every function below merges BY DATE — at most one document per
/// date — and never sums or combines two collections' values for the same
/// date. If a date-id is ever somehow present in both (a data anomaly, not
/// something normal use produces), `sadhana-reports` wins and the
/// `hostel-sadhana` copy for that date is dropped entirely, never merged
/// field-by-field.
///
/// ---------------------------------------------------------------------------
/// Field differences are expected (Part 3 item 2)
/// ---------------------------------------------------------------------------
/// A FOLK-era day's document carries different fields (temple entry, daily
/// services) than a Hostel/Localite-era one (wake-up time). Every caller
/// already reads fields defensively (`data.containsKey(...)`) rather than
/// assuming a fixed shape, and that continues to be the right approach —
/// this file returns each date's document exactly as stored, never
/// synthesising or dropping fields.
const List<String> kSadhanaReportCollections = [
  'sadhana-reports',
  'hostel-sadhana',
];

CollectionReference<Map<String, dynamic>> _datesRef(
  String collection,
  String studentName,
) {
  return FirebaseFirestore.instance
      .collection(collection)
      .doc(studentName)
      .collection('dates');
}

/// Every date-doc for [studentName] across both collections, merged so at
/// most one document exists per date (first collection in
/// [kSadhanaReportCollections] wins on the — not expected in practice —
/// event of a real collision). Two reads total, regardless of how much
/// history exists (Part 3 item 4).
Future<Map<String, Map<String, dynamic>>> fetchMergedDateReports(
  String studentName,
) async {
  final merged = <String, Map<String, dynamic>>{};
  if (studentName.isEmpty) return merged;
  for (final collection in kSadhanaReportCollections) {
    final snap = await _datesRef(collection, studentName).get();
    for (final doc in snap.docs) {
      merged.putIfAbsent(doc.id, () => doc.data());
    }
  }
  return merged;
}

/// One specific date's report, checked across both collections — null if
/// neither has it. Never sums or combines two documents for the same date
/// (see this file's header): at most one collection can genuinely have it,
/// so the first hit is returned as-is.
Future<Map<String, dynamic>?> fetchMergedDateReport(
  String studentName,
  String dateId,
) async {
  if (studentName.isEmpty) return null;
  for (final collection in kSadhanaReportCollections) {
    final doc = await _datesRef(collection, studentName).doc(dateId).get();
    if (doc.exists) return doc.data();
  }
  return null;
}

/// Live "which dates have a report" set, combined from both collections'
/// own `.snapshots()` streams — for calendar day-colouring, where a
/// one-shot read would miss a report arriving while the screen stays open.
/// A plain set union: a student's own date-doc only ever lives in one of
/// the two collections, so there is nothing to reconcile between them.
Stream<Set<String>> mergedAvailableDatesStream(String studentName) {
  late StreamController<Set<String>> controller;
  final latest = <String, Set<String>>{};
  final subs = <StreamSubscription>[];

  void emit() {
    if (latest.length < kSadhanaReportCollections.length) return;
    controller.add(latest.values.expand((s) => s).toSet());
  }

  controller = StreamController<Set<String>>.broadcast(
    onListen: () {
      for (final collection in kSadhanaReportCollections) {
        subs.add(
          _datesRef(collection, studentName).snapshots().listen((snap) {
            latest[collection] = snap.docs.map((d) => d.id).toSet();
            emit();
          }),
        );
      }
    },
    onCancel: () {
      for (final s in subs) {
        s.cancel();
      }
    },
  );

  if (studentName.isEmpty) {
    return Stream<Set<String>>.value(<String>{});
  }
  return controller.stream;
}
