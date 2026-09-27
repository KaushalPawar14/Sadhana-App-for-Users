import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import 'AssistantHistoryScreen.dart';

/// The named route used when this screen is opened from the floating
/// assistant button. Past-session views (Stage 6) pop back to this exact
/// route rather than just once, regardless of how many screens deep a
/// student has browsed into their history.
const String kAssistantRouteName = '/assistant';

/// `dd-MM-yyyy` in the student's local time, matching the doc-id convention
/// every date-keyed collection in this project already uses.
String todaySessionKey() => DateFormat('dd-MM-yyyy').format(DateTime.now());

/// The student assistant (Phase 7).
///
/// Answers are produced by the `studentChat` callable, which grounds
/// philosophical replies in Śrīla Prabhupāda's own books, letters and talks.
///
/// ⚠️ **Streaming (Stage C, 2026-08-27).** `functions/chat.js` writes the
/// reply to Firestore incrementally as it generates (Stage B). This screen
/// pre-mints the reply document's id, hands it to the callable, and listens
/// to that document with `.snapshots()` instead of waiting on the callable's
/// own return value for the text — see `_send()`. The callable is still
/// awaited, but only to detect a failure that happened *before* anything was
/// ever saved; once the reply document exists at all, the listener is the
/// source of truth for what the student sees, because `chat.js` finalizes
/// that same document with a graceful fallback message even when generation
/// fails outright (its own comment: "a student... should not be left
/// thinking it vanished").
///
/// **The student is never told a message was flagged.** The backend returns
/// `flagged` and `acuteRisk`, and this screen deliberately ignores both. A
/// student who learns that certain words alert their guide will start
/// choosing safer words — which would defeat the point of noticing distress
/// at all. Flagging is a guide-side concern; the disclosure below is how the
/// student is told the truth, once, up front.
///
/// The "Prabhupada content feed" from the handoff is folded in here as
/// starter questions rather than built as a separate browse screen: it is the
/// same retrieval, and the handoff defines no content structure to browse by.
class AssistantScreen extends StatefulWidget {
  final String uid;

  const AssistantScreen({super.key, required this.uid});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

/// A single turn on screen. Not persisted here — the backend owns the
/// transcript; this is only what the student is currently looking at.
///
/// Public (Stage 6, 2026-08-24) so `AssistantHistoryScreen.dart`'s read-only
/// past-session viewer can reuse it and [chatBubble] instead of duplicating
/// the turn model and bubble styling.
class ChatTurn {
  final String text;
  final bool fromStudent;

  /// Follow-up task, 2026-09-10, Part 2 — purely additive: defaults to
  /// `false` so every existing call site (and every message written before
  /// this task) reads as an ordinary conversation turn, unchanged.
  final bool isDailyMessage;

  const ChatTurn(this.text, {required this.fromStudent, this.isDailyMessage = false});
}

/// The message bubble, shared between the live chat and the read-only past-
/// session viewer so the two never visually diverge.
Widget chatBubble(BuildContext context, ChatTurn turn) {
  final mine = turn.fromStudent;

  return Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Follow-up task, 2026-09-10, Part 2 — a small caption so a student
        // recognises this as their daily message, not a reply to something
        // they asked.
        if (turn.isDailyMessage)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wb_sunny_outlined,
                    size: 12, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Text(
                  "Today's message",
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        _chatBubbleContent(context, turn, mine),
      ],
    ),
  );
}

