import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'LeaderboardData.dart';

/// The dot trail of the published RESULTS (weekly results every Monday, monthly results on the 1st).
///
/// "New results" = the server has finalised a period (`competition-results/weekly_meta.last_week_finalized`, e.g.
/// "2026-W42"; `monthly_meta.last_month_finalized`, e.g. "2026-09") and THIS student has not opened that period's
/// Results yet. What a student has seen is kept per student per period id in the existing seen-markers document
/// (`seenMarkers/{uid}.resultsSeen.{period}_{id}`, written with a server timestamp, the same document the other dots use).
///
/// Nothing clears a dot except opening that period's Results ([markSeen]), and each period is tracked on its own, so a
/// Monday that is also the 1st simply has both dots.
class ResultsDots {
  ResultsDots(this.db, this.uid);

  final FirebaseFirestore db;
  final String uid;

  static const String seenField = 'resultsSeen';

  static ResultsDots? _shared;

  /// Tests hand in their own (an in-memory database).
  @visibleForTesting
  static ResultsDots? override;

  /// The signed-in student's (one per signed-in student); null when nobody is signed in.
  static ResultsDots? forCurrentUser() {
    final o = override;
    if (o != null) return o;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      if (_shared == null || _shared!.uid != uid) _shared = ResultsDots(FirebaseFirestore.instance, uid);
      return _shared;
    } catch (_) {
      return null; // Firebase is not up (a screen test): no dots
    }
  }

  /// A Results page was opened (from the Leaderboard or straight from a notification): that period's dots go.
  static void opened(BoardPeriod period) => forCurrentUser()?.markSeen(period);

  static String _metaDoc(BoardPeriod p) => p == BoardPeriod.weekly ? 'weekly_meta' : 'monthly_meta';
  static String _metaField(BoardPeriod p) => p == BoardPeriod.weekly ? 'last_week_finalized' : 'last_month_finalized';

  /// The seen-marker key of one period id: "weekly_2026-W42".
  static String seenKey(BoardPeriod p, String id) => '${p.key}_$id';

  /// The id of the latest published results of [period] (null: none yet).
  Stream<String?> latestId(BoardPeriod period) => db
      .collection('competition-results')
      .doc(_metaDoc(period))
      .snapshots()
      .map((s) => s.data()?[_metaField(period)])
      .map((v) => v is String && v.isNotEmpty ? v : null);

  /// Which period ids this student has opened the Results of.
  Stream<Set<String>> seenKeys() => db.collection('seenMarkers').doc(uid).snapshots().map((s) {
        final m = s.data()?[seenField];
        return m is Map ? m.keys.map((k) => k.toString()).toSet() : <String>{};
      });

  /// Are there published results of [period] this student has not opened yet? A failing input counts as "no dot".
  /// Every listener gets its own live subscription (`Stream.multi`), so a widget that starts listening later still gets
  /// the current answer at once and a stream can be listened to again.
  Stream<bool> unseen(BoardPeriod period) => Stream<bool>.multi((controller) {
        String? id;
        Set<String>? seen;
        var gotId = false;
        var gotSeen = false;
        void emit() {
          if (!gotId || !gotSeen) return;
          controller.add(id != null && !seen!.contains(seenKey(period, id!)));
        }

        final a = latestId(period).listen((v) {
          id = v;
          gotId = true;
          emit();
        }, onError: (Object _) {
          id = null;
          gotId = true;
          emit();
        });
        final b = seenKeys().listen((v) {
          seen = v;
          gotSeen = true;
          emit();
        }, onError: (Object _) {
          seen = <String>{};
          gotSeen = true;
          emit();
        });
        controller.onCancel = () async {
          await a.cancel();
          await b.cancel();
        };
      });

  /// Weekly OR monthly results are new (the Insights tab and the Leaderboard tile).
  Stream<bool> get anyUnseen => Stream<bool>.multi((controller) {
        final latest = <bool?>[null, null];
        void emit() {
          if (latest.any((v) => v == null)) return;
          controller.add(latest.any((v) => v == true));
        }

        final subs = <StreamSubscription>[
          for (final (i, p) in BoardPeriod.values.indexed)
            unseen(p).listen((v) {
              latest[i] = v;
              emit();
            }, onError: (Object _) {
              latest[i] = false;
              emit();
            }),
        ];
        controller.onCancel = () async {
          for (final s in subs) {
            await s.cancel();
          }
        };
      });

  /// The student opened the Results of [period]: its current id is marked seen (every dot of that period goes). Nothing
  /// to mark when no results are published yet. Failures are swallowed: a dot that stays is the safe outcome.
  Future<void> markSeen(BoardPeriod period) async {
    try {
      final doc = await db.collection('competition-results').doc(_metaDoc(period)).get();
      final id = doc.data()?[_metaField(period)];
      if (id is! String || id.isEmpty) return;
      await db.collection('seenMarkers').doc(uid).set({
        seenField: {seenKey(period, id): FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
