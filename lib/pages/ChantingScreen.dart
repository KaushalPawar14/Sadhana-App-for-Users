import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/SadhanaReportSource.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkPageBackground.dart';
import '../widgets/FolkStatusBar.dart';
import '../widgets/DayHeatStrip.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/JapaTapCircle.dart';
import '../widgets/PressScale.dart';
import '../widgets/RoundIconButton.dart';
import '../widgets/StatTile.dart';

/// Japa counter. Replaces the previous `ChantingScreen.dart` entirely, in
/// place (same file, same class name, same constructor), so the app's one
/// entry point (`pages/ABCDEScreen.dart`'s "C — Chanting" journey card)
/// needed no changes at all.
///
/// ---------------------------------------------------------------------------
/// ⚠️ Fully disconnected from sadhana reports (product owner's decision)
/// ---------------------------------------------------------------------------
/// Counts beads to 108, then banks a completed round:
///   users/{uid}.lifetimeRounds -> increment(1)
///
/// That is the ONLY Firestore write this screen makes. It used to also
/// increment `chantRounds`/`japaCounterRounds` and set `roundsSource` on the
/// student's sadhana report — that write was removed entirely (task: "Fully
/// disconnect the japa counter from sadhana reports"). This counter is a
/// personal tool only; a sadhana report reflects nothing but what the
/// student typed into the sadhana form. `japaCounterRounds`/`roundsSource`
/// still EXIST as fields (both forms, `pages/Questions.dart` and
/// `HostelersPage/Sadhana.dart`, still read/write them at submission time —
/// this screen never touches either form), but nothing in this file
/// populates them any more.
///
/// `lifetimeRounds` is kept, deliberately: it is a personal counter tally,
/// not a report figure, and both `pages/ABCDEScreen.dart` (this student's own
/// "C — Chanting" card) and the Guide app's `AbcdeActivityCard.dart` already
/// display it labelled explicitly as "rounds banked in the in-app counter" —
/// separate from, and deliberately never reconciled with, report-derived
/// chanting figures. Removing it would break two already-working, correctly
/// labelled displays for no reason connected to this task's actual goal.
///
/// The 30-day history strip below the counter still reads sadhana reports
/// (`fetchMergedDateReports`, both residence collections merged by date,
/// same as every other report reader in this app) — READ-ONLY, showing what
/// the student actually submitted, exactly as `sadhana-reports`/
/// `hostel-sadhana` hold it. This screen never writes there, so showing it
/// does not reintroduce any coupling; it is labelled "Your Sadhana Reports"
/// (not "counter history") so a student whose counter rounds don't appear
/// here understands why — the counter and the form are separate now, all
/// the way through.
///
/// All Firestore reads are cached in state and refreshed explicitly, never
/// built as a live `.snapshots()` stream inside `build()` — that would
/// create (and immediately leak) a fresh stream on every rebuild, including
/// every single bead tap.
class ChantingScreen extends StatefulWidget {
  final String uid;
  final String userName;

  /// Kept only for API parity with the one caller (`ABCDEScreen.dart`) —
  /// no longer used to choose a report collection (Part 1 item 4; see this
  /// file's own header). Nothing inside this screen reads it any more.
  final String role;

  const ChantingScreen({
    super.key,
    required this.uid,
    required this.userName,
    required this.role,
  });

  @override
  State<ChantingScreen> createState() => _ChantingScreenState();
}

