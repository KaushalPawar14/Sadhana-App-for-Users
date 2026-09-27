import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'SeenMarkers.dart';
import 'UnseenDot.dart';

/// Wraps a journey-card / nav item with an [UnseenBadge] driven by one
/// feature's "is there new content I haven't seen" state — Master Task
/// 2026-09-10, Part 6. Mirrors the Guide app's own `utils/
/// UnseenFeatureBadge.dart` exactly (same contract, same reasoning — see
/// that file's own header) except the viewer identity here is this app's
/// real one: `FirebaseAuth.instance.currentUser.uid`, not a guide code.
class UnseenFeatureBadge extends StatefulWidget {
  final Widget child;
  final String featureKey;
  final String? subKey;

  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(String uid)
      latestQuery;
  final String timestampField;
  final Timestamp? Function(Map<String, dynamic> data)? extractTimestamp;

  /// Aggregate mode — see the Guide app's own doc comment on this same
  /// field for the full contract.
  final String Function(String docId, Map<String, dynamic> data)? subKeyOf;

  /// See the Guide app's own `dotOffset` doc comment — identical contract
  /// (grid-squeeze fix, 2026-09-10, item 2).
  final Offset dotOffset;

  /// See the Guide app's own `fillParent` doc comment — identical
  /// contract (grid-squeeze / disappearing-icon fix, 2026-09-11). `false`
  /// (the default) is correct for every current caller in this app.
  final bool fillParent;

  const UnseenFeatureBadge({
    super.key,
    required this.child,
    required this.featureKey,
    required this.latestQuery,
    this.timestampField = 'updatedAt',
    this.extractTimestamp,
    this.subKey,
    this.subKeyOf,
    this.dotOffset = const Offset(2, -2),
    this.fillParent = false,
  });

  @override
  State<UnseenFeatureBadge> createState() => _UnseenFeatureBadgeState();
}

class _UnseenFeatureBadgeState extends State<UnseenFeatureBadge> {
  Stream<bool>? _unseen;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    if (widget.subKeyOf != null) {
      setState(() => _unseen = _aggregateUnseen(uid));
      return;
    }

    final latest = widget.latestQuery(uid).map((snap) {
      Timestamp? max;
      for (final doc in snap.docs) {
        final ts = widget.extractTimestamp != null
            ? widget.extractTimestamp!(doc.data())
            : doc.data()[widget.timestampField];
        if (ts is Timestamp && (max == null || ts.compareTo(max) > 0)) {
          max = ts;
        }
      }
      return max;
    });

    final seen = widget.subKey == null
        ? SeenMarkers.seenAt(uid, widget.featureKey)
        : SeenMarkers.seenAtSub(uid, widget.featureKey, widget.subKey!);

    setState(() => _unseen = SeenMarkers.unseenFrom(latest, seen));
  }

  Stream<bool> _aggregateUnseen(String uid) {
    late StreamController<bool> controller;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
    Map<String, Timestamp>? cursors;
    StreamSubscription? subA, subB;

    void emit() {
      if (docs == null || cursors == null) return;
      final anyUnseen = docs!.any((doc) {
        final ts = widget.extractTimestamp != null
            ? widget.extractTimestamp!(doc.data())
            : doc.data()[widget.timestampField];
        if (ts is! Timestamp) return false;
        final key = widget.subKeyOf!(doc.id, doc.data());
        final cursor = cursors![key];
        return cursor == null || ts.compareTo(cursor) > 0;
      });
      controller.add(anyUnseen);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        subA = widget.latestQuery(uid).listen((snap) {
          docs = snap.docs;
          emit();
        });
        subB = SeenMarkers.subCursors(uid, widget.featureKey).listen((c) {
          cursors = c;
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

  @override
  Widget build(BuildContext context) {
    final unseen = _unseen;
    if (unseen == null) return widget.child;

    return StreamBuilder<bool>(
      stream: unseen,
      builder: (context, snap) => UnseenBadge(
        show: snap.data ?? false,
        offset: widget.dotOffset,
        fillParent: widget.fillParent,
        child: widget.child,
      ),
    );
  }
}
