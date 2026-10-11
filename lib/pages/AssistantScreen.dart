import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/SeenMarkers.dart';
import '../services/DailyMessageService.dart';
import '../widgets/AssistantStarterCards.dart';
import '../widgets/DailyMessageCard.dart';
import '../widgets/MarkdownText.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkPageBackground.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/MotionHelpers.dart';
import '../widgets/PressScale.dart';
import '../widgets/RoundIconButton.dart';
import '../widgets/TypingDots.dart';
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

  const ChatTurn(this.text,
      {required this.fromStudent, this.isDailyMessage = false});
}

/// The message bubble, shared between the live chat and the read-only past-
/// session viewer so the two never visually diverge.
///
/// Today's daily message is drawn as the warm message card; every other turn
/// is a bubble — ink for the student, a surface card for the reply.
Widget chatBubble(BuildContext context, ChatTurn turn) {
  if (turn.isDailyMessage) return _dailyMessageCard(context, turn);

  final mine = turn.fromStudent;
  return Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: _chatBubbleContent(context, turn, mine),
  );
}

/// Chat bubble corners: 22 everywhere except the corner nearest the speaker,
/// which is 6.
BorderRadius _bubbleRadius({required bool mine}) => BorderRadius.only(
      topLeft: const Radius.circular(FolkShape.messageBubbleRadius),
      topRight: const Radius.circular(FolkShape.messageBubbleRadius),
      bottomLeft: Radius.circular(mine ? FolkShape.messageBubbleRadius : 6),
      bottomRight: Radius.circular(mine ? 6 : FolkShape.messageBubbleRadius),
    );

/// Follow-up task, 2026-09-10, Part 2 — the daily message carries a small
/// caption so a student recognises it as their daily message, not a reply to
/// something they asked. Now a full-width warm gradient card.
Widget _dailyMessageCard(BuildContext context, ChatTurn turn) =>
    DailyMessageCard(text: turn.text);

Widget _chatBubbleContent(BuildContext context, ChatTurn turn, bool mine) {
  final colors = context.folk;
  final text = context.folkText;
  return Container(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * 0.82,
    ),
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: mine
        ? const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: mine ? colors.primaryBg : colors.surface,
      borderRadius: _bubbleRadius(mine: mine),
      boxShadow: mine ? null : colors.cardShadows,
    ),
    // The student's own words stay plain; the assistant's reply shows its
    // simple markdown (bold, italic, lists, headings) properly.
    child: mine
        ? Text(
            turn.text,
            style: text.body.copyWith(height: 1.5, color: colors.primaryFg),
          )
        : MarkdownText(
            turn.text,
            style: text.body.copyWith(height: 1.5, color: colors.text),
          ),
  );
}