Widget _chatBubbleContent(BuildContext context, ChatTurn turn, bool mine) {
  return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.82,
      ),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: mine ? Colors.blue.shade600 : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        border: mine ? null : Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        turn.text,
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: mine ? Colors.white : Colors.black87,
        ),
      ),
  );
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const List<String> _starters = [
    "What does Prabhupada say about the soul and the body?",
    "Why is chanting Hare Krishna so important?",
    "How do I stay steady in my practice during exams?",
    "What is the purpose of human life?",
  ];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<ChatTurn> _turns = [];

  bool _loadingHistory = true;
  bool _sending = false;

  /// Issue 3 fix (2026-09-16) — true only while `generateDailyEncouragement`
  /// is actually in flight, so the screen can show a real waiting state
  /// instead of looking idle for the several seconds that call can take.
  bool _preparingDailyMessage = false;

  /// Set only on a GENUINE failure of that call (network error, function
  /// error, or timeout) — never for the normal, non-error case where
  /// today's message already existed (`isNew == false`). Cleared
  /// automatically a few seconds after being shown; never blocks ordinary
  /// use of the assistant underneath it.
  String? _dailyMessageError;

  /// The live streaming listener on the current reply-in-progress, and its
  /// give-up timer. Null whenever no send is in flight.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _replySub;
  Timer? _streamTimeout;

  /// Whether the listener has ever observed the reply document existing at
  /// all, for THIS send. Distinguishes the two failure modes in `_send()`'s
  /// catch block — see there.
  bool _replyDocSeen = false;

  /// How long to wait for `streaming: false` before giving up on this turn.
  ///
  /// Every real duration Stage B measured against production infrastructure
  /// was 4.4s-53.1s (the 53.1s case was itself a since-fixed bug; the fixed
  /// figure was 11.4s). 90s leaves generous margin above the worst real
  /// number observed, rather than a round guess.
  static const Duration _kStreamTimeout = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _replySub?.cancel();
    _streamTimeout?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Loads any earlier conversation, then shows the disclosure if this student
  /// has never acknowledged it.
  ///
  /// Follow-up task, 2026-09-10, Part 1 items 1/2 — after the disclosure
  /// (never before it: a message a student has not yet consented to a
  /// guide-visible transcript must not be generated), this also ensures
  /// today's daily encouragement message exists, generating it on this
  /// first open of the day if needed. If a NEW message was written,
  /// history is reloaded once so it appears — cheap (this transcript is
  /// small by construction, per `AssistantHistoryScreen.dart`'s own
  /// header) and avoids a second, parallel way of adding a turn to
  /// `_turns`.
  ///
  /// Bug fix, 2026-09-16 (Issue 3, real-device report) — two things were
  /// wrong here, both fixed together since they're the same underlying
  /// ordering mistake:
  ///  1. `SeenMarkers.markSeen` used to run BEFORE generation even started
  ///     — the dot cleared the instant the screen opened, not when the
  ///     student actually saw the message. If they closed the app during
  ///     the several-second generation, the dot was already gone with
  ///     nothing telling them to come back and look. It now runs only
  ///     after the message has been loaded into `_turns` (or generation
  ///     has definitively failed) — see the bottom of this method.
  ///  2. Generation ran with no visible indication at all — the starter
  ///     view or existing message list just sat there, looking idle, for
  ///     however long the call took. `_preparingDailyMessage` now drives a
  ///     banner (`_dailyMessageStatusBanner()`) for that whole window.
  Future<void> _bootstrap() async {
    await _loadHistory();

    if (!mounted) return;
    setState(() => _loadingHistory = false);

    final acceptedDisclosure = await _ensureDisclosureAcknowledged();
    if (!acceptedDisclosure || !mounted) return;

    setState(() => _preparingDailyMessage = true);

    final result = await _ensureDailyEncouragement();
    if (!mounted) return;

    if (result.isNew) {
      await _loadHistory();
      if (!mounted) return;
    }

    // Only now — after the message has actually been loaded and would be
    // showing on screen, or generation has definitively failed/timed out
    // — is "seen" recorded. See this method's own header for why this
    // moved from the top of `_bootstrap`.
    SeenMarkers.markSeen(widget.uid, 'dailyEncouragement');

    setState(() {
      _preparingDailyMessage = false;
      _dailyMessageError = result.failed
          ? "Could not prepare today's message. It will be ready next time "
              "you open this."
          : null;
    });

    if (result.failed) {
      // Transient — auto-clears; never blocks ordinary use of the
      // assistant underneath it (matching this method's own long-standing
      // "a failure here must never block ordinary use" rule).
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _dailyMessageError = null);
      });
    }
  }

  /// Calls the (idempotent — at most one OpenAI call per student per day,
  /// server-side) `generateDailyEncouragement` callable.
  ///
  /// `isNew` distinguishes "a message was just generated" from "today's
  /// message already existed" (the normal case on a second open the same
  /// day) — both are non-error outcomes. `failed` is set ONLY for a genuine
  /// failure (network error, function error, or a timeout — an explicit
  /// 45s client-side deadline, since this is a single-shot generation call
  /// like `studentChat`'s own, which Stage B measured at 4.4s-53.1s in
  /// practice; unlike that screen's own conversational reply, this is not
  /// worth a 90s wait before telling the student something went wrong). A
  /// failure never throws past this function — `_bootstrap` above turns it
  /// into a plain, readable, auto-clearing message instead of an indefinite
  /// spinner.
  Future<({bool isNew, bool failed})> _ensureDailyEncouragement() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable(
        'generateDailyEncouragement',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      final result = await callable.call<Map<String, dynamic>>();
      return (isNew: result.data['isNew'] == true, failed: false);
    } catch (_) {
      return (isNew: false, failed: true);
    }
  }

  Future<void> _loadHistory() async {
    try {
      // Stage 6 (2026-08-24): scoped to TODAY's session only, via the
      // `sessionDate` field `functions/chat.js` now stamps on every message
      // (server-side, IST). This used to be an unbounded `.get()` over the
      // WHOLE lifetime transcript on every open — harmless for a handful of
      // messages, but unbounded growth for a heavy user over months. Past
      // sessions are reached through History (`AssistantHistoryScreen.dart`),
      // not loaded here.
      //
      // One equality filter, sorted in Dart — matching this project's
      // convention of avoiding composite indexes.
      final snap = await _firestore
          .collection('studentChats')
          .doc(widget.uid)
          .collection('messages')
          .where('sessionDate', isEqualTo: todaySessionKey())
          .get();

      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          if (ta is! Timestamp) return -1;
          if (tb is! Timestamp) return 1;
          return ta.compareTo(tb);
        });

      _turns
        ..clear()
        ..addAll(docs.map((d) {
          final data = d.data();
          return ChatTurn(
            (data['text'] ?? '').toString(),
            fromStudent: data['role'] == 'student',
            isDailyMessage: data['entryType'] == 'daily_message',
          );
        }));
    } catch (_) {
      // An unreadable history must not block a new conversation.
    }
  }

  // ---------------------------------------------------------------------------
  // One-time disclosure
  // ---------------------------------------------------------------------------

  /// Shows the disclosure exactly once per student, ever.
  ///
  /// The flag lives on `users/{uid}.acknowledgedDisclosure`, so it survives
  /// reinstalls and follows the student across devices — a local preference
  /// would show it again on a new phone.
  ///
  /// If the flag cannot be read, the disclosure is shown. Telling a student
  /// twice is a small annoyance; never telling them is a broken promise.
  ///
  /// Returns whether the student may proceed (already acknowledged, or just
  /// accepted) — follow-up task, 2026-09-10: `_bootstrap` uses this to
  /// decide whether generating today's daily message is appropriate yet
  /// (never before this consent, since that message lands in the same
  /// guide-visible transcript this dialog discloses).
  Future<bool> _ensureDisclosureAcknowledged() async {
    bool acknowledged = false;

    try {
      final snap =
          await _firestore.collection('users').doc(widget.uid).get();
      acknowledged = snap.data()?['acknowledgedDisclosure'] == true;
    } catch (_) {
      acknowledged = false;
    }

    if (acknowledged) return true;
    if (!mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("How this works"),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Ask freely — this is here to help you.",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 10),
              Text(
                "Questions about Krishna consciousness and the teachings, "
                "about your daily practice, or about how this app works — "
                "all of it is welcome, and no question is too small.",
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              SizedBox(height: 12),
              Text(
                "Your guide can see these conversations. Not to check up on "
                "you — it is one of the ways they stay close to how you are "
                "doing, the same way they see your sadhana reports.",
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              SizedBox(height: 12),
              Text(
                "And if you ever write something that suggests you are "
                "going through a hard time, your guide is gently let know, "
                "so they can be there for you.",
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              SizedBox(height: 12),
              Text(
                "This assistant is not a replacement for real people. When "
                "something weighs on you, your guide is the one to talk to.",
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Go back"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("I understand"),
          ),
        ],
      ),
    );

    if (!mounted) return false;

    if (accepted != true) {
      // Declining means leaving — the student cannot use the assistant
      // without knowing their guide can read it.
      Navigator.pop(context);
      return false;
    }

    try {
      await _firestore.collection('users').doc(widget.uid).set(
        {'acknowledgedDisclosure': true},
        SetOptions(merge: true),
      );
    } catch (_) {
      // If the write fails the dialog reappears next time. Acceptable: the
      // student has still been told, and being told twice is harmless.
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    // Client-mints the reply doc id — the standard Firestore idiom
    // (`.doc()` with no argument), already used server-side throughout this
    // project (`chat.js`, `goals.js`, `BoardQueries.dart`) but not previously
    // used from either Flutter app; checked for a client-side precedent
    // before adding one and found none. Handing this id to the callable is
    // what lets `chat.js` write to a document this screen is already
    // listening to, instead of one it only learns about after the fact.
    final replyRef = _firestore
        .collection('studentChats')
        .doc(widget.uid)
        .collection('messages')
        .doc();

    setState(() {
      _turns.add(ChatTurn(text, fromStudent: true));
      // Placeholder for the streaming reply. Updated IN PLACE (by index, see
      // `_listenForStreamedReply`) as chunks arrive — never appended to again
      // for this turn.
      _turns.add(const ChatTurn('', fromStudent: false));
      _sending = true;
      _input.clear();
    });
    _scrollToEnd();

    _listenForStreamedReply(replyRef);

    try {
      // The function lives in asia-south1, not the default region.
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('studentChat');

      await callable.call<Map<String, dynamic>>({
        'message': text,
        'replyDocId': replyRef.id,
      });

      // `flagged`, `acuteRisk` and the final `reply` text all come back in
      // the payload but are intentionally not read here — see the class
      // comment on why `flagged`/`acuteRisk` are ignored, and the streaming
      // note above on why the listener, not this return value, is the source
      // of truth for the text. A successful call needs no further action:
      // the listener already finalized the bubble the moment it saw
      // `streaming: false`, which happens before this await resolves.
    } catch (e) {
      if (!mounted) return;

      // Distinguishes two real failure modes, per `chat.js`'s actual
      // behaviour (Stage B): if the reply document was NEVER seen at all,
      // nothing was saved server-side (the failure was before intake —  no
      // network, not signed in, etc.) and the old recovery applies. If it
      // WAS seen — even mid-stream, even just chat.js's own graceful
      // fallback text — the student's message and some reply are already
      // durably saved; stripping the turn here would contradict chat.js's
      // own stated intent that a student "should not be left thinking it
      // vanished".
      final docWasSeen = _replyDocSeen;
      _finishStreaming();

      setState(() {
        if (!docWasSeen) {
          _turns.removeLast(); // the empty reply placeholder
          _turns.removeLast(); // the student's own turn
          _input.text = text; // put their words back, nothing was lost
        }
        _sending = false;
      });

      if (!docWasSeen) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FirebaseFunctionsException && e.message != null ?
                  e.message! :
                  "Could not send. Check your connection and try again.",
            ),
          ),
        );
      }
    }

    _scrollToEnd();
  }

  /// Listens to the reply document as `chat.js` streams into it, updating
  /// the placeholder bubble in place. Stops on `streaming: false`, on a
  /// listener error, or on `_kStreamTimeout` — whichever comes first — so the
  /// UI can never hang open-ended waiting for a completion signal that never
  /// arrives (item 2e: a network drop or a function timeout on the server
  /// must not leave the bubble stuck mid-stream forever).
  void _listenForStreamedReply(
    DocumentReference<Map<String, dynamic>> replyRef,
  ) {
    _replyDocSeen = false;
    _replySub?.cancel();
    _streamTimeout?.cancel();

    _streamTimeout = Timer(_kStreamTimeout, _finishStreaming);

    _replySub = replyRef.snapshots().listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;
      _replyDocSeen = true;

      final text = (data['text'] ?? '').toString();
      final streaming = data['streaming'] == true;

      setState(() {
        if (_turns.isNotEmpty && !_turns.last.fromStudent) {
          _turns[_turns.length - 1] = ChatTurn(
            text.isEmpty && !streaming
                ? "I could not answer that just now."
                : text,
            fromStudent: false,
          );
        }
      });
      _scrollToEnd();

      if (!streaming) _finishStreaming();
    }, onError: (_) {
      // A dropped listener is not fatal on its own — the reply is still
      // being written server-side regardless of whether this client can see
      // it. Stop waiting rather than hang; whatever text already arrived
      // stands as the shown answer.
      _finishStreaming();
    });
  }

  /// Tears down the listener and timeout, and clears the sending state.
  /// Idempotent — safe to call from more than one of the three places above
  /// that can end a stream (completion, error, timeout).
  void _finishStreaming() {
    _streamTimeout?.cancel();
    _streamTimeout = null;
    _replySub?.cancel();
    _replySub = null;
    if (mounted) setState(() => _sending = false);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Back-button fix (2026-09-03) — same bug and same fix as
  /// `pages/Questions.dart`'s own `build()`: no `PopScope`/`WillPopScope`
  /// at all before this fix, so a hardware back press with the keyboard
  /// open could close the app instead of just the keyboard. Same
  /// `PopScope<Object?>` + `canPop: false` idiom, same `viewInsets.bottom >
  /// 0` keyboard-open check — applies regardless of this screen's own
  /// AppBar, which only affects a tapped back arrow, not the hardware
  /// back button/gesture this fix targets.
  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (MediaQuery.of(context).viewInsets.bottom > 0) {
              FocusScope.of(context).unfocus();
              return;
            }
            Navigator.of(context).pop();
          },
          child: Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            iconTheme: IconThemeData(color: colorProvider.secondColor),
            title: Text(
              "Ask a Question",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              // Stage 6 (2026-08-24) — browse past date-based sessions.
              IconButton(
                tooltip: "Past conversations",
                icon: Icon(Icons.history, color: colorProvider.secondColor),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AssistantHistoryListPage(uid: widget.uid),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _dailyMessageStatusBanner(),
                Expanded(
                  child: _loadingHistory ?
                      const Center(child: CircularProgressIndicator()) :
                      _turns.isEmpty ?
                          _starterView() :
                          _messageList(),
                ),
                if (_sending) _thinkingRow(),
                _composer(),
              ],
            ),
          ),
          ),
        );
      },
    );
  }


  /// Replaces the "Prabhupada content feed" placeholder — the feed is these
  /// openings into the same corpus.
  Widget _starterView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      children: [
        Icon(Icons.forum_outlined, size: 48, color: Colors.blue.shade200),
        const SizedBox(height: 16),
        const Text(
          "Ask about the teachings",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "Answers come from Śrīla Prabhupāda's books, letters and recorded "
          "talks. You can also ask about your practice, or about this app.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 24),
        ..._starters.map(
          (s) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _sending ? null : () => _send(s),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.auto_stories_outlined,
                          size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      itemCount: _turns.length,
      itemBuilder: (context, i) => chatBubble(context, _turns[i]),
    );
  }

  /// Issue 3 fix (2026-09-16) — the waiting/failure state for today's daily
  /// encouragement message (see `_bootstrap`/`_ensureDailyEncouragement`).
  /// Sits above the starter view or message list, which stay visible and
  /// usable underneath it — generating today's message never blocks a
  /// student from asking their own question in the meantime.
  Widget _dailyMessageStatusBanner() {
    if (_dailyMessageError != null) {
      return Container(
        width: double.infinity,
        color: Colors.red.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _dailyMessageError!,
                style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      );
    }

    if (_preparingDailyMessage) {
      return Container(
        width: double.infinity,
        color: Colors.orange.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              "Preparing today's message for you…",
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade800,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _thinkingRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            "Looking through the teachings…",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_sending,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: "Ask something…",
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onSubmitted: _sending ? null : (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: _sending ? Colors.grey : Colors.blue.shade600,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              onPressed: _sending ? null : () => _send(),
            ),
          ),
        ],
      ),
    );
  }
}
