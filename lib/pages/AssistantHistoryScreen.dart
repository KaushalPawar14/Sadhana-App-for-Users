import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/Group2Widgets.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/ScoreWidgets.dart';
import 'AssistantScreen.dart';

/// One merged history of the assistant: one list, one entry per day.
///
/// Before 2026-10-19 this screen had two tabs ("Conversations" and "Daily messages"). A day is now ONE
/// entry: opening it shows ONE thread, today's message first and then that day's whole chat exactly as
/// it looked while chatting.
///
/// ---------------------------------------------------------------------------
/// Schema: extended, not rewritten
/// ---------------------------------------------------------------------------
/// `studentChats/{uid}/messages` is unchanged in shape and location. Every message carries
/// `sessionDate` (`dd-MM-yyyy`, IST, stamped server-side in `functions/chat.js`), and the daily message
/// carries `entryType: 'daily_message'`.
///
/// The one addition is `studentChats/{uid}/sessions/{dd-MM-yyyy}`: one small document per day, written
/// ONLY by the server (`functions/chatSession.js`), read only by its owner (rules). It holds the day's
/// AI title (e.g. "12 Oct · 7-day streak, keep going") and the day's question count. It sits under the
/// student's own chat data, so the existing delete-a-student cascade removes it too. A day with no
/// title (older days before the one-time backfill, or a title the server could not write) simply shows
/// its date.
///
/// ---------------------------------------------------------------------------
/// Past days are read-only
/// ---------------------------------------------------------------------------
/// [AssistantPastSessionPage] carries no composer; a student can only send from [AssistantScreen],
/// which always targets TODAY (the server stamps `sessionDate` itself). Today's entry in the list
/// takes the student back to the live chat instead of opening a read-only copy.
///
/// One `.get()` over the (small) subcollections, grouped in Dart: the same "single filter, the rest
/// in Dart" convention used everywhere else in this project.
class AssistantHistoryListPage extends StatefulWidget {
  final String uid;

  // Test seam: the app never sets this.
  final FirebaseFirestore? firestore;

  const AssistantHistoryListPage({super.key, required this.uid, this.firestore});

  @override
  State<AssistantHistoryListPage> createState() =>
      _AssistantHistoryListPageState();
}

/// One day, summarised for its list row.
class _DaySummary {
  final String sessionDate; // dd-MM-yyyy
  final DateTime sortKey; // parsed from sessionDate, for descending sort
  final String title; // the AI title, or '' when the day has none yet
  final int messageCount;
  final String preview;

  const _DaySummary({
    required this.sessionDate,
    required this.sortKey,
    required this.title,
    required this.messageCount,
    required this.preview,
  });
}

DateTime? _parseSessionDate(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  return DateTime(y, m, d);
}

String _dayLabel(String sessionDate) {
  if (sessionDate == todaySessionKey()) return "Today";
  final parsed = _parseSessionDate(sessionDate);
  return parsed == null ? sessionDate : DateFormat('EEEE, dd MMM yyyy').format(parsed);
}

int _byTime(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ta = a['createdAt'];
  final tb = b['createdAt'];
  if (ta is! Timestamp) return -1;
  if (tb is! Timestamp) return 1;
  return ta.compareTo(tb);
}

/// Today's message first, then the chat in the order it happened.
void _dailyMessageFirst(List<Map<String, dynamic>> messages) {
  messages.sort((a, b) {
    final da = a['entryType'] == 'daily_message';
    final db = b['entryType'] == 'daily_message';
    if (da != db) return da ? -1 : 1;
    return _byTime(a, b);
  });
}

class _AssistantHistoryListPageState extends State<AssistantHistoryListPage> {
  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;

  bool _loading = true;
  bool _failed = false;
  List<_DaySummary> _days = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final chat = _firestore.collection('studentChats').doc(widget.uid);
      final messagesSnap = await chat.collection('messages').get();

      // A day's title lives on its session document. Missing or unreadable is fine: the day just
      // shows its date.
      final titles = <String, String>{};
      try {
        final sessionsSnap = await chat.collection('sessions').get();
        for (final doc in sessionsSnap.docs) {
          final t = (doc.data()['title'] ?? '').toString().trim();
          if (t.isNotEmpty) titles[doc.id] = t;
        }
      } catch (_) {}

