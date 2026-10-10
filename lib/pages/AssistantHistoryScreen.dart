import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/Group2Widgets.dart';
import '../widgets/FolkChip.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/ScoreWidgets.dart';
import 'AssistantScreen.dart';

/// Date-based chat history — Stage 6, built 2026-08-24.
///
/// ---------------------------------------------------------------------------
/// Schema: extended, not rewritten
/// ---------------------------------------------------------------------------
/// `studentChats/{uid}/messages` is unchanged in shape and location (Rule 3).
/// Every message now additionally carries `sessionDate` (`dd-MM-yyyy`, IST,
/// stamped server-side in `functions/chat.js` via the project's existing
/// `todayDateId()`), added going forward at write time and backfilled once
/// onto the handful of pre-existing messages by deriving it from each
/// message's own real `createdAt` Timestamp — a lossless derivation, not a
/// guess, since every message already had a trustworthy server timestamp.
/// No new collection was needed (Rule 12 does not apply here).
///
/// ---------------------------------------------------------------------------
/// ⚠️ ASSUMPTION — flagged for product-owner confirmation, not silently
/// decided
/// ---------------------------------------------------------------------------
/// **Viewing a past day's chat is read-only.** [AssistantPastSessionPage]
/// carries no composer at all — a student cannot send into a past session.
/// Sending a new message is only ever possible from [AssistantScreen] itself,
/// which always targets **today's** session regardless of which past day was
/// most recently viewed (`handleStudentChat` stamps `sessionDate` from the
/// server's *current* date on every call — there is no way to direct a new
/// message at an old session even if this screen wanted to). This was the
/// task's own recommended default; implemented as specified, flagged as
/// requested rather than assumed without comment.
///
/// ---------------------------------------------------------------------------
/// Why one query grouped in Dart, not a session index collection
/// ---------------------------------------------------------------------------
/// A personal assistant transcript is small by construction — real production
/// data at the time this was built: 11 messages for one student, 4 for
/// another. One `.get()` over the whole subcollection, grouped and sorted in
/// Dart, is the same "single filter, Dart-side the rest" convention this
/// project already uses everywhere else, and building a separate per-session
/// index collection for a dataset this size would be complexity with no
/// payoff.
class AssistantHistoryListPage extends StatefulWidget {
  final String uid;

  const AssistantHistoryListPage({super.key, required this.uid});

  @override
  State<AssistantHistoryListPage> createState() =>
      _AssistantHistoryListPageState();
}

/// One day's worth of the transcript, summarised for the list row.
class _SessionSummary {
  final String sessionDate; // dd-MM-yyyy
  final DateTime sortKey; // parsed from sessionDate, for descending sort
  final int messageCount;
  final String preview;

  const _SessionSummary({
    required this.sessionDate,
    required this.sortKey,
    required this.messageCount,
    required this.preview,
  });
}

/// One day's daily encouragement message — follow-up task, 2026-09-10,
/// Part 2. Short by construction (<=50 words server-side), so it is shown
/// inline here rather than requiring a second navigation into a whole
/// session viewer built for multi-turn conversations.
class _DailyMessageSummary {
  final String sessionDate;
  final DateTime sortKey;
  final String text;

  const _DailyMessageSummary({
    required this.sessionDate,
    required this.sortKey,
    required this.text,
  });
}

