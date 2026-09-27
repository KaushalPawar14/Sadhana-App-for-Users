import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  static Stream<Timestamp?> seenAt(String viewerId, String featureKey) {
    if (viewerId.isEmpty) return Stream.value(null);
    return _col
        .doc(viewerId)
        .snapshots()
        .map((doc) => doc.data()?[featureKey] as Timestamp?);
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
    return _col.doc(viewerId).snapshots().map((doc) {
      final feature = doc.data()?[featureKey];
      if (feature is Map) return feature[subKey] as Timestamp?;
      return null;
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
    return _col.doc(viewerId).snapshots().map((doc) {
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
        subA = latestActivity.listen((v) {
          latest = v;
          gotLatest = true;
          emit();
        });
        subB = lastSeen.listen((v) {
          seen = v;
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