class _ChantingScreenState extends State<ChantingScreen>
    with WidgetsBindingObserver {
  static const int beadsPerRound = 108;

  // SharedPreferences keys — the first three unchanged from the previous
  // screen, so an in-progress session recorded by the old build is still
  // picked up. `_kRoundDurations` is new (Part 2).
  static const String _kBeads = 'chanting_beads';
  static const String _kSessionRounds = 'chanting_session_rounds';
  static const String _kDate = 'chanting_date';
  static const String _kRoundDurations = 'chanting_round_durations';

  /// Part 3 item 1 — the product owner will supply the real ~6s single
  /// "Hare Krishna" mantra recording at exactly this path/filename. Until
  /// then this is a short, clearly synthetic placeholder tone (a soft
  /// repeating chime, generated — NOT the mantra, NOT a recording of
  /// anything) so `just_audio` has something genuinely decodable to load,
  /// loop, speed-adjust and count loop-boundaries against right now.
  /// Dropping the real recording in at this same path needs no code
  /// change; a different filename or extension needs only this constant
  /// updated.
  static const String _kMantraAsset = 'assets/audio/hare_krishna_mantra.wav';

  /// Part 3 item 1 — round-completion chime. Same placeholder approach as
  /// the mantra asset above: a short, clearly-synthetic bell-like tone
  /// (generated, not a recording of a real bell) so `just_audio` has
  /// something genuinely decodable to play right now. Swap the file at
  /// this same path for the real one; no code change needed unless the
  /// filename/extension changes too.
  static const String _kChimeAsset = 'assets/audio/round_complete_chime.wav';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AudioPlayer _player = AudioPlayer();

  /// Part 3 item 6 — a SEPARATE player instance from [_player] (which
  /// loops the mantra), so the one-shot completion chime and the looping
  /// mantra can play at the same time without one stopping or replacing
  /// the other: each `AudioPlayer` owns its own underlying platform
  /// player, and two independent players from the same app mix rather
  /// than interrupt each other. Loaded once in [initState]; each
  /// completion just seeks it back to the start and replays it.
  final AudioPlayer _chimePlayer = AudioPlayer();
  bool _chimeReady = false;

  int _beads = 0;
  int _sessionRounds = 0;

  /// Resolved lazily: the values handed in may be empty if the caller's own
  /// user lookup had not finished when this screen was opened.
  late String _name = widget.userName;

  int _lifetimeRounds = 0;
  List<Map<String, dynamic>> _historyData = [];
  bool _loadingStats = true;

  /// Time on the CURRENT round. A [Stopwatch] rather than a
  /// hand-accumulated tick counter: it reads real elapsed wall-clock time
  /// on every tick regardless of how late a given `Timer` tick actually
  /// fires, so a busy frame or a delayed timer never makes the displayed
  /// time drift from reality — the periodic timer below only decides how
  /// OFTEN to repaint, never what value is shown.
  ///
  /// ⚠️ **Deferred start (task: "Japa counter: deferred timer start,
  /// per-round history, round-completion feedback").** Deliberately NOT
  /// started here or anywhere in [initState] — it stays freshly
  /// constructed (not running, zero elapsed) until [_advanceBead] sees the
  /// FIRST bead of a round, whether from a manual tap or an auto-counted
  /// audio loop (both call that one method — see its own doc comment).
  /// `Stopwatch.reset()` alone does not stop a running stopwatch (per its
  /// own API docs), so every place this needs to go back to "not
  /// running, zero" explicitly calls `.stop()` first.
  final Stopwatch _roundStopwatch = Stopwatch();
  Timer? _roundTicker;
  Duration _roundElapsed = Duration.zero;

  /// Part 2 — today's completed rounds' durations, in seconds, oldest
  /// first. Reset alongside beads/rounds by the same daily boundary and
  /// the same manual "Reset Day" action; persisted alongside them too
  /// (`_kRoundDurations`).
  List<int> _roundDurationsSeconds = [];

  // ---------------------------------------------------------------------------
  // Chant with Prabhupada — Part 3
  // ---------------------------------------------------------------------------

  bool _audioReady = false;
  bool _audioFailed = false;
  bool _autoCountEnabled = false;
  double _speed = 1.0;
  StreamSubscription<PositionDiscontinuity>? _loopSub;

  /// Cosmetic only: false while the app is not in the foreground, so the tap
  /// circle's idle pulse can stop. Never read by the counting code.
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _restoreSession();
    _bootstrap();
    _ensureChimeLoaded();

    // Deliberately does NOT start `_roundStopwatch` — see that field's own
    // doc comment. This ticker just repaints the live display roughly once
    // a second while a round is actually running; while it isn't, `.elapsed`
    // stays `Duration.zero` and the display simply keeps showing 00:00:00.
    //
    // Smoothness pass: it only rebuilds when the elapsed time has actually
    // changed. While no round is running it is still zero, so the second-by-
    // second rebuild of this whole screen no longer happens.
    _roundTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = _roundStopwatch.elapsed;
      if (elapsed == _roundElapsed) return;
      setState(() => _roundElapsed = elapsed);
    });

    // Part 3 item 5 — event-driven loop counting, not a polling `Timer`.
    // `positionDiscontinuityStream` fires directly off the audio engine's
    // own decoded position the instant a `LoopMode.one` source wraps back
    // to its start (just_audio's own detection: position drops AND the
    // previous position was already past 60% of the clip's duration — see
    // that package's own `just_audio.dart`, around its
    // `_positionDiscontinuitySubscription` setup). Nothing here measures or
    // accumulates time at all, so there is no clock to drift against, even
    // across an ~11-minute, ~110-loop round: each bead is advanced exactly
    // once per genuine loop-back event, however long the round takes.
    // Subscribed once here, never rebuilt inside `build()`.
    _loopSub = _player.positionDiscontinuityStream.listen((event) {
      if (event.reason != PositionDiscontinuityReason.autoAdvance) return;
      if (!_autoCountEnabled) return;
      _advanceBead();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roundTicker?.cancel();
    _loopSub?.cancel();
    _player.dispose();
    _chimePlayer.dispose();
    super.dispose();
  }

  /// Part 3 item 4 — product owner's explicit decision: no background
  /// audio service. Leaving the app (backgrounded, or the screen locked)
  /// stops playback outright; nothing here auto-resumes it when the app
  /// comes back — the student consciously taps Play again. This never
  /// touches the bead/round COUNT, which lives entirely in state and
  /// `SharedPreferences`, independent of whether audio happens to be
  /// playing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground != _foreground) setState(() => _foreground = foreground);

    if (state != AppLifecycleState.resumed && _player.playing) {
      _player.pause();
      if (mounted) setState(() {});
    }
  }

  String _dateKey(DateTime date) => DateFormat('dd-MM-yyyy').format(date);

  /// Parses a "dd-MM-yyyy" document id, or null if it is not a date key.
  DateTime? _parseDateKey(String key) {
    try {
      return DateFormat('dd-MM-yyyy').parseStrict(key);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Session persistence — Part 4 items 1/2
  // ---------------------------------------------------------------------------

  /// Restores an in-progress round, but only if it belongs to today.
  ///
  /// "Today" is this device's own local calendar day (`DateTime.now()`,
  /// `DateFormat('dd-MM-yyyy')`) — the SAME convention every other
  /// client-side day-boundary in this app already uses
  /// (`AbcdeActivityCard.dart`'s 30-day window, `FloatingAssistantOverlay
  /// .dart`'s "seen today" check, the previous version of this very
  /// screen). The explicit Asia/Kolkata math in `functions/shared.js` is a
  /// SERVER-side necessity (Cloud Functions run on UTC hardware); no
  /// client-side code in either app does that conversion, since a
  /// student's phone is already set to their own local time. Matching that
  /// existing client convention here, rather than introducing a new
  /// explicit IST conversion nothing else on this side does, is what
  /// keeps this screen consistent with the rest of the app.
  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString(_kDate);
      final today = _dateKey(DateTime.now());

      if (savedDate == today) {
        if (!mounted) return;
        setState(() {
          _beads = prefs.getInt(_kBeads) ?? 0;
          _sessionRounds = prefs.getInt(_kSessionRounds) ?? 0;
          // Part 2 item 2 — restored alongside the existing session state,
          // same key list, same "only if today" guard.
          _roundDurationsSeconds = (prefs.getStringList(_kRoundDurations) ?? [])
              .map((s) => int.tryParse(s) ?? 0)
              .toList();
        });
      } else {
        // New day — start fresh (Part 4 item 2).
        await prefs.setString(_kDate, today);
        await prefs.setInt(_kBeads, 0);
        await prefs.setInt(_kSessionRounds, 0);
        await prefs.setStringList(_kRoundDurations, const []);
      }
    } catch (_) {
      // Counting still works without persistence.
    }
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDate, _dateKey(DateTime.now()));
      await prefs.setInt(_kBeads, _beads);
      await prefs.setInt(_kSessionRounds, _sessionRounds);
      await prefs.setStringList(
        _kRoundDurations,
        _roundDurationsSeconds.map((s) => s.toString()).toList(),
      );
    } catch (_) {
      // Ignored — persistence is best-effort.
    }
  }

  // ---------------------------------------------------------------------------
  // Firestore
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    await _ensureIdentity();
    await _refreshStats();
  }

  /// The name is what locates the sadhana report, so recover it from the
  /// user document when the caller passed a blank (role is no longer
  /// needed here at all — see this file's own header).
  Future<void> _ensureIdentity() async {
    if (_name.isNotEmpty) return;

    try {
      final doc = await _firestore.collection('users').doc(widget.uid).get();
      final name = (doc.data()?['name'] ?? '').toString();

      if (!mounted) return;
      if (name.isNotEmpty) setState(() => _name = name);
    } catch (_) {
      // Leaves the empty state in place.
    }
  }

  /// Single read of everything the screen displays. Called once on open and
  /// again after each completed round.
  Future<void> _refreshStats() async {
    try {
      final userDoc =
          await _firestore.collection('users').doc(widget.uid).get();
      final lifetimeRaw = userDoc.data()?['lifetimeRounds'];
      final lifetime = lifetimeRaw is num ? lifetimeRaw.toInt() : 0;

      final history = <Map<String, dynamic>>[];

      if (_name.isNotEmpty) {
        // Part 1 item 4 / Part 3 (history task) — both residence
        // collections, merged by date, never one picked by current role.
        final merged = await fetchMergedDateReports(_name);

        // Date documents are keyed "dd-MM-yyyy", which does not sort
        // chronologically, so index them and walk real dates instead.
        //
        // A sadhana report submitted on day N records day N-1's practice, so
        // each document's rounds belong to the day *before* its key.
        final byDate = <String, int>{};
        for (final entry in merged.entries) {
          final keyDate = _parseDateKey(entry.key);
          if (keyDate == null) continue;

          final actualDay = keyDate.subtract(const Duration(days: 1));
          byDate[_dateKey(actualDay)] = roundsOf(entry.value);
        }

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        for (int i = 29; i >= 0; i--) {
          final day = today.subtract(Duration(days: i));
          history.add({'date': day, 'rounds': byDate[_dateKey(day)] ?? 0});
        }
      }

      if (!mounted) return;
      setState(() {
        _lifetimeRounds = lifetime;
        _historyData = history;
        _loadingStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStats = false);
    }
  }

  /// Persists one completed round.
  ///
  /// ⚠️ **Fully disconnected from sadhana reports.** This used to also find
  /// today's report (in whichever collection actually held it) and
  /// increment `chantRounds`/`japaCounterRounds`/set `roundsSource` there.
  /// That write is removed entirely — this counter is a personal tool now;
  /// a sadhana report reflects only what the student typed into the
  /// sadhana form. `users/{uid}.lifetimeRounds` is the ONLY Firestore write
  /// this screen makes, kept because it is a personal tally, not a report
  /// figure — see this file's own header.
  ///
  /// This is the ONLY point in the whole screen that writes to Firestore
  /// at all, and it only runs once per completed round (every 108th bead),
  /// never once per bead — a per-bead write would be 108x the cost for no
  /// benefit, since individual beads are transient, local-only progress
  /// (`SharedPreferences`) until a round is actually complete.
  Future<void> _bankCompletedRound() async {
    try {
      await _firestore.collection('users').doc(widget.uid).set({
        'lifetimeRounds': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not save this round")),
        );
      }
    }

    // Refresh the cached lifetime total so the summary tile catches up.
    // (The history strip is sadhana-report data, untouched by this write —
    // see this file's own header — so it does not need refreshing here.)
    await _refreshStats();
  }

  // ---------------------------------------------------------------------------
  // Counting — Part 2
  // ---------------------------------------------------------------------------

  /// The ONE place a bead is ever advanced — a manual tap (`_onBeadTap`)
  /// and an auto-counted audio loop (`initState`'s `_loopSub`) both call
  /// this, so the two input modes can never disagree about what counts as
  /// a completed round or bank one twice between them. That also means
  /// the deferred-timer-start rule below and the round-completion
  /// feedback further down apply identically to both input modes, by
  /// construction, not by separately duplicating either behaviour.
  void _advanceBead() {
    HapticFeedback.selectionClick();

    // Part 1 item 1 — the round timer starts on the FIRST bead of a round,
    // not automatically when the screen opens. `isRunning` is false both
    // for a screen that just opened and for a round that just completed
    // (see the `.stop()` calls below and in `_setManual`), so this single
    // check covers "first bead of THIS round" in every case.
    if (!_roundStopwatch.isRunning) {
      _roundStopwatch.start();
    }

    final completed = _beads + 1 >= beadsPerRound;

    setState(() {
      if (completed) {
        // Part 2 item 1 — record this round's real duration before
        // resetting the stopwatch that measured it.
        _roundDurationsSeconds.add(_roundStopwatch.elapsed.inSeconds);

        _beads = 0;
        _sessionRounds++;
        // `.reset()` alone does not stop a running Stopwatch (see that
        // field's own doc comment) — `.stop()` first is what makes the
        // timer show 00:00:00 and NOT running until the next round's
        // first bead (Part 1 item 3).
        _roundStopwatch
          ..stop()
          ..reset();
        _roundElapsed = Duration.zero;
      } else {
        _beads++;
      }
    });

    _persistSession();

    if (completed) {
      _playRoundCompleteFeedback();
      _bankCompletedRound();
    }
  }

  void _onBeadTap() => _advanceBead();

  void _undo() {
    if (_beads == 0) return; // completed rounds are never undone
    setState(() => _beads--);
    _persistSession();
  }

  /// Part 2 item 5 — direct manual set, no confirmation (an intentional
  /// typed correction, not a one-tap destructive action). Beads are
  /// clamped to a real in-progress round (0-107); reaching 108 is what
  /// completing a round already means, so a "manual" completion just asks
  /// the student to bump rounds by one instead — keeps this local-only
  /// edit from ever needing to decide whether to bank a round on Firestore
  /// (this method never writes to Firestore at all, matching `_undo`'s own
  /// existing local-only philosophy above — see the class-level note on
  /// this in the rebuild's Part 1/2 report).
  void _setManual({required int rounds, required int beads}) {
    setState(() {
      _sessionRounds = rounds < 0 ? 0 : rounds;
      _beads = beads.clamp(0, beadsPerRound - 1);
      // Same stop-then-reset as `_advanceBead`'s completed branch — a
      // manual edit also means "not mid-round any more" for timer
      // purposes, so the next bead (in whichever round the student is
      // now on) is what starts it again.
      _roundStopwatch
        ..stop()
        ..reset();
      _roundElapsed = Duration.zero;
    });
    _persistSession();
  }

  /// Part 2 item 5 — destroys the day's count, so this is the one action
  /// in this screen gated by an explicit confirmation.
  Future<void> _confirmAndResetDay() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        return AlertDialog(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FolkShape.cardRadius),
          ),
          title: Text('Reset today\'s count?', style: text.topBarTitle),
          content: Text(
            "This clears today's rounds and beads on this device. It does not "
            "change anything already saved to your sadhana report.",
            style: text.small.copyWith(height: 1.45, color: colors.text),
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
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize:
                    const Size(FolkShape.touchTarget, FolkShape.touchTarget),
                foregroundColor: colors.calendarMissedText,
                textStyle: text.chip,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      // Part 2 item 1 — round history resets with the same daily/manual
      // reset the bead/round count uses, so it never shows stale rounds
      // that no longer match the reset session counter.
      setState(() => _roundDurationsSeconds = []);
      _setManual(rounds: 0, beads: 0);
    }
  }

  Future<void> _openManualSetSheet() async {
    final roundsController = TextEditingController(text: '$_sessionRounds');
    final beadsController = TextEditingController(text: '$_beads');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.folk.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(FolkShape.cardRadius)),
      ),
      builder: (sheetContext) {
        final colors = sheetContext.folk;
        final text = sheetContext.folkText;
        InputDecoration field(String label) => InputDecoration(
              labelText: label,
              labelStyle: text.small,
              filled: true,
              fillColor: colors.surfaceSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                borderSide: BorderSide.none,
              ),
            );
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set rounds & beads', style: text.topBarTitle),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: roundsController,
                      keyboardType: TextInputType.number,
                      style: text.body,
                      cursorColor: colors.text,
                      decoration: field('Rounds'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: beadsController,
                      keyboardType: TextInputType.number,
                      style: text.body,
                      cursorColor: colors.text,
                      decoration: field('Beads (0-107)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primaryBg,
                    foregroundColor: colors.primaryFg,
                    elevation: 0,
                    shape: const StadiumBorder(),
                    minimumSize: const Size.fromHeight(FolkShape.buttonHeight),
                    textStyle: text.button,
                  ),
                  onPressed: () {
                    final rounds = int.tryParse(roundsController.text.trim()) ??
                        _sessionRounds;
                    final beads =
                        int.tryParse(beadsController.text.trim()) ?? _beads;
                    _setManual(rounds: rounds, beads: beads);
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _confirmAndResetDay();
                  },
                  icon: Icon(Icons.delete_outline,
                      color: colors.calendarMissedText),
                  label: Text(
                    'Reset Day',
                    style: TextStyle(color: colors.calendarMissedText),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.calendarMissedText),
                    shape: const StadiumBorder(),
                    minimumSize: const Size.fromHeight(FolkShape.buttonHeight),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Chant with Prabhupada — Part 3
  // ---------------------------------------------------------------------------

  Future<void> _ensureAudioLoaded() async {
    if (_audioReady) return;
    try {
      await _player.setAsset(_kMantraAsset);
      await _player.setLoopMode(LoopMode.one);
      await _player.setSpeed(_speed);
      _audioReady = true;
    } catch (_) {
      _audioFailed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not load the chanting audio")),
        );
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioFailed) return;
    if (!_audioReady) await _ensureAudioLoaded();
    if (!_audioReady) return;

    if (_player.playing) {
      await _player.pause();
    } else {
      // Deliberately not awaited — for a looping source, just_audio's own
      // `play()` future only completes once playback is paused/stopped, so
      // awaiting it here would block this method (and the tap that called
      // it) until the student stops playback again.
      unawaited(_player.play());
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    if (_audioReady) await _player.setSpeed(speed);
  }

  // ---------------------------------------------------------------------------
  // Round-completion feedback — Part 3
  // ---------------------------------------------------------------------------

  /// Loads the completion chime once, eagerly, from [initState] — not
  /// lazily on the first completion. A round can take ~11 minutes; by the
  /// time one actually completes the asset has had the whole round to
  /// finish loading, so the feedback is never delayed by decoding on the
  /// critical moment itself.
  Future<void> _ensureChimeLoaded() async {
    if (_chimeReady) return;
    try {
      await _chimePlayer.setAsset(_kChimeAsset);
      _chimeReady = true;
    } catch (_) {
      // Sound unavailable — vibration below still fires on its own.
    }
  }

  /// Fires on every completed round, from BOTH input modes (both go
  /// through `_advanceBead`, which is the only caller of this method).
  ///
  /// Sound and vibration are two independent channels, not a fallback
  /// chain — both are always attempted, regardless of whether the other
  /// succeeds, because either one on its own can fail for reasons that
  /// have nothing to do with the other (no vibration hardware; the sound
  /// asset not yet loaded).
  Future<void> _playRoundCompleteFeedback() async {
    // Sound — Part 3 item 1. `_chimePlayer` is independent of `_player`
    // (the mantra looper) — see that field's own doc comment for why that
    // is what lets both play at once (item 6) instead of one cutting off
    // the other.
    unawaited(_playChime());

    // Vibration — Part 3 items 2/3. Fires unconditionally, not gated on
    // any detected ringer/silent state: this app has no reliable,
    // dependency-light way to query the device's ringer mode at all (no
    // existing package here exposes it, and Android's vibrator motor is
    // controlled by the VIBRATE permission, not by the ringer/notification
    // volume) — so rather than try to detect silent mode, vibration is
    // simply fired every time alongside the sound. That is also exactly
    // why it is the reliable channel for a student whose eyes are closed
    // or phone is silenced: it does not depend on the ringer at all.
    try {
      if (await Vibration.hasVibrator()) {
        // ~1.2s — "roughly the same duration" as the chime (Part 3 item 2).
        await Vibration.vibrate(duration: 1200);
      }
    } catch (_) {
      // No vibrator hardware, or the platform refused — sound above still
      // fires regardless.
    }
  }

  Future<void> _playChime() async {
    await _ensureChimeLoaded();
    if (!_chimeReady) return;
    try {
      await _chimePlayer.seek(Duration.zero);
      unawaited(_chimePlayer.play());
    } catch (_) {
      // Vibration in _playRoundCompleteFeedback still fires regardless.
    }
  }

  // ---------------------------------------------------------------------------
  // History helpers
  // ---------------------------------------------------------------------------

  static Color heatColor(int rounds) {
    if (rounds >= 8) return FolkJapaTokens.heat8;
    if (rounds >= 5) return FolkJapaTokens.heat5;
    if (rounds >= 3) return FolkJapaTokens.heat3;
    if (rounds >= 1) return FolkJapaTokens.heat1;
    return const Color(0xFFEEEEEE);
  }

  static int roundsOf(Map<String, dynamic>? data) {
    final raw = data?['chantRounds'];
    return raw is num ? raw.toInt() : 0;
  }

  static String _pad3(int n) => n.toString().padLeft(3, '0');

  /// Part 1 item 2 — HH:MM:SS, so a not-yet-started round reads "00:00:00"
  /// (not "00:00" — the example given for this task).
  static String _formatElapsed(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Part 2 item 3 — one completed round's duration, natural-language
  /// style ("7m 35s"), distinct from the live HH:MM:SS countdown display
  /// above.
  static String _formatRoundDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  /// Part 2 item 6 — the section's total, e.g. "1h 28m" or, under an
  /// hour, "42m".
  static String _formatTotalDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    return FolkStatusBar(
      child: Scaffold(
        backgroundColor: colors.pageBackground,
        body: FolkPageBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                EntryAnimation(index: 0, child: _buildTopBar()),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      FolkSpace.pagePadding,
                      0,
                      FolkSpace.pagePadding,
                      30 + MediaQuery.paddingOf(context).bottom,
                    ),
                    // One scope: the ghosts on this screen pulse together, and it
                    // only runs while one is showing.
                    child: GhostScope(
                      child: Column(
                        children: [
                          const SizedBox(height: 14),
                          EntryAnimation(index: 1, child: _buildReadout()),
                          const SizedBox(height: 14),
                          EntryAnimation(index: 2, child: _buildTapArea()),
                          const SizedBox(height: 16),
                          EntryAnimation(index: 3, child: _buildUndoRow()),
                          const SizedBox(height: 18),
                          EntryAnimation(index: 4, child: _buildAudioPanel()),
                          const SizedBox(height: 24),
                          _buildSectionLabel("Today's Session"),
                          _buildSessionSummary(),
                          const SizedBox(height: 12),
                          _buildRoundHistorySection(),
                          const SizedBox(height: 24),
                          _buildSectionLabel("Your Sadhana Reports"),
                          Text(
                            "What you submitted in your sadhana form — separate from "
                            "this counter, which never writes to your report.",
                            style:
                                context.folkText.caption.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          _buildHistory(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Back, the title, and the set / reset button — in place of the AppBar.
  Widget _buildTopBar() {
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
              "Japa Counter",
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.folkText.topBarTitle,
            ),
          ),
          RoundIconButton(
            icon: Icons.tune,
            semanticLabel: 'Set / reset',
            onPressed: _openManualSetSheet,
          ),
        ],
      ),
    );
  }

  /// Part 2 item 1 — rounds and beads as one readout, "RRR:BBB". Shown as a
  /// chip: the round you are on, with the exact readout beside it.
  Widget _buildReadout() {
    final colors = context.folk;
    final text = context.folkText;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: colors.iconShadows,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Round ${_sessionRounds + 1}',
              style: text.bodyStrong.copyWith(fontSize: 13),
            ),
            const SizedBox(width: 8),
            Text(
              '${_pad3(_sessionRounds)}:${_pad3(_beads)}',
              style: text.caption.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Part 2 item 3.
  Widget _buildRoundTimer() {
    final colors = context.folk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: colors.iconShadows,
      ),
      child: Text(
        _formatElapsed(_roundElapsed),
        style: context.folkText.topBarTitle.copyWith(
          fontSize: 22,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// Part 2 item 4 — the tap target: the full width of the content area and
  /// at least the full height of the circle. The count handler is the same one
  /// as before (`_onBeadTap` -> `_advanceBead`); the circle only draws around
  /// it and never sits between a tap and the count.
  Widget _buildTapArea() {
    return JapaTapCircle(
      beads: _beads,
      rounds: _sessionRounds,
      onTap: _onBeadTap,
      // The idle pulse only runs while the app is in the foreground.
      idleEnabled: _foreground,
      beadsPerRound: beadsPerRound,
    );
  }

  /// The round timer and the undo button, side by side.
  Widget _buildUndoRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildRoundTimer(),
        const SizedBox(width: FolkSpace.md),
        RoundIconButton(
          icon: Icons.undo,
          iconSize: 20,
          semanticLabel: 'Undo last bead',
          onPressed: _undo,
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(label.toUpperCase(), style: context.folkText.label),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    final colors = context.folk;
    return BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(FolkShape.cardRadius),
      boxShadow: colors.cardShadows,
    );
  }

  /// Part 3 — play/pause, speed, auto-count. A plain `Column`/`Row` layout
  /// throughout (no `Stack`), so there is no risk of the "Stack under an
  /// unconstrained parent" crash this app has already hit twice elsewhere.
  Widget _buildAudioPanel() {
    final colors = context.folk;
    final text = context.folkText;
    final playing = _player.playing;

    return Container(
      padding: const EdgeInsets.all(FolkSpace.lg),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: playing ? 'Pause mantra' : 'Play mantra',
                enabled: !_audioFailed,
                excludeSemantics: true,
                child: PressScale(
                  enabled: !_audioFailed,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _audioFailed ? null : _togglePlayback,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _audioFailed
                            ? colors.disabledText
                            : colors.primaryBg,
                      ),
                      child: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        color: colors.primaryFg,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Chant with Prabhupada", style: text.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      _audioFailed
                          ? "Chanting audio unavailable"
                          : playing
                              ? "Playing — loops automatically"
                              : "Tap play to loop the mantra",
                      style: text.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(width: 52, child: Text("Speed", style: text.small)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: colors.primaryBg,
                    inactiveTrackColor: colors.surfaceSecondary,
                    thumbColor: colors.primaryBg,
                    overlayColor: colors.primaryBg.withValues(alpha: .12),
                    activeTickMarkColor: Colors.transparent,
                    inactiveTickMarkColor: Colors.transparent,
                    valueIndicatorColor: colors.primaryBg,
                    valueIndicatorTextStyle:
                        text.caption.copyWith(color: colors.primaryFg),
                  ),
                  child: Slider(
                    value: _speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    label: '${_speed.toStringAsFixed(2)}x',
                    onChanged: (v) => _setSpeed(v),
                  ),
                ),
              ),
              Text(
                '${_speed.toStringAsFixed(2)}x',
                style: text.small.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text("Auto-count each loop",
                    style: text.body.copyWith(fontSize: 14)),
              ),
              Switch(
                value: _autoCountEnabled,
                thumbColor: WidgetStatePropertyAll(
                  _autoCountEnabled
                      ? colors.primaryFg
                      : (colors.isDark ? colors.mutedText : Colors.white),
                ),
                trackColor: WidgetStatePropertyAll(
                  _autoCountEnabled ? colors.primaryBg : colors.switchOff,
                ),
                trackOutlineColor:
                    const WidgetStatePropertyAll(Colors.transparent),
                onChanged: (v) => setState(() => _autoCountEnabled = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [countUp] counts the number up from 0 the FIRST time it is shown and
  /// never again: a value that changes later (a round was just banked) is
  /// shown at once, true. [ghost] shows a ghost bar in place of the number
  /// while it is still loading.
  Widget _summaryTile(String label, String value,
      {required int countUp, bool ghost = false}) {
    return Expanded(
      child: StatTile(
        value: value,
        label: label,
        style: FolkGradientStyle.coral,
        countUp: countUp,
        valueGhost: ghost,
      ),
    );
  }

  Widget _buildSessionSummary() {
    return Row(
      children: [
        _summaryTile("This session", '$_sessionRounds',
            countUp: _sessionRounds),
        const SizedBox(width: FolkSpace.cardGap),
        _summaryTile("Lifetime", '$_lifetimeRounds',
            countUp: _lifetimeRounds, ghost: _loadingStats),
      ],
    );
  }

  /// Part 2 — collapsible, collapsed by default (`ExpansionTile`'s own
  /// `initiallyExpanded` defaults to `false`), each completed round's
  /// duration listed underneath a simple rounds/total-time summary.
  ///
  /// ⚠️ **Bounded-height scrollable, not `LayoutBuilder` (Part 2 items 4/5;
  /// Part 4 item 2).** This app has already crashed twice from a Stack or
  /// scrollable sitting under an UNCONSTRAINED parent (no explicit size of
  /// its own to fall back on) — see `utils/UnseenDot.dart`'s own header for
  /// the first of those two. `ExpansionTile.children` lays out inside an
  /// internal `Column`, which — same as the outer `SingleChildScrollView`'s
  /// own `Column` here — gives a LOOSE, effectively unbounded height to
  /// whatever it holds. Wrapping the `ListView.builder` in a `SizedBox`
  /// with an explicit, fixed `height` gives that Column's child a TIGHT,
  /// bounded height regardless of how many rounds exist (16 in a day, or
  /// 60), so a long day scrolls inside that fixed box instead of growing
  /// and pushing the rest of the screen down. No `LayoutBuilder` anywhere
  /// in this file — the height is a plain literal, not computed from the
  /// parent's own constraints.
  Widget _buildRoundHistorySection() {
    final colors = context.folk;
    final text = context.folkText;
    final count = _roundDurationsSeconds.length;
    final totalSeconds = _roundDurationsSeconds.fold<int>(0, (a, b) => a + b);

    return Container(
      decoration: _cardDecoration(),
      // ExpansionTile paints its header (a ListTile internally) and its
      // own ink splash via the nearest Material ancestor. Without one
      // here, that ancestor is the Scaffold's own Material several
      // widgets up, which triggers "ListTile background color or ink
      // splashes may be invisible" — this exact warning has now recurred
      // three times in this project (`AssistantHistoryScreen.dart`,
      // `GuideCalendarPage.dart`'s end-date picker, and here); same fix
      // each time: `clipBehavior` matches the Container's own rounded
      // corners so the splash doesn't square off past them.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          // No divider lines above and below the open tile.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            iconColor: colors.text,
            collapsedIconColor: colors.mutedText,
            tilePadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text("Today's Round Times", style: text.bodyStrong),
            subtitle: Text(
              count == 0
                  ? "No rounds completed yet today"
                  : "$count ${count == 1 ? 'round' : 'rounds'} · "
                      "${_formatTotalDuration(Duration(seconds: totalSeconds))} total",
              style: text.caption,
            ),
            children: [
              if (count == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text("Complete a round to see it listed here.",
                      style: text.small),
                )
              else
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    itemCount: count,
                    itemBuilder: (context, i) {
                      final roundNumber = i + 1;
                      final seconds = _roundDurationsSeconds[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Text(
                          'Round $roundNumber — '
                          '${_formatRoundDuration(Duration(seconds: seconds))}',
                          style: text.body.copyWith(fontSize: 13),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _heatFill(int rounds, FolkColors colors) =>
      rounds <= 0 ? colors.surfaceSecondary : heatColor(rounds);

  Widget _buildHistory() {
    return GhostCrossFade(
      loading: _loadingStats,
      ghost: const DayHeatStripGhost(),
      child: _historyContent(),
    );
  }

  Widget _historyContent() {
    final colors = context.folk;
    final text = context.folkText;

    if (_historyData.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text("No history available", style: text.body),
      );
    }

    return DayHeatStrip(
      data: _historyData,
      fillFor: (rounds) => _heatFill(rounds, colors),
      onTapDay: (day, rounds) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              "${DateFormat('dd MMM yyyy').format(day)}: "
              "$rounds ${rounds == 1 ? 'round' : 'rounds'}",
            ),
          ),
        );
      },
    );
  }
}
