import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/VoiceRoomService.dart';
import '../utils/ColorProvider.dart';
import '../utils/MalaLoading.dart';

/// The live voice-room screen — join, see who's in it, toggle mic, leave.
///
/// Reused for BOTH creating a fresh room and rejoining an existing one
/// (via the persistent overlay icon or a manual room-code join): the room
/// document already exists by the time this screen opens in every case
/// (creation writes it first — see `RduaFriendsScreen._createRoom`), so
/// this screen only ever needs a `roomId`, never a "create vs join" flag.
///
/// ⚠️ SAFETY-CRITICAL, per the product owner's explicit requirement
/// (Part 6 item 3 / Part 8 item 3 of the task that built this): navigating
/// away from this screen (back button, app backgrounded, another page
/// pushed on top) does NOT remove this student from the room's
/// `participantUids` — only the explicit "Leave Room" button does. The
/// room's own ending condition (`_leaveRoom`/`_endRoomForEveryone`) is the
/// ONLY code in this file that writes `status: "ended"`, and it does so
/// either because `participantUids` became empty as a DIRECT RESULT of
/// this explicit leave, or because the creator explicitly chose to end it
/// for everyone — never as a side effect of the creator specifically
/// being the one who left.
///
/// ⚠️ MINIMIZE, NOT DISCONNECT — every way of leaving this screen other
/// than the two buttons above (the AppBar's minimize arrow, the Android
/// hardware back button/gesture, or simply pushing another page on top)
/// is a MINIMIZE: the screen closes but the live [VoiceRoomService]
/// connection underneath it does not. This works because:
///   1. `dispose()` below only tears down the connection when `_leaving`
///      is true — and `_leaving` is set ONLY by `_leaveRoom`/
///      `_endRoomForEveryone`, never by `_minimize()` or a bare pop.
///      This screen adds no `PopScope`/`WillPopScope` of its own, so the
///      hardware back button/gesture already falls through to a plain
///      `Navigator.pop` — hitting this exact same `_leaving == false`
///      path as `_minimize()`, with no extra wiring needed.
///   2. The connection itself is held by [ActiveVoiceRoomSession], not by
///      this State object — so it survives this screen being destroyed,
///      and `initState()` reconnects to the SAME instance (via
///      [ActiveVoiceRoomSession.serviceFor]) rather than creating a
///      second one when the student reopens the room from
///      `VoiceRoomOverlay`'s persistent icon.
///
/// ⚠️ OVERLAY ICON VISIBILITY — `VoiceRoomOverlay`'s icon must be hidden
/// while THIS screen is the current top route (showing it then would be
/// redundant — the full room UI is already on screen), but shown the
/// instant this screen minimizes. `initState()` sets
/// `ActiveVoiceRoomSession.screenVisible` true (covers both a fresh join
/// and a reopen-after-minimize); `dispose()`'s minimize branch sets it
/// false again. See `ActiveVoiceRoomSession`'s own header for why this is
/// a [ValueNotifier], not a bare field.
class VoiceRoomScreen extends StatefulWidget {
  final String uid;
  final String roomId;

  const VoiceRoomScreen({super.key, required this.uid, required this.roomId});

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final VoiceRoomService _voice;

  VoiceConnectionState _connection = VoiceConnectionState.connecting;
  bool _micMuted = false;
  bool _leaving = false;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — used
  /// to be constructed fresh directly in `build()`. Hoisted to a field,
  /// built once in `initState()` — safe unconditionally, since
  /// `widget.roomId` is fixed for this screen's whole life.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _roomStream;

  /// Listener-leak fix (2026-09-09, size/perf task) — these two
  /// subscriptions were never captured before. Since `_voice` itself
  /// deliberately OUTLIVES a minimize (see this class's own header), every
  /// minimize-then-reopen cycle used to add two more live, never-cancelled
  /// listeners on top of the previous ones — a real accumulating leak
  /// across a single voice-call session, not just a one-time miss. Both
  /// are cancelled in `dispose()` below UNCONDITIONALLY (unlike `_voice`
  /// itself, which is only disposed on a genuine leave) — this SCREEN's own
  /// subscription to `_voice`'s streams must end whenever this screen is
  /// destroyed, whether that's a minimize or a real leave; only whether
  /// `_voice` itself is torn down depends on which one it was.
  StreamSubscription<VoiceConnectionState>? _connectionSub;
  StreamSubscription<bool>? _micSub;

