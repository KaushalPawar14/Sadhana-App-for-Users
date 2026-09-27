import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/MalaLoading.dart';

/// Chanting Competition — the student-facing view of the Guide app's
/// "Chanting Challenge" feature (`chantingChallenges` /
/// `chantingChallengeContributions`, written by `functions/challenges.js`).
///
/// ⚠️ **Not the same feature as `pages/Competition.dart`.** That is the
/// unrelated pre-existing "Folk Analysis" scorecard (`competition/{name}`).
/// This page reads a completely different pair of collections and has no
/// relationship to that one beyond the name.
///
/// This page is **read-only**. It never writes to `chantingChallenges` or
/// `chantingChallengeContributions` — those are written only by
/// `functions/challenges.js` (server-side, on a sadhana report write) and by
/// the guide's own create/close actions. A student's own rounds already
/// reach `currentTotal` through the existing sadhana submission flow; nothing
/// here duplicates or re-implements that.
///
/// `targetRounds` is a COLLECTIVE, whole-roster target — not a personal one.
/// The per-student bars below are a relative view of each student's own
/// contribution, not a personal pass/fail: the shared total vs. the shared
/// target is what actually decides the outcome, and is shown first.
///
/// Three states, driven by a live listener on `chantingChallenges` (see
/// `_ChantingCompetitionPageState`):
///   - Idle — no `status: "active"` challenge for this student's guide.
///   - Active — a challenge is active; live leaderboard from
///     `chantingChallengeContributions`.
///   - Winner summary — fires on a LIVE transition observed while this
///     listener is attached (the tracked challenge's own `status` flips from
///     "active" to "achieved" or "missed"), exactly as before **and now
///     also** the next time a participating student opens this page after
///     the fact (Part 5), via the additive `summarySeenBy` array field on
///     the challenge doc — written when the student dismisses the card, so
///     it shows exactly once per student per challenge, then never again,
///     even before the next challenge starts (the field lives on THAT
///     challenge's own document, so a new challenge always starts with no
///     `summarySeenBy` at all — no cross-challenge leakage is possible by
///     construction, not merely by convention).
///
///     ⚠️ **Result window (Master Task Part 1 item 4, 2026-09-10):** the
///     cold-open backfill above additionally skips any ended challenge more
///     than two days past its own `targetDate` — see `_pastResultWindow()`,
///     which matches `functions/challenges.js`'s `RESULT_WINDOW_DAYS`
///     exactly so client and server never disagree. A student who never
///     opens this page no longer sees an arbitrarily old result pop up; a
///     live active->ended transition witnessed while this screen is open is
///     unaffected (it is, by definition, happening within the window).
class ChantingCompetitionPage extends StatefulWidget {
  const ChantingCompetitionPage({super.key});

  @override
  State<ChantingCompetitionPage> createState() =>
      _ChantingCompetitionPageState();
}