class _AssistantScreenState extends State<AssistantScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<ChatTurn> _turns = [];

  bool _loadingHistory = true;
  bool _sending = false;

  /// UI only: a turn added after the list was first drawn rises in once; the
  /// first draw (earlier messages) never animates.
  final NewItemRise _rise = NewItemRise();

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

  /// Ensures today's message through `DailyMessageService` (which makes the
  /// one call to the idempotent — at most one OpenAI call per student per day,
  /// server-side — `generateDailyEncouragement` callable, and shares it with
  /// the app-open start and Journey).
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
    // The one shared service (`DailyMessageService`): it makes the call, and
    // if the app already started it for today (on open), this joins that call
    // or finds the message ready — never a second call.
    final result = await DailyMessageService.instance.ensureToday(widget.uid);
    return (isNew: result.isNew, failed: result.failed);
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
      final snap = await _firestore.collection('users').doc(widget.uid).get();
      acknowledged = snap.data()?['acknowledgedDisclosure'] == true;
    } catch (_) {
      acknowledged = false;
    }

    if (acknowledged) return true;
    if (!mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        final paragraph = text.small.copyWith(height: 1.45, color: colors.text);
        return AlertDialog(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FolkShape.cardRadius),
          ),
          title: Text("How this works", style: text.topBarTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Ask freely — this is here to help you.",
                  style: text.bodyStrong,
                ),
                const SizedBox(height: 10),
                Text(
                  "Questions about Krishna consciousness and the teachings, "
                  "about your daily practice, or about how this app works — "
                  "all of it is welcome, and no question is too small.",
                  style: paragraph,
                ),
                const SizedBox(height: 12),
                Text(
                  "Your guide can see these conversations. Not to check up on "
                  "you — it is one of the ways they stay close to how you are "
                  "doing, the same way they see your sadhana reports.",
                  style: paragraph,
                ),
                const SizedBox(height: 12),
                Text(
                  "And if you ever write something that suggests you are "
                  "going through a hard time, your guide is gently let know, "
                  "so they can be there for you.",
                  style: paragraph,
                ),
                const SizedBox(height: 12),
                Text(
                  "This assistant is not a replacement for real people. When "
                  "something weighs on you, your guide is the one to talk to.",
                  style: paragraph,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize:
                    const Size(FolkShape.touchTarget, FolkShape.touchTarget),
                foregroundColor: colors.mutedText,
                textStyle: text.chip,
              ),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Go back"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize:
                    const Size(FolkShape.touchTarget, FolkShape.touchTarget),
                backgroundColor: colors.primaryBg,
                foregroundColor: colors.primaryFg,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                textStyle: text.button,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("I understand"),
            ),
          ],
        );
      },
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
              e is FirebaseFunctionsException && e.message != null
                  ? e.message!
                  : "Could not send. Check your connection and try again.",
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
  /// top bar, which only affects a tapped back arrow, not the hardware
  /// back button/gesture this fix targets.
  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (colors.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: PopScope<Object?>(
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
          backgroundColor: colors.pageBackground,
          body: FolkPageBackground(
            child: SafeArea(
              child: Column(
                children: [
                  EntryAnimation(index: 0, child: _topBar()),
                  _dailyMessageStatusBanner(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration:
                          FolkMotion.of(context, FolkMotion.ghostCrossFade),
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, if (current != null) current],
                      ),
                      child: _loadingHistory
                          // While earlier messages load: two ghost bubbles.
                          ? KeyedSubtree(
                              key: const ValueKey<String>('ghost'),
                              child: _ghostChat(),
                            )
                          // One stable key, so the entry animation plays once
                          // and is not replayed when the starter view gives way
                          // to the message list on the first send.
                          : KeyedSubtree(
                              key: const ValueKey<String>('body'),
                              child: EntryAnimation(
                                key: const ValueKey('ask-body'),
                                index: 1,
                                child: _turns.isEmpty
                                    ? _starterView()
                                    : _messageList(),
                              ),
                            ),
                    ),
                  ),
                  if (_sending) _thinkingRow(),
                  EntryAnimation(index: 2, child: _composer()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Round back button, centred title, round history button. "Back" is the
  /// pop the AppBar's own back arrow did; the history button is the same
  /// "Past conversations" push as before.
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FolkSpace.pagePadding, FolkSpace.xl, FolkSpace.pagePadding, 0),
      child: Row(
        children: [
          RoundIconButton(
            icon: Icons.chevron_left_rounded,
            iconSize: 26,
            semanticLabel: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              "Ask a Question",
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.folkText.topBarTitle,
            ),
          ),
          // Stage 6 (2026-08-24) — browse past date-based sessions.
          RoundIconButton(
            icon: Icons.history_rounded,
            semanticLabel: 'Past conversations',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssistantHistoryListPage(uid: widget.uid),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Replaces the "Prabhupada content feed" placeholder — the feed is these
  /// openings into the same corpus. Four coloured question cards, one per category
  /// (spiritual, the app, daily practice, how am I doing), a different question for
  /// each every day (`utils/AssistantStarters.dart`); tapping one sends it through the
  /// same `_send` as typing it.
  Widget _starterView() {
    final colors = context.folk;
    final text = context.folkText;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          FolkSpace.pagePadding, 24, FolkSpace.pagePadding, FolkSpace.lg),
      children: [
        Icon(Icons.forum_outlined, size: 48, color: colors.disabledText),
        const SizedBox(height: 16),
        Text(
          "Ask about the teachings",
          textAlign: TextAlign.center,
          style: text.topBarTitle,
        ),
        const SizedBox(height: 8),
        Text(
          "Answers come from Śrīla Prabhupāda's books, letters and recorded "
          "talks. You can also ask about your practice, how you are doing, "
          "or this app. Tap a question to start, or write your own.",
          textAlign: TextAlign.center,
          style: text.small.copyWith(height: 1.45),
        ),
        const SizedBox(height: 24),
        AssistantStarterCards(onPick: _send, enabled: !_sending),
      ],
    );
  }

  Widget _messageList() {
    _rise.markDrawn(_turns.length);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg,
          FolkSpace.pagePadding, FolkSpace.sm),
      itemCount: _turns.length,
      itemBuilder: (context, i) =>
          _rise.wrap(i, chatBubble(context, _turns[i])),
    );
  }

  /// Ghost of the chat while earlier messages load: a short bubble on the
  /// right (yours) and a taller one on the left (the reply), at the list's own
  /// padding.
  Widget _ghostChat() {
    return GhostScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.lg,
            FolkSpace.pagePadding, FolkSpace.sm),
        children: const [
          Align(
            alignment: Alignment.centerRight,
            child: GhostPlaceholder(
              width: 160,
              height: 44,
              radius: FolkShape.messageBubbleRadius,
              showBars: false,
            ),
          ),
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostPlaceholder(
              width: 260,
              height: 92,
              radius: FolkShape.messageBubbleRadius,
            ),
          ),
        ],
      ),
    );
  }

  /// Issue 3 fix (2026-09-16) — the waiting/failure state for today's daily
  /// encouragement message (see `_bootstrap`/`_ensureDailyEncouragement`).
  /// Sits above the starter view or message list, which stay visible and
  /// usable underneath it — generating today's message never blocks a
  /// student from asking their own question in the meantime.
  Widget _dailyMessageStatusBanner() {
    final colors = context.folk;
    final text = context.folkText;
    const margin = EdgeInsets.fromLTRB(
        FolkSpace.pagePadding, FolkSpace.md, FolkSpace.pagePadding, 0);
    const padding =
        EdgeInsets.symmetric(horizontal: FolkSpace.lg, vertical: FolkSpace.md);

    if (_dailyMessageError != null) {
      return Container(
        width: double.infinity,
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: colors.calendarMissedBg,
          borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                size: 16, color: colors.calendarMissedText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _dailyMessageError!,
                style: text.caption.copyWith(color: colors.calendarMissedText),
              ),
            ),
          ],
        ),
      );
    }

    if (_preparingDailyMessage) {
      return Container(
        width: double.infinity,
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          gradient: FolkGradients.sky,
          borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: FolkColors.onGradient,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "Preparing today's message for you…",
              style: text.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: FolkColors.onGradient,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// The existing "thinking" indicator (spinner + line), now sitting in a
  /// reply-shaped bubble. The three-dot animation is Phase 11.
  Widget _thinkingRow() {
    final colors = context.folk;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
            FolkSpace.pagePadding, 4, FolkSpace.pagePadding, FolkSpace.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: FolkSpace.lg, vertical: FolkSpace.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: _bubbleRadius(mine: false),
          boxShadow: colors.cardShadows,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingDots(color: colors.mutedText),
            const SizedBox(width: 12),
            Text(
              "Looking through the teachings…",
              style: context.folkText.caption,
            ),
          ],
        ),
      ),
    );
  }

  /// A floating pill: the same text field, send button and rules as before
  /// (disabled while a reply is in flight, up to four lines, Enter sends).
  Widget _composer() {
    final colors = context.folk;
    final text = context.folkText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.sm,
          FolkSpace.pagePadding, FolkSpace.md),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(22, 6, 8, 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: colors.navShadows,
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
                style: text.body,
                cursorColor: colors.text,
                decoration: InputDecoration(
                  hintText: "Ask something…",
                  hintStyle: text.body.copyWith(color: colors.mutedText),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onSubmitted: _sending ? null : (_) => _send(),
              ),
            ),
            const SizedBox(width: FolkSpace.sm),
            Semantics(
              button: true,
              label: 'Send',
              enabled: !_sending,
              excludeSemantics: true,
              child: PressScale(
                enabled: !_sending,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _sending ? null : () => _send(),
                  child: SizedBox(
                    width: FolkShape.touchTarget,
                    height: FolkShape.touchTarget,
                    child: Center(
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _sending ? colors.disabledText : colors.primaryBg,
                        ),
                        child: Icon(Icons.send_rounded,
                            size: 20, color: colors.primaryFg),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
