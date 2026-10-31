import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Per-viewer "have I seen this yet" markers — Master Task 2026-09-10,
/// Part 6. Mirrors the Guide app's own `utils/SeenMarkers.dart` exactly
/// (same collection, same shape, same reasoning) — see that file's own
/// header for the full Rule 12 justification. Kept as a second, parallel
/// copy rather than a shared package because these two apps have no shared
/// package between them today (every cross-app "same idea" file in this
/// project — e.g. `utils/NotificationRouter.dart` — is duplicated the same
/// way, not factored into a third package).
///
/// `viewerId` here is the Student app's own real identity: `FirebaseAuth.
/// instance.currentUser.uid` — unlike the Guide app's `_selectedGuide`
/// code, students really do sign in individually.
class SeenMarkers {
  static final _col = FirebaseFirestore.instance.collection('seenMarkers');

  /// "Everything is seen": what a seen-field reads as while the student's OWN write of it is still on its way to the server. A pending `serverTimestamp()` is empty on his own
  /// screen, and empty means "never seen": the dot flashed (and came back for a moment) between a tap and the server's answer. A pending write of one's own seen-field is a seen-field.
  static final Timestamp everythingSeen = Timestamp(253402300799, 0);

  /// A snapshot is LIVE when it is not just the stale local cache (the first frame after a start can be an old cache saying "unseen" before the server has answered): from the
  /// server, or carrying the student's own pending write.
  @visibleForTesting
  static bool isLive({required bool fromCache, required bool hasPendingWrites}) => !fromCache || hasPendingWrites;

  /// The value of a seen-field: its timestamp; [everythingSeen] while his own write of it is pending; else null (never seen).
  @visibleForTesting
  static Timestamp? seenValue(Object? raw, {required bool pending}) => raw is Timestamp ? raw : (pending ? everythingSeen : null);

  /// The student's marker document of [db], live snapshots only (metadata changes included so the server's answer to a local write arrives too).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> liveFrom(FirebaseFirestore db, String viewerId) =>
      db.collection('seenMarkers').doc(viewerId).snapshots(includeMetadataChanges: true).where((s) => isLive(fromCache: s.metadata.isFromCache, hasPendingWrites: s.metadata.hasPendingWrites));

  static Stream<Timestamp?> seenAt(String viewerId, String featureKey) {
    if (viewerId.isEmpty) return Stream.value(null);
    return liveFrom(FirebaseFirestore.instance, viewerId).map((doc) => seenValue(doc.data()?[featureKey], pending: doc.metadata.hasPendingWrites));
  }

  static Future<void> markSeen(String viewerId, String featureKey) async {
    if (viewerId.isEmpty) return;
    await _col.doc(viewerId).set({
      featureKey: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<Timestamp?> seenAtSub(
      String viewerId, String featureKey, String subKey) {
    if (viewerId.isEmpty || subKey.isEmpty) return Stream.value(null);
    return liveFrom(FirebaseFirestore.instance, viewerId).map((doc) {
      final feature = doc.data()?[featureKey];
      return seenValue(feature is Map ? feature[subKey] : null, pending: doc.metadata.hasPendingWrites);
    });
  }

  static Future<void> markSeenSub(
      String viewerId, String featureKey, String subKey) async {
    if (viewerId.isEmpty || subKey.isEmpty) return;
    await _col.doc(viewerId).set({
      featureKey: {subKey: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  /// See the Guide app's own `subCursors` doc comment — identical
  /// contract.
  static Stream<Map<String, Timestamp>> subCursors(
      String viewerId, String featureKey) {
    if (viewerId.isEmpty) return Stream.value(const {});
    return liveFrom(FirebaseFirestore.instance, viewerId).map((doc) {
      final feature = doc.data()?[featureKey];
      if (feature is! Map) return const {};
      final out = <String, Timestamp>{};
      feature.forEach((k, v) {
        if (v is Timestamp) out[k.toString()] = v;
      });
      return out;
    });
  }

  /// See the Guide app's own `unseenFrom` doc comment — identical
  /// contract: call ONCE per feature with two already-hoisted input
  /// streams, never fresh inside `build()`.
  static Stream<bool> unseenFrom(
      Stream<Timestamp?> latestActivity, Stream<Timestamp?> lastSeen) {
    late StreamController<bool> controller;
    Timestamp? latest;
    Timestamp? seen;
    var gotLatest = false;
    var gotSeen = false;
    StreamSubscription? subA, subB;

    void emit() {
      if (!gotLatest || !gotSeen) return;
      final isUnseen =
          latest != null && (seen == null || latest!.compareTo(seen!) > 0);
      controller.add(isUnseen);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        // A failing input (offline, or refused by the rules) is "nothing": no dot, never an unhandled error.
        subA = latestActivity.listen((v) {
          latest = v;
          gotLatest = true;
          emit();
        }, onError: (Object _) {
          latest = null;
          gotLatest = true;
          emit();
        });
        subB = lastSeen.listen((v) {
          seen = v;
          gotSeen = true;
          emit();
        }, onError: (Object _) {
          seen = null;
          gotSeen = true;
          emit();
        });
      },
      onCancel: () {
        subA?.cancel();
        subB?.cancel();
      },
    );
    return controller.stream;
  }
}