class _ChantingCompetitionPageState extends State<ChantingCompetitionPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loadingGuide = true;

  /// Needed at dismiss time to write into `summarySeenBy` (Part 5) — kept as
  /// a field rather than re-reading `FirebaseAuth.instance.currentUser` each
  /// time, since `_init()` already resolves it once.
  String? _uid;

  StreamSubscription<QuerySnapshot>? _sub;
  bool _isFirstSnapshot = true;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — the
  /// contributions `StreamBuilder` inside `_activeState` used to construct
  /// its stream fresh on every call, itself called from `build()`. Unlike
  /// this file's other stream (`_sub`, already a one-time `initState`
  /// subscription with a proper `dispose()`), this one genuinely CANNOT be
  /// hoisted to a single `late final` field built once: `_trackedChallenge`
  /// — and the `challengeId` this stream filters on — legitimately changes
  /// over this screen's life as challenges start, end, and get replaced
  /// (`setState(() => _trackedChallenge = ...)` at several call sites
  /// above). Handled instead with [_contributionsStreamFor]: cached by
  /// challenge id, rebuilt only when that id actually changes — not on
  /// every rebuild of the same still-active challenge (which reassigns
  /// `_trackedChallenge` to a new map with the SAME id just to refresh
  /// fields like `currentTotal`).
  String? _contributionsStreamChallengeId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _contributionsStream;

  Stream<QuerySnapshot<Map<String, dynamic>>> _contributionsStreamFor(
      String challengeId) {
    if (_contributionsStreamChallengeId != challengeId) {
      _contributionsStreamChallengeId = challengeId;
      _contributionsStream = _firestore
          .collection('chantingChallengeContributions')
          .where('challengeId', isEqualTo: challengeId)
          .snapshots();
    }
    return _contributionsStream!;
  }

  /// The challenge currently being shown in the Active state, or null when
  /// idle. Includes 'id' merged into the map alongside the doc's fields.
  Map<String, dynamic>? _trackedChallenge;

  /// Set only while the winner card is on screen.
  bool _showWinner = false;
  Map<String, dynamic>? _winnerChallenge;
  List<Map<String, dynamic>> _winnerTop = [];
  Map<String, dynamic>? _pendingNextChallenge;
  Timer? _winnerTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _winnerTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadingGuide = false);
      return;
    }
    _uid = uid;

    String guideId = '';
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      guideId = (userDoc.data()?['guideId'] ?? '').toString();
    } catch (_) {
      // Falls through to the idle state below — no guide to query for.
    }

    if (!mounted) return;
    setState(() => _loadingGuide = false);

    if (guideId.isNotEmpty) _subscribe(guideId);
  }

  void _subscribe(String guideId) {
    // Three single-field OR clauses (verified against real data to need no
    // composite index — each disjunct is its own single-field filter, which
    // is what Firestore's OR queries evaluate as under the hood), sorted in
    // Dart. `guideId` alone is the original, unchanged condition; the other
    // two catch an HOD challenge scoped via `guideIds` or `allStudents`
    // (Part 2 of the HOD guide-selection feature) — a legacy/guide-created
    // challenge never carries either field, so those two clauses simply
    // never match it.
    _sub = _firestore
        .collection('chantingChallenges')
        .where(Filter.or(
          Filter('guideId', isEqualTo: guideId),
          Filter('guideIds', arrayContains: guideId),
          Filter('allStudents', isEqualTo: true),
        ))
        .snapshots()
        .listen(_onChallenges, onError: (_) {});
  }

  DateTime? _targetDateOf(QueryDocumentSnapshot doc) {
    final ts = (doc.data() as Map<String, dynamic>)['targetDate'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  /// Result window (Master Task Part 1 item 4, 2026-09-10) — matches
  /// `functions/challenges.js`'s own `RESULT_WINDOW_DAYS`/
  /// `pastResultWindow()` exactly: two days after `targetDate`, the SAME
  /// anchor field, so client and server can never disagree about whether
  /// a result is still "new." Used only in the cold-open backfill below —
  /// a LIVE transition (`_handleChallengeEnded` called while this screen's
  /// listener is already attached) is, by definition, happening right now,
  /// always within the window at that moment, so it needs no check here.
  static const int _resultWindowDays = 2;

  bool _pastResultWindow(Map<String, dynamic> data) {
    final ts = data['targetDate'];
    if (ts is! Timestamp) return true;
    final windowEnd =
        ts.toDate().add(const Duration(days: _resultWindowDays));
    return DateTime.now().isAfter(windowEnd);
  }

  /// When a non-active challenge actually ended, for ranking "most recent"
  /// among several unseen ones (Part 5). `closedAt` covers both the manual
  /// Close action and the deadline sweep; `achievedAt` covers the target
  /// being reached. Null when neither is set — deliberately not falling
  /// back to `targetDate`, which is when the challenge was AIMED at, not
  /// when it actually ended.
  DateTime? _endedAt(Map<String, dynamic> data) {
    final closedAt = data['closedAt'];
    if (closedAt is Timestamp) return closedAt.toDate();
    final achievedAt = data['achievedAt'];
    if (achievedAt is Timestamp) return achievedAt.toDate();
    return null;
  }

  void _onChallenges(QuerySnapshot snapshot) {
    final docs = snapshot.docs.toList()
      ..sort((a, b) {
        final da = _targetDateOf(a);
        final db = _targetDateOf(b);
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    Map<String, dynamic>? activeNow;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if ((data['status'] ?? '').toString() == 'active') {
        activeNow = {...data, 'id': doc.id};
        break;
      }
    }

    // First emission of this listener's lifetime (Part 5): before landing on
    // whatever is active right now, check whether this student has an ended
    // challenge they have not yet been shown a summary for. `docs` already
    // holds every challenge this student's roster is part of, any status —
    // no extra query needed (Rule 1: reuse what the subscription already
    // fetched).
    if (_isFirstSnapshot) {
      _isFirstSnapshot = false;

      final myUid = _uid;
      if (myUid != null) {
        Map<String, dynamic>? mostRecentUnseen;
        DateTime? mostRecentUnseenAt;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if ((data['status'] ?? '').toString() == 'active') continue;

          final seenBy = data['summarySeenBy'];
          if (seenBy is List && seenBy.contains(myUid)) continue;

          // Part 1 item 4 — "stop being surfaced": an ended challenge more
          // than two days past its own target date is settled history, not
          // a result this student was waiting on. Checked here rather than
          // by trusting `summarySeenBy` alone, since a student who never
          // opened this page at all would otherwise see an arbitrarily old
          // result pop up the next time they do.
          if (_pastResultWindow(data)) continue;

          final endedAt = _endedAt(data);
          // No reliable end timestamp to rank by — skip rather than guess
          // which of several such challenges is "the" recent one.
          if (endedAt == null) continue;

          if (mostRecentUnseenAt == null ||
              endedAt.isAfter(mostRecentUnseenAt)) {
            mostRecentUnseenAt = endedAt;
            mostRecentUnseen = {...data, 'id': doc.id};
          }
        }

        if (mostRecentUnseen != null) {
          // Reuses the exact live-transition path below: same contribution
          // fetch, same winner card, same "show the newly-active challenge
          // next" handoff via pendingNext.
          _handleChallengeEnded(mostRecentUnseen, pendingNext: activeNow);
          return;
        }
      }

      setState(() => _trackedChallenge = activeNow);
      return;
    }

    final trackedId = _trackedChallenge?['id'] as String?;

    if (trackedId == null) {
      // Was idle. A new active challenge appearing needs no student action.
      if (activeNow != null) {
        setState(() => _trackedChallenge = activeNow);
      }
      return;
    }

    QueryDocumentSnapshot? trackedDoc;
    for (final doc in docs) {
      if (doc.id == trackedId) {
        trackedDoc = doc;
        break;
      }
    }

    if (trackedDoc == null) {
      // The tracked challenge doc is gone outright (not a designed
      // transition) — fall back quietly to whatever is active now, with no
      // winner data to show.
      setState(() => _trackedChallenge = activeNow);
      return;
    }

    final statusNow =
        ((trackedDoc.data() as Map<String, dynamic>)['status'] ?? '')
            .toString();

    if (statusNow == 'active') {
      // Still ongoing — refresh with the latest fields (e.g. currentTotal).
      setState(() => _trackedChallenge = {
            ...trackedDoc!.data() as Map<String, dynamic>,
            'id': trackedDoc.id,
          });
      return;
    }

    // Live transition: active -> achieved/missed.
    _handleChallengeEnded(
      {...trackedDoc.data() as Map<String, dynamic>, 'id': trackedDoc.id},
      pendingNext: activeNow,
    );
  }

  Future<void> _handleChallengeEnded(
    Map<String, dynamic> ended, {
    Map<String, dynamic>? pendingNext,
  }) async {
    List<Map<String, dynamic>> top = [];
    try {
      // One-time read, not a stream: a contribution is locked at first
      // submission and never updated again, so nothing here can change once
      // the challenge has already left "active".
      final snap = await _firestore
          .collection('chantingChallengeContributions')
          .where('challengeId', isEqualTo: ended['id'])
          .get();

      top = snap.docs.map((d) => d.data()).toList()
        ..sort((a, b) {
          final ra = a['rounds'] is num ? (a['rounds'] as num).toInt() : 0;
          final rb = b['rounds'] is num ? (b['rounds'] as num).toInt() : 0;
          return rb.compareTo(ra);
        });
    } catch (_) {
      // Winner card still shows with the collective total even if the
      // per-student breakdown could not be read.
    }

    if (!mounted) return;

    setState(() {
      _winnerChallenge = ended;
      _winnerTop = top;
      _showWinner = true;
      _pendingNextChallenge = pendingNext;
      _trackedChallenge = null;
    });

    _winnerTimer?.cancel();
    _winnerTimer = Timer(const Duration(seconds: 6), _dismissWinner);
  }

  void _dismissWinner() {
    _winnerTimer?.cancel();

    // Part 5 — additive on the challenge's own doc (Rule 12: no new
    // collection: which students have seen an ended challenge's summary is
    // intrinsic to that one challenge, not a separate entity, and a
    // per-challenge array is the same shape `chantingChallengeContributions`
    // already uses for "who did what for this challenge"). Fire-and-forget:
    // a student dismissing a dialog they have already read should not wait
    // on a write completing, and the worst case of a failure is seeing this
    // same summary once more on a future cold open, never a crash.
    final endedId = _winnerChallenge?['id'] as String?;
    final myUid = _uid;
    if (endedId != null && myUid != null) {
      _firestore.collection('chantingChallenges').doc(endedId).set({
        'summarySeenBy': FieldValue.arrayUnion([myUid]),
      }, SetOptions(merge: true)).catchError((_) {});
    }

    if (!mounted) return;
    setState(() {
      _showWinner = false;
      _trackedChallenge = _pendingNextChallenge;
      _winnerChallenge = null;
      _winnerTop = [];
      _pendingNextChallenge = null;
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            title: Text(
              "Chanting Competition",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            backgroundColor: colorProvider.color,
            elevation: 0,
          ),
          body: _loadingGuide
              ? const CustomLoader()
              : _showWinner
                  ? _winnerCard(colorProvider)
                  : (_trackedChallenge == null
                      ? _idleState(colorProvider)
                      : _activeState(colorProvider, _trackedChallenge!)),
        );
      },
    );
  }

  Widget _idleState(ColorProvider colorProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.self_improvement,
                size: 56, color: colorProvider.secondColor.withOpacity(.4)),
            const SizedBox(height: 18),
            Text(
              "No competition right now",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorProvider.secondColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Your guide hasn't started a chanting competition yet. "
              "When one begins, it will show up here automatically — "
              "no need to check back constantly.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colorProvider.secondColor.withOpacity(.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeState(
      ColorProvider colorProvider, Map<String, dynamic> challenge) {
    final name = (challenge['name'] ?? '').toString();
    final target = challenge['targetRounds'] is num
        ? (challenge['targetRounds'] as num).toInt()
        : 0;
    final total = challenge['currentTotal'] is num
        ? (challenge['currentTotal'] as num).toInt()
        : 0;
    final ts = challenge['targetDate'];
    final dateText =
        ts is Timestamp ? DateFormat('dd MMM yyyy').format(ts.toDate()) : '';
    final collectiveFraction =
        target <= 0 ? 0.0 : (total / target).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF00695C),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? "Chanting Competition" : name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (dateText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  dateText,
                  style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(.85)),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    "$total",
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    " / $target rounds — together",
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(.85)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: collectiveFraction,
                  minHeight: 8,
                  backgroundColor: Colors.white.withOpacity(.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Every student's own rounds add to this shared total. "
                "This is a group goal, not a personal one.",
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(.75)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Who's contributing",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorProvider.secondColor,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: _contributionsStreamFor(challenge['id'] as String),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final rows = snapshot.data!.docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              final rounds =
                  data['rounds'] is num ? (data['rounds'] as num).toInt() : 0;
              return {
                'name': (data['studentName'] ?? '').toString(),
                'rounds': rounds,
              };
            }).toList()
              ..sort((a, b) =>
                  (b['rounds'] as int).compareTo(a['rounds'] as int));

            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  "No one has submitted rounds for this yet — be the first!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, color: colorProvider.secondColor.withOpacity(.7)),
                ),
              );
            }

            return Column(
              children: rows
                  .map((r) => _leaderboardRow(
                        colorProvider,
                        r['name'] as String,
                        r['rounds'] as int,
                        target,
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _leaderboardRow(
      ColorProvider colorProvider, String name, int rounds, int target) {
    final fraction = target <= 0 ? 0.0 : (rounds / target).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? "Unknown" : name,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                "$rounds rounds",
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00695C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF00695C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _winnerCard(ColorProvider colorProvider) {
    final challenge = _winnerChallenge ?? {};
    final name = (challenge['name'] ?? '').toString();
    final status = (challenge['status'] ?? '').toString();
    final target = challenge['targetRounds'] is num
        ? (challenge['targetRounds'] as num).toInt()
        : 0;
    final total = challenge['currentTotal'] is num
        ? (challenge['currentTotal'] as num).toInt()
        : 0;
    final achieved = status == 'achieved';

    int topRounds = 0;
    if (_winnerTop.isNotEmpty) {
      final r = _winnerTop.first['rounds'];
      topRounds = r is num ? r.toInt() : 0;
    }
    final topStudents = _winnerTop
        .where((r) => (r['rounds'] is num ? (r['rounds'] as num).toInt() : 0) ==
            topRounds)
        .map((r) => (r['studentName'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toList();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                achieved ? Icons.emoji_events : Icons.flag_outlined,
                size: 46,
                color: achieved ? Colors.amber.shade700 : Colors.grey.shade500,
              ),
              const SizedBox(height: 12),
              Text(
                achieved ? "Target reached!" : "Competition closed",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colorProvider.secondColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name.isEmpty ? "Chanting Competition" : name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: colorProvider.secondColor.withOpacity(.75),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "$total / $target rounds together",
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00695C),
                ),
              ),
              const SizedBox(height: 16),
              if (topStudents.isNotEmpty) ...[
                Text(
                  topStudents.length == 1
                      ? "Top contributor"
                      : "Top contributors",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                    color: colorProvider.secondColor.withOpacity(.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "${topStudents.join(', ')} — $topRounds rounds",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _dismissWinner,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Continue"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