      final byDate = <String, List<Map<String, dynamic>>>{};
      for (final doc in messagesSnap.docs) {
        final data = doc.data();
        final key = (data['sessionDate'] ?? '').toString();
        if (key.isEmpty) continue; // an old message with no derivable day
        (byDate[key] ??= []).add(data);
      }

      final days = <_DaySummary>[];
      byDate.forEach((sessionDate, messages) {
        _dailyMessageFirst(messages);
        // The first thing the student asked reads better than a generic reply; a day with only
        // today's message previews that message.
        final first = messages.firstWhere(
          (m) => m['role'] == 'student' && m['entryType'] != 'daily_message',
          orElse: () => messages.first,
        );
        final preview = (first['text'] ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        days.add(_DaySummary(
          sessionDate: sessionDate,
          sortKey: _parseSessionDate(sessionDate) ?? DateTime(2000),
          title: titles[sessionDate] ?? '',
          messageCount: messages.length,
          preview: preview.length > 80 ? '${preview.substring(0, 80)}…' : preview,
        ));
      });
      days.sort((a, b) => b.sortKey.compareTo(a.sortKey));

      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _open(_DaySummary d) {
    if (d.sessionDate == todaySessionKey()) {
      // Today is the live chat: back to it, whatever was opened along the way.
      Navigator.of(context).popUntil(ModalRoute.withName(kAssistantRouteName));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssistantPastSessionPage(
          uid: widget.uid,
          sessionDate: d.sessionDate,
          dateLabel: _dayLabel(d.sessionDate),
          title: d.title,
          firestore: widget.firestore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: "History",
      body: _loading
          ? const LeaderboardGhost(rows: 4)
          : _failed
              ? FolkErrorRetry(
                  message: "Couldn't load your history just now.",
                  onRetry: _load,
                )
              : _list(),
    );
  }

  Widget _list() {
    final text = context.folkText;
    if (_days.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text("No conversations yet.", style: text.small),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding, 28),
      itemCount: _days.length,
      itemBuilder: (context, i) {
        final d = _days[i];
        final hasTitle = d.title.isNotEmpty;
        return EntryAnimation(
          index: i,
          child: HistorySessionTile(
            label: hasTitle ? d.title : _dayLabel(d.sessionDate),
            subtitle: d.preview.isEmpty
                ? "${d.messageCount} message${d.messageCount == 1 ? '' : 's'}"
                : d.preview,
            onTap: () => _open(d),
          ),
        );
      },
    );
  }
}

/// Read-only view of one past day: today's message first, then that day's whole chat, exactly as it
/// looked while chatting. No composer; "Go to today's chat" goes back to the live chat.
class AssistantPastSessionPage extends StatefulWidget {
  final String uid;
  final String sessionDate;
  final String dateLabel;

  /// The day's AI title, when it has one.
  final String title;

  // Test seam: the app never sets this.
  final FirebaseFirestore? firestore;

  const AssistantPastSessionPage({
    super.key,
    required this.uid,
    required this.sessionDate,
    required this.dateLabel,
    this.title = '',
    this.firestore,
  });

  @override
  State<AssistantPastSessionPage> createState() =>
      _AssistantPastSessionPageState();
}

class _AssistantPastSessionPageState extends State<AssistantPastSessionPage> {
  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;
  bool _loading = true;
  bool _failed = false;
  final List<ChatTurn> _turns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final snap = await _firestore
          .collection('studentChats')
          .doc(widget.uid)
          .collection('messages')
          .where('sessionDate', isEqualTo: widget.sessionDate)
          .get();

      final messages = snap.docs.map((d) => d.data()).toList();
      _dailyMessageFirst(messages);

      _turns
        ..clear()
        ..addAll(messages.map((data) => ChatTurn(
              (data['text'] ?? '').toString(),
              fromStudent: data['role'] == 'student',
              isDailyMessage: data['entryType'] == 'daily_message',
              category: (data['category'] ?? '').toString(),
            )));
    } catch (_) {
      _failed = true;
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
                if (widget.title.isNotEmpty) ...[
                  Text(widget.title, style: text.bodyStrong),
                  const SizedBox(height: 4),
                ],
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
                    // Pops every screen this history browse pushed (list, then this viewer)
                    // straight back to today's live chat.
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
                : _failed
                    ? FolkErrorRetry(
                        message: "Couldn't load this day just now.",
                        onRetry: _load,
                      )
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
