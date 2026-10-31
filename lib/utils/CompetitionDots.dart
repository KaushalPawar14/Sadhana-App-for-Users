import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'SeenMarkers.dart';
import 'UnseenDot.dart';

/// The dot trail of the CHANTING COMPETITIONS a guide (or a HOD) starts for the student's roster:
///
///   Profile tab (bottom bar) -> the "My Competitions" row -> the competition's own card (and, when it ends, its RESULT card).
///
/// What is new, per student and per competition:
///   `new_<challengeId>`     a competition with status "active" the student has not seen yet;
///   `result_<challengeId>`  a competition that ended ("achieved" or "missed" = its results are published) inside its result window, whose result the student has not seen.
/// What a student has seen is kept per student in the existing seen-markers document (`seenMarkers/{uid}.chantingSeen.{key}`, a server timestamp). Nothing clears a dot except the
/// student seeing that competition: opening "My Competitions" and leaving it marks what was shown (the card keeps its dot while he is on the page, so he can see which one is new),
/// and dismissing the winner card marks that result. Each competition is tracked on its own: a second competition lights the trail again.
///
/// No flash: nothing is shown until BOTH the competitions and the seen markers are live (a stale cache is not shown), and a seen-marker that is still on its way to the server is already
/// a seen-marker (the key is in the map the moment it is written).
class CompetitionDots {
  CompetitionDots(this.db, this.uid);

  final FirebaseFirestore db;
  final String uid;

  static const String seenField = 'chantingSeen';

  /// The same two days after the competition's own date the winner card and the server (`functions/challenges.js`) use: an older result is not "new".
  static const int resultWindowDays = 2;

  /// Today's date for the result window (tests).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static CompetitionDots? _shared;

  /// Tests hand in their own (an in-memory database).
  @visibleForTesting
  static CompetitionDots? override;

  /// The signed-in student's (one per signed-in student); null when nobody is signed in.
  static CompetitionDots? forCurrentUser() {
    final o = override;
    if (o != null) return o;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      if (_shared == null || _shared!.uid != uid) _shared = CompetitionDots(FirebaseFirestore.instance, uid);
      return _shared;
    } catch (_) {
      return null; // Firebase is not up (a screen test): no dots
    }
  }

  static String newKey(String challengeId) => 'new_$challengeId';
  static String resultKey(String challengeId) => 'result_$challengeId';

  /// Whether a competition's result is older than its window (the winner card does not show it either).
  static bool pastResultWindow(Map<String, dynamic> challenge, DateTime now) {
    final ts = challenge['targetDate'];
    if (ts is! Timestamp) return true;
    return now.isAfter(ts.toDate().add(const Duration(days: resultWindowDays)));
  }

  /// THE RULE (pure): the keys of what is new for a student, from the competitions of his roster and the keys he has seen.
  static Set<String> unseenOf(Iterable<Map<String, dynamic>> challenges, Set<String> seen, DateTime now) {
    final out = <String>{};
    for (final c in challenges) {
      final id = (c['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final status = (c['status'] ?? '').toString();
      if (status == 'active') {
        if (!seen.contains(newKey(id))) out.add(newKey(id));
      } else if ((status == 'achieved' || status == 'missed') && !pastResultWindow(c, now)) {
        if (!seen.contains(resultKey(id))) out.add(resultKey(id));
      }
    }
    return out;
  }

  /// The competitions the student is part of: those of his guide (`guideId`), those a HOD gave to that guide (`guideIds`) and the HOD's for every student (`allStudents`) - the same
  /// three conditions "My Competitions" reads. Live; a failing read is "none".
  Stream<List<Map<String, dynamic>>> challenges() => Stream<List<Map<String, dynamic>>>.multi((controller) {
        StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
        var cancelled = false;
        () async {
          var guideId = '';
          try {
            guideId = ((await db.collection('users').doc(uid).get()).data()?['guideId'] ?? '').toString();
          } catch (_) {}
          if (cancelled) return;
          if (guideId.isEmpty) {
            controller.add(const []);
            return;
          }
          sub = db
              .collection('chantingChallenges')
              .where(Filter.or(
                Filter('guideId', isEqualTo: guideId),
                Filter('guideIds', arrayContains: guideId),
                Filter('allStudents', isEqualTo: true),
              ))
              .snapshots()
              .listen((s) => controller.add([for (final d in s.docs) {...d.data(), 'id': d.id}]), onError: (Object _) => controller.add(const []));
        }();
        controller.onCancel = () async {
          cancelled = true;
          await sub?.cancel();
        };
      });

  /// Which keys this student has seen (live snapshots only; a key still being written counts as seen).
  Stream<Set<String>> seenKeys() => SeenMarkers.liveFrom(db, uid).map((s) {
        final m = s.data()?[seenField];
        return m is Map ? m.keys.map((k) => k.toString()).toSet() : <String>{};
      });

  /// What is new now, live. Nothing is emitted until the competitions AND the seen markers are known.
  Stream<Set<String>> unseenKeysStream({DateTime Function()? clock}) => Stream<Set<String>>.multi((controller) {
        List<Map<String, dynamic>>? list;
        Set<String>? seen;
        void emit() {
          if (list == null || seen == null) return;
          controller.add(unseenOf(list!, seen!, (clock ?? CompetitionDots.clock)()));
        }

        final a = challenges().listen((v) {
          list = v;
          emit();
        }, onError: (Object _) {
          list = const [];
          emit();
        });
        final b = seenKeys().listen((v) {
          seen = v;
          emit();
        }, onError: (Object _) {
          seen = <String>{};
          emit();
        });
        controller.onCancel = () async {
          await a.cancel();
          await b.cancel();
        };
      });

  /// Is anything new (the Profile tab and the "My Competitions" row)?
  Stream<bool> get anyUnseen => unseenKeysStream().map((s) => s.isNotEmpty);

  /// Is this one competition card (or its result) new?
  Stream<bool> unseenFor(String key) => unseenKeysStream().map((s) => s.contains(key));

  /// The student has seen these (his competition's card, its result): the dots go. Failures are swallowed: a dot that stays is the safe outcome.
  Future<void> markSeen(Iterable<String> keys) async {
    final list = keys.where((k) => k.isNotEmpty).toList();
    if (list.isEmpty) return;
    try {
      await db.collection('seenMarkers').doc(uid).set({
        seenField: {for (final k in list) k: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

/// A small dot on one competition's card (or its result card) while it is new for this student. Hoists its stream in [initState].
class CompetitionDot extends StatefulWidget {
  const CompetitionDot({super.key, required this.dotKey, required this.child, this.offset = const Offset(10, 10)});

  /// `CompetitionDots.newKey(id)` or `CompetitionDots.resultKey(id)`.
  final String dotKey;
  final Widget child;
  final Offset offset;

  @override
  State<CompetitionDot> createState() => _CompetitionDotState();
}

class _CompetitionDotState extends State<CompetitionDot> {
  late Stream<bool> _unseen = CompetitionDots.forCurrentUser()?.unseenFor(widget.dotKey) ?? Stream.value(false);

  @override
  void didUpdateWidget(CompetitionDot old) {
    super.didUpdateWidget(old);
    if (old.dotKey != widget.dotKey) _unseen = CompetitionDots.forCurrentUser()?.unseenFor(widget.dotKey) ?? Stream.value(false);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
        stream: _unseen,
        builder: (context, snap) => UnseenBadge(key: ValueKey('competition-dot-${widget.dotKey}'), show: snap.data ?? false, offset: widget.offset, child: widget.child),
      );
}