  @override
  void initState() {
    super.initState();
    // Reopening after a minimize resolves to the SAME already-connected
    // instance (see this class's own header) — `_reopening` is what tells
    // us to skip `_joinAndConnect()`'s fresh join/roster write below.
    final reopening = ActiveVoiceRoomSession.isActive(widget.roomId);
    _voice = ActiveVoiceRoomSession.serviceFor(widget.roomId);
    // Read the CURRENT state synchronously: `connectionState` is a
    // broadcast stream that will not replay its last event to this new
    // listener, so on reopen there may be no further event to wait for.
    _connection = _voice.currentConnectionState;
    _micMuted = _voice.isMicMuted;
    _connectionSub = _voice.connectionState.listen((s) {
      if (mounted) setState(() => _connection = s);
    });
    _micSub = _voice.micMuted.listen((m) {
      if (mounted) setState(() => _micMuted = m);
    });
    _roomStream =
        _firestore.collection('voiceRooms').doc(widget.roomId).snapshots();
    if (!reopening) _joinAndConnect();
    // This screen is now the top route for this room — genuine fresh
    // join AND reopen-after-minimize both reach here, so both correctly
    // hide `VoiceRoomOverlay`'s icon (see `ActiveVoiceRoomSession`).
    ActiveVoiceRoomSession.setScreenVisible(widget.roomId, true);
  }