class _AssistantHistoryListPageState extends State<AssistantHistoryListPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TabController _tabController;

  bool _loading = true;
  List<_SessionSummary> _sessions = [];
  List<_DailyMessageSummary> _dailyMessages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Follow-up task, 2026-09-10, Part 2 — two categories, read from the
  /// SAME query and the SAME additive `entryType` field
  /// (`dailyEncouragement.js` writes `entryType: 'daily_message'`; every
  /// message from before this task, and every ordinary conversational
  /// turn, has no `entryType` at all and reads as "conversation" — Rule
  /// 3, nothing existing is renamed or reinterpreted). A day with ONLY a
  /// daily message and no real conversation turn is excluded from the
  /// Conversations tab entirely, rather than showing an empty-looking
  /// "conversation".
  Future<void> _load() async {
    try {
      final snap = await _firestore
          .collection('studentChats')
          .doc(widget.uid)
          .collection('messages')
          .get();

      final byDate = <String, List<Map<String, dynamic>>>{};
      final dailyByDate = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final key = (data['sessionDate'] ?? '').toString();
        if (key.isEmpty) continue; // pre-Stage-6 message with no derivable key

        if (data['entryType'] == 'daily_message') {
          dailyByDate[key] = data;
        } else {
          (byDate[key] ??= []).add(data);
        }
      }

      final summaries = <_SessionSummary>[];
      byDate.forEach((sessionDate, messages) {
        messages.sort((a, b) {
          final ta = a['createdAt'];
          final tb = b['createdAt'];
          if (ta is! Timestamp) return -1;
          if (tb is! Timestamp) return 1;
          return ta.compareTo(tb);
        });

        // First student message reads as a better preview than the first
        // assistant reply, which is often generic ("I hear you...").
        final firstStudentMsg = messages.firstWhere(
          (m) => m['role'] == 'student',
          orElse: () => messages.first,
        );
        final preview = (firstStudentMsg['text'] ?? '').toString();

        final parsed = _parseSessionDate(sessionDate);

        summaries.add(_SessionSummary(
          sessionDate: sessionDate,
          sortKey: parsed ?? DateTime(2000),
          messageCount: messages.length,
          preview: preview.length > 80
              ? '${preview.substring(0, 80)}…'
              : preview,
        ));
      });

      summaries.sort((a, b) => b.sortKey.compareTo(a.sortKey));

      final dailyMessages = <_DailyMessageSummary>[];
      dailyByDate.forEach((sessionDate, data) {
        final parsed = _parseSessionDate(sessionDate);
        dailyMessages.add(_DailyMessageSummary(
          sessionDate: sessionDate,
          sortKey: parsed ?? DateTime(2000),
          text: (data['text'] ?? '').toString(),
        ));
      });
      dailyMessages.sort((a, b) => b.sortKey.compareTo(a.sortKey));

      if (!mounted) return;
      setState(() {
        _sessions = summaries;
        _dailyMessages = dailyMessages;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static DateTime? _parseSessionDate(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  String _label(_SessionSummary s) {
    final today = todaySessionKey();
    if (s.sessionDate == today) return "Today";
    return DateFormat('EEEE, dd MMM yyyy').format(s.sortKey);
  }

  String _dailyLabel(_DailyMessageSummary d) {
    final today = todaySessionKey();
    if (d.sessionDate == today) return "Today";
    return DateFormat('EEEE, dd MMM yyyy').format(d.sortKey);
  }

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: "History",
      // Follow-up task, 2026-09-10, Part 2 — two categories, filterable via
      // tabs rather than mixed into one list. The two tabs are chips that
      // drive the same TabController the swipeable TabBarView uses.
      bottom: Padding(
        padding: const EdgeInsets.only(top: FolkSpace.lg),
        child: AnimatedBuilder(
          animation: _tabController.animation!,
          builder: (context, _) {
            final selectedIndex = _tabController.animation!.value.round();
            const labels = ["Conversations", "Daily messages"];
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: FolkSpace.pagePadding),
              child: Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                          right: i == labels.length - 1 ? 0 : FolkSpace.sm),
                      child: FolkChip(
                        label: labels[i],
                        selected: i == selectedIndex,
                        large: true,
                        onTap: () => _tabController.animateTo(i),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      body: _loading
          ? const LeaderboardGhost(rows: 4)
          : TabBarView(
              controller: _tabController,
              children: [
                _conversationsTab(),
                _dailyMessagesTab(),
              ],
            ),
    );
  }

  Widget _conversationsTab() {
    final text = context.folkText;
    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text("No conversations yet.", style: text.small),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg,
          FolkSpace.pagePadding, 28),
      itemCount: _sessions.length,
      itemBuilder: (context, i) {
        final s = _sessions[i];
        return EntryAnimation(
          index: i,
          child: HistorySessionTile(
            label: _label(s),
            subtitle: s.preview.isEmpty
                ? "${s.messageCount} message${s.messageCount == 1 ? '' : 's'}"
                : s.preview,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssistantPastSessionPage(
                  uid: widget.uid,
                  sessionDate: s.sessionDate,
                  dateLabel: _label(s),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Each daily message is shown inline, in full — short by construction
  /// (<=50 words, server-enforced in `dailyEncouragement.js`), so a second
  /// navigation into a sub-page would be friction for no benefit. Read-only,
  /// same as the Conversations tab's own past-session viewer (Part 2 item
  /// 4 — nothing here ever writes to a student's own messages).
  Widget _dailyMessagesTab() {
    final text = context.folkText;
    if (_dailyMessages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text("No daily messages yet.", style: text.small),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg,
          FolkSpace.pagePadding, 28),
      itemCount: _dailyMessages.length,
      itemBuilder: (context, i) {
        final d = _dailyMessages[i];
        return EntryAnimation(
          index: i,
          child: DailyHistoryCard(label: _dailyLabel(d), text: d.text),
        );
      },
    );
  }
}

/// Read-only view of one past day's conversation. No composer — see this
/// file's header for why that is a deliberate, flagged default rather than an
/// oversight.
class AssistantPastSessionPage extends StatefulWidget {
  final String uid;
  final String sessionDate;
  final String dateLabel;

  const AssistantPastSessionPage({
    super.key,
    required this.uid,
    required this.sessionDate,
    required this.dateLabel,
  });

  @override
  State<AssistantPastSessionPage> createState() =>
      _AssistantPastSessionPageState();
}

class _AssistantPastSessionPageState extends State<AssistantPastSessionPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _loading = true;
  final List<ChatTurn> _turns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _firestore
          .collection('studentChats')
          .doc(widget.uid)
          .collection('messages')
          .where('sessionDate', isEqualTo: widget.sessionDate)
          .get();

      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          if (ta is! Timestamp) return -1;
          if (tb is! Timestamp) return 1;
          return ta.compareTo(tb);
        });

      _turns.addAll(docs.map((d) {
        final data = d.data();
        return ChatTurn(
          (data['text'] ?? '').toString(),
          fromStudent: data['role'] == 'student',
        );
      }));
    } catch (_) {
      // Falls through to an empty read-only view rather than crashing.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkScaffold(
      title: widget.dateLabel,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: colors.surfaceSecondary,
            padding: const EdgeInsets.symmetric(
                horizontal: FolkSpace.pagePadding, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.visibility_off_outlined,
                        size: 14, color: colors.mutedText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Viewing a past conversation — read only.",
                        style: text.caption,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                          FolkShape.touchTarget, FolkShape.touchTarget),
                      foregroundColor: colors.text,
                      textStyle: text.chip.copyWith(fontSize: 12),
                    ),
                    // Pops every screen this history browse pushed —
                    // list, then this viewer — straight back to today's
                    // live chat, however many were opened along the way.
                    onPressed: () => Navigator.of(context)
                        .popUntil(ModalRoute.withName(kAssistantRouteName)),
                    child: const Text("Go to today's chat"),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LeaderboardGhost(rows: 4)
                : _turns.isEmpty
                    ? Center(
                        child: Text(
                          "No messages found for this day.",
                          style: text.small,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            FolkSpace.pagePadding, 16, FolkSpace.pagePadding, 24),
                        itemCount: _turns.length,
                        itemBuilder: (context, i) =>
                            chatBubble(context, _turns[i]),
                      ),
          ),
        ],
      ),
    );
  }
}
