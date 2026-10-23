import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ChallengeRange.dart';
import '../utils/SameGender.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/FolkErrorRetry.dart';
import 'package:intl/intl.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/Group2Widgets.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';

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
///
/// Now the FIRST SECTION of "My Competitions" (`MyCompetitionsPage.dart`): the
/// same widget, logic, streams, 6-second winner timer and `summarySeenBy` write
/// the old Chanting Competition page had, drawn without its own scaffold or
/// scrolling, so the page can scroll as one.
class ChantingCompetitionSection extends StatefulWidget {
  const ChantingCompetitionSection({super.key});

  @override
  State<ChantingCompetitionSection> createState() =>
      _ChantingCompetitionSectionState();
}

class _ChantingCompetitionSectionState
    extends State<ChantingCompetitionSection> {
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
      // Only contributions of my own gender (documents carry a server-stamped
      // `gender`): a query the security rules can prove, and the same
      // separation the screen already applied on screen.
      var contributions = _firestore
          .collection('chantingChallengeContributions')
          .where('challengeId', isEqualTo: challengeId);
      final mine = _directory?.mine;
      if (mine != null) contributions = contributions.where('gender', isEqualTo: mine);
      _contributionsStream = contributions.snapshots();
    }
    return _contributionsStream!;
  }

  /// The challenge currently being shown in the Active state, or null when
  /// idle. Includes 'id' merged into the map alongside the doc's fields.
  Map<String, dynamic>? _trackedChallenge;

  /// Who is of my gender: only those students are listed as contributors or
  /// winners. Null until read (nothing is listed before then).
  GenderDirectory? _directory;

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

    try {
      _directory = await GenderDirectory.forCurrentUser();
    } catch (_) {
      // Without it no other student is listed: the screen fails closed.
    }

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
      final directory = await GenderDirectory.forCurrentUser();
      final snap = await _firestore
          .collection('chantingChallengeContributions')
          .where('challengeId', isEqualTo: ended['id'])
          .where('gender', isEqualTo: directory.mine)
          .get();

      top = snap.docs
          .map((d) => d.data())
          .where((d) => directory.sameByName(d['studentName']?.toString()))
          .toList()
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
    // A result with a day-by-day table is something to read, not glance at, so
    // it waits for the student to press Continue. A single day keeps the
    // six-second card it always had.
    final span = ChallengeSpan.of(ended);
    if (span == null || !span.isRange) {
      _winnerTimer = Timer(const Duration(seconds: 6), _dismissWinner);
    }
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
    return _loadingGuide
        ? const GhostScope(
            child: Padding(
              padding: EdgeInsets.all(FolkSpace.pagePadding),
              child: Column(
                children: [
                  GhostPlaceholder(
                      width: double.infinity, height: 170, showBars: false),
                  SizedBox(height: FolkSpace.cardGap),
                  GhostPlaceholder(
                      width: double.infinity,
                      height: 64,
                      radius: FolkShape.tileRadius,
                      showBars: false),
                ],
              ),
            ),
          )
        : _showWinner
            ? _winnerCard()
            : (_trackedChallenge == null
                ? _idleState()
                : _activeState(_trackedChallenge!));
  }

  Widget _idleState() {
    final colors = context.folk;
    final text = context.folkText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.self_improvement, size: 56, color: colors.mutedText),
            const SizedBox(height: 18),
            Text("No competition right now", style: text.bodyStrong),
            const SizedBox(height: 10),
            Text(
              "Your guide hasn't started a chanting competition yet. "
              "When one begins, it will show up here automatically — "
              "no need to check back constantly.",
              textAlign: TextAlign.center,
              style: text.small.copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeState(Map<String, dynamic> challenge) {
    final text = context.folkText;
    final name = (challenge['name'] ?? '').toString();
    final target = challenge['targetRounds'] is num
        ? (challenge['targetRounds'] as num).toInt()
        : 0;
    final total = challenge['currentTotal'] is num
        ? (challenge['currentTotal'] as num).toInt()
        : 0;
    final ts = challenge['targetDate'];
    // A range reads "15 Oct – 20 Oct 2026"; a single day, or a competition
    // from before ranges, its one date exactly as before.
    final span = ChallengeSpan.of(challenge);
    final dateText = span != null
        ? span.label
        : ts is Timestamp
            ? DateFormat('dd MMM yyyy').format(ts.toDate())
            : '';
    final collectiveFraction =
        target <= 0 ? 0.0 : (total / target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg,
          FolkSpace.pagePadding, 0),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChallengeSummaryCard(
          name: name,
          dateText: dateText,
          total: total,
          target: target,
          fraction: collectiveFraction,
        ),
        const SizedBox(height: 20),
        Text("Who's contributing", style: text.bodyStrong),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: _contributionsStreamFor(challenge['id'] as String),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return FolkErrorRetry(
                compact: true,
                message: "Couldn't load the contributions just now.",
                onRetry: () => setState(() {
                  // Forgetting the cached stream makes the next build open it again.
                  _contributionsStreamChallengeId = null;
                }),
              );
            }
            if (!snapshot.hasData) {
              return const GhostScope(
                child: Column(
                  children: [
                    GhostPlaceholder(
                        width: double.infinity,
                        height: 64,
                        radius: FolkShape.tileRadius,
                        showBars: false),
                    SizedBox(height: 10),
                    GhostPlaceholder(
                        width: double.infinity,
                        height: 64,
                        radius: FolkShape.tileRadius,
                        showBars: false),
                  ],
                ),
              );
            }

            final rows = snapshot.data!.docs.where((d) {
              // Only students of my gender are listed.
              final data = d.data() as Map<String, dynamic>;
              return _directory?.sameByName(data['studentName']?.toString()) ??
                  false;
            }).map((d) {
              final data = d.data() as Map<String, dynamic>;
              final rounds =
                  data['rounds'] is num ? (data['rounds'] as num).toInt() : 0;
              return {
                'name': (data['studentName'] ?? '').toString(),
                'rounds': rounds,
                // For the day-by-day table; a row from before ranges has none.
                'byDay': data['byDay'],
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
                  style: text.small,
                ),
              );
            }

            final span = ChallengeSpan.of(challenge);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows.map((r) => _leaderboardRow(
                      r['name'] as String,
                      r['rounds'] as int,
                      target,
                    )),
                if (span != null && span.isRange) ...[
                  const SizedBox(height: 10),
                  ChallengeDayTable(
                    days: buildDayTable(
                      span,
                      rows.map((r) => {
                            'studentName': r['name'],
                            'rounds': r['rounds'],
                            'byDay': r['byDay'],
                          }),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
    );
  }

  Widget _leaderboardRow(String name, int rounds, int target) {
    final fraction = target <= 0 ? 0.0 : (rounds / target).clamp(0.0, 1.0);

    return ContributionRow(name: name, rounds: rounds, fraction: fraction);
  }

  Widget _winnerCard() {
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

    final span = ChallengeSpan.of(challenge);
    final card = ChallengeResultCard(
      achieved: achieved,
      name: name,
      total: total,
      target: target,
      topStudents: topStudents,
      topRounds: topRounds,
      action: PrimaryButton(label: "Continue", onPressed: _dismissWinner),
    );

    // A competition over several days shows the total ranking above (the
    // top contributors) AND who chanted how much on which day.
    if (span != null && span.isRange && _winnerTop.isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            card,
            const SizedBox(height: 16),
            ChallengeDayTable(days: buildDayTable(span, _winnerTop)),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: card,
      ),
    );
  }
}