  /// Minimize — pops this screen WITHOUT touching `participantUids` and
  /// WITHOUT disposing `_voice` (see `dispose()` below and this class's
  /// own header). This is exactly what the Android hardware back
  /// button/gesture already does by default (this screen intercepts pop
  /// with no `PopScope`), so the two are identical by construction — a
  /// student pressing back is never surprised out of a live call.
  void _minimize() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    // Always cancelled, regardless of leave vs minimize — see this
    // screen's own `_connectionSub`/`_micSub` doc comment for why.
    _connectionSub?.cancel();
    _micSub?.cancel();
    // Only a genuine leave/end (the only two places that set `_leaving`)
    // tears down the actual connection. Minimizing — `_minimize()` or the
    // hardware back button/gesture, both of which leave `_leaving` false —
    // pops this screen while deliberately leaving `_voice` alive, held by
    // `ActiveVoiceRoomSession`. That persistence is the entire mechanism
    // minimize-to-overlay depends on.
    if (_leaving) {
      _voice.dispose();
      // `ActiveVoiceRoomSession.clear()` (already called by `_leaveRoom`/
      // `_endRoomForEveryone` before this pop) already reset
      // `screenVisible` to false as part of clearing the whole session —
      // nothing further needed here.
    } else {
      // Minimizing (explicit button OR hardware back/gesture — both fall
      // through to this same path, see this class's own header): this
      // screen is no longer the top route for this room, so
      // `VoiceRoomOverlay`'s icon should reappear.
      ActiveVoiceRoomSession.setScreenVisible(widget.roomId, false);
    }
    super.dispose();
  }

  Future<void> _joinAndConnect() async {
    // Only reached on a genuine fresh join — `initState()` skips this
    // entire method when reopening an already-active session (minimized,
    // then reopened via the overlay icon), since that student is already
    // listed. Idempotent regardless (arrayUnion is a no-op if already
    // present), so a rejoin after a real prior leave is still safe here.
    try {
      await _firestore.collection('voiceRooms').doc(widget.roomId).set({
        'participantUids': FieldValue.arrayUnion([widget.uid]),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal: the local voice connection below still proceeds: a
      // Firestore hiccup on the roster write should not block the call
      // itself. The overlay icon will simply be one write behind.
    }

    final snap = await _firestore.collection('users').doc(widget.uid).get();
    final displayName = (snap.data()?['name'] ?? 'Student').toString();

    await _voice.joinRoom(
      roomId: widget.roomId,
      uid: widget.uid,
      displayName: displayName,
    );
  }

  /// Explicit leave (Part 6 item 3's ONLY trigger for possibly ending the
  /// room). Runs inside a transaction so two students leaving at the same
  /// instant cannot both read "I'm the last one" and race on ending it.
  Future<void> _leaveRoom() async {
    if (_leaving) return;
    setState(() => _leaving = true);

    try {
      final ref = _firestore.collection('voiceRooms').doc(widget.roomId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>;
        final current = (data['participantUids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final remaining = current.where((u) => u != widget.uid).toList();

        final update = <String, dynamic>{'participantUids': remaining};
        // The room ends ONLY because this leave emptied it — not because
        // of who, specifically, just left (Part 6/8's explicit
        // requirement: creator-independent ending).
        if (remaining.isEmpty && data['status'] == 'active') {
          update['status'] = 'ended';
          update['endedAt'] = FieldValue.serverTimestamp();
        }
        tx.update(ref, update);
      });
    } catch (_) {
      // Fall through to popping regardless — a failed roster write must
      // not trap the student on a screen they are trying to leave.
    }

    await _voice.leaveRoom();
    ActiveVoiceRoomSession.clear(widget.roomId);
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Explicit end-for-everyone — the OTHER legitimate ending trigger
  /// (Part 2 item 4 / Part 6 item 3), available to the creator only.
  /// Distinct from `_leaveRoom`: this ends the room regardless of how many
  /// participants remain, by the creator's own explicit choice, not as a
  /// side effect of their presence.
  Future<void> _endRoomForEveryone(String creatorUid) async {
    if (widget.uid != creatorUid || _leaving) return;
    setState(() => _leaving = true);

    try {
      await _firestore.collection('voiceRooms').doc(widget.roomId).update({
        'status': 'ended',
        'participantUids': <String>[],
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    await _voice.leaveRoom();
    ActiveVoiceRoomSession.clear(widget.roomId);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: Colors.grey.shade900,
          appBar: AppBar(
            backgroundColor: Colors.grey.shade900,
            elevation: 0,
            // Minimize — visually distinct from the red "Leave"/"End room"
            // controls below (a plain chevron, not a call-ending icon),
            // and functionally distinct too: see `_minimize()` and this
            // class's own header for why this never disconnects the call.
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white),
              tooltip: 'Minimize',
              onPressed: _minimize,
            ),
            title: const Text("Voice Room",
                style: TextStyle(color: Colors.white)),
          ),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _roomStream,
            builder: (context, roomSnap) {
              if (!roomSnap.hasData || !roomSnap.data!.exists) {
                return const Center(child: CustomLoader());
              }
              final room = roomSnap.data!.data()!;
              final participantUids = (room['participantUids'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final isCreator = room['createdBy'] == widget.uid;
              final roomCode = (room['roomCode'] ?? '').toString();
              final ended = room['status'] == 'ended';

              // The room ended REMOTELY (another device's explicit leave
              // emptied it, or its creator ended it for everyone) — this
              // device never went through `_leaveRoom`/`_endRoomForEveryone`
              // itself, so `_leaving` must still be set here (same as
              // those two methods do) or `dispose()` below would treat
              // this pop as a mere minimize and leave the connection
              // running with nowhere to be reopened from.
              if (ended && !_leaving) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  setState(() => _leaving = true);
                  await _voice.leaveRoom();
                  ActiveVoiceRoomSession.clear(widget.roomId);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                });
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          _connection == VoiceConnectionState.connected
                              ? Icons.podcasts
                              : Icons.sync,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _connection == VoiceConnectionState.connected
                              ? "Connected"
                              : "Connecting…",
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (roomCode.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            "Room code: $roomCode",
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<Map<String, String>>>(
                      future: _resolveNames(participantUids),
                      builder: (context, nameSnap) {
                        final people = nameSnap.data ?? [];
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: people.length,
                          itemBuilder: (context, i) {
                            final p = people[i];
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.white24,
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                              title: Text(p['name'] ?? 'Student',
                                  style: const TextStyle(color: Colors.white)),
                              trailing: p['uid'] == room['createdBy']
                                  ? const Text("Host",
                                      style: TextStyle(color: Colors.white38))
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _roundButton(
                                icon: _micMuted ? Icons.mic_off : Icons.mic,
                                color: _micMuted ? Colors.red : Colors.white24,
                                onTap: _voice.toggleMic,
                              ),
                              const SizedBox(width: 20),
                              _roundButton(
                                icon: Icons.call_end,
                                color: Colors.red,
                                onTap: _leaving ? null : _leaveRoom,
                              ),
                            ],
                          ),
                          if (isCreator) ...[
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: _leaving
                                  ? null
                                  : () => _endRoomForEveryone(
                                      room['createdBy'].toString()),
                              child: const Text(
                                "End room for everyone",
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<List<Map<String, String>>> _resolveNames(List<String> uids) async {
    if (uids.isEmpty) return [];
    // Bounded by real friend-group sizes; `whereIn`/documentId lookups cap
    // at 30, comfortably above any realistic room size for this feature.
    final snap = await _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: uids.take(30).toList())
        .get();
    return snap.docs
        .map((d) => {
              'uid': d.id,
              'name': (d.data()['name'] ?? 'Student').toString(),
            })
        .toList();
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
