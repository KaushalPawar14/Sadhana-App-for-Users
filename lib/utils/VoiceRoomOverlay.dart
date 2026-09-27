import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/VoiceRoomService.dart';
import 'Snackbar.dart';

/// The persistent "who's in the room" icon (Part 6) — reuses
/// `FloatingAssistantOverlay.dart`'s exact draggable/persisted-position
/// mechanism (Rule 1: same `Positioned` + `GestureDetector` pan/tap
/// disambiguation, same screen-fraction `shared_preferences` persistence),
/// with its own distinct preference keys and default corner so the two
/// buttons never start stacked on top of each other.
///
/// Visible only while this student is a LIVE participant in an active
/// voice room — driven by a single-equality-filter Firestore listener on
/// `voiceRooms` (`array-contains` on `participantUids`; `status == "active"`
/// is then checked in Dart, the same "one filter, rest in Dart" shape every
/// query in this project already uses, so no composite index is needed) —
/// AND additionally hidden while `VoiceRoomScreen` for that same room is
/// itself the current top route (see `_ActiveRoomWatcherState.build()`'s
/// `ValueListenableBuilder` on `ActiveVoiceRoomSession.screenVisible`):
/// showing this icon while the full room UI is already on screen would be
/// redundant, and tapping it there would just push a second, stacked copy
/// of the same screen.
///
/// ⚠️ Room persistence, per Part 6 item 3: navigating elsewhere in the app
/// does NOT remove this student from `participantUids` — only the room
/// screen's own explicit "Leave Room" action does (see `VoiceRoomScreen`).
/// This overlay existing at all, and finding the student still listed, is
/// what lets them background the app and rejoin later exactly as the
/// product owner required.
class VoiceRoomOverlay extends StatelessWidget {
  final Widget child;

  const VoiceRoomOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Switched from authStateChanges() to userChanges() (bug
        // investigation, 2026-09-16) — same fix, same reason, as
        // `FloatingAssistantOverlay.dart`'s own copy of this exact pattern;
        // see that file's header for the full explanation and the
        // `currentUser?.reload()` call in `services/PostAuthRouter.dart`
        // that this now reacts to.
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.userChanges(),
          builder: (context, snap) {
            final user = snap.data;
            if (user == null) return const SizedBox.shrink();
            return _ActiveRoomWatcher(uid: user.uid);
          },
        ),
      ],
    );
  }
}

/// Holds the live query; only mounts the actual draggable button once a
/// real active room is found, so the button's own drag state does not
/// reset every time Firestore emits an unrelated snapshot.
class _ActiveRoomWatcher extends StatefulWidget {
  final String uid;
  const _ActiveRoomWatcher({required this.uid});

  @override
  State<_ActiveRoomWatcher> createState() => _ActiveRoomWatcherState();
}

class _ActiveRoomWatcherState extends State<_ActiveRoomWatcher> {
  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — used
  /// to be constructed fresh directly in `build()`. Hoisted to a field,
  /// built once in `initState()` — safe unconditionally, since `widget.uid`
  /// is fixed for this widget's whole life.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeRoomStream;

  @override
  void initState() {
    super.initState();
    _activeRoomStream = FirebaseFirestore.instance
        .collection('voiceRooms')
        .where('participantUids', arrayContains: widget.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeRoomStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        QueryDocumentSnapshot<Map<String, dynamic>>? activeRoom;
        for (final d in docs) {
          if ((d.data()['status'] ?? '') == 'active') {
            activeRoom = d;
            break;
          }
        }

        if (activeRoom == null) return const SizedBox.shrink();

        final roomId = activeRoom.id;
        final participantCount =
            (activeRoom.data()['participantUids'] as List?)?.length ?? 0;

        // Hidden specifically while `VoiceRoomScreen` for THIS room is the
        // current top route (its own full UI already shows everything
        // this icon would) — shown again the instant it minimizes. See
        // `ActiveVoiceRoomSession.screenVisible`'s own header for why this
        // needs a `ValueListenableBuilder` rather than a plain check: a
        // bare field wouldn't cause this widget to rebuild on its own.
        return ValueListenableBuilder<bool>(
          valueListenable: ActiveVoiceRoomSession.screenVisible,
          builder: (context, screenVisible, _) {
            if (ActiveVoiceRoomSession.isActive(roomId) && screenVisible) {
              return const SizedBox.shrink();
            }
            return _DraggableRoomButton(
              uid: widget.uid,
              roomId: roomId,
              participantCount: participantCount,
            );
          },
        );
      },
    );
  }
}

const String _kPrefsDx = 'voiceroom_button_dx_fraction';
const String _kPrefsDy = 'voiceroom_button_dy_fraction';

const double _kButtonSize = 58;
const double _kBottomInset = 96;
const double _kSideInset = 14;

class _DraggableRoomButton extends StatefulWidget {
  final String uid;
  final String roomId;
  final int participantCount;

  const _DraggableRoomButton({
    required this.uid,
    required this.roomId,
    required this.participantCount,
  });

  @override
  State<_DraggableRoomButton> createState() => _DraggableRoomButtonState();
}

class _DraggableRoomButtonState extends State<_DraggableRoomButton> {
  Offset? _position;
  bool _loaded = false;
  bool _dragging = false;
  Offset? _pendingFraction;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble(_kPrefsDx);
    final dy = prefs.getDouble(_kPrefsDy);
    if (!mounted) return;
    setState(() {
      _pendingFraction = (dx != null && dy != null) ? Offset(dx, dy) : null;
      _loaded = true;
    });
  }

  Future<void> _persist(Offset fraction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefsDx, fraction.dx);
    await prefs.setDouble(_kPrefsDy, fraction.dy);
  }

  Offset _resolvePosition(Size screen) {
    final maxX = screen.width - _kButtonSize - _kSideInset;
    final maxY = screen.height - _kButtonSize - _kBottomInset;

    if (_position != null) {
      return Offset(
        _position!.dx.clamp(_kSideInset, maxX < _kSideInset ? _kSideInset : maxX),
        _position!.dy.clamp(0, maxY < 0 ? 0 : maxY),
      );
    }

    if (_pendingFraction != null) {
      final resolved = Offset(
        _pendingFraction!.dx * screen.width,
        _pendingFraction!.dy * screen.height,
      );
      return Offset(
        resolved.dx.clamp(_kSideInset, maxX < _kSideInset ? _kSideInset : maxX),
        resolved.dy.clamp(0, maxY < 0 ? 0 : maxY),
      );
    }

    // First-ever appearance: bottom-LEFT — the assistant button's own
    // default is bottom-right, so the two never start stacked together.
    return Offset(_kSideInset, maxY);
  }

  /// ZegoCloud removal (2026-09-09, size/perf task) — same "coming in a
  /// future update" message as `RduaFriendsScreen.dart`'s start/join
  /// actions, rather than reopening `VoiceRoomScreen` into a stub-simulated
  /// fake "connected" state. This icon itself stays exactly as it was —
  /// still shows whenever a `voiceRooms` doc lists this student as an
  /// active participant, still shows the live participant count — see this
  /// file's own header for why: with no path left anywhere in the app that
  /// can ever CREATE a new active room, this icon should only ever surface
  /// pre-existing/historical room data now, not a data-model change.
  void _openRoom() {
    showSnackbar(context, "Voice rooms are coming in a future update.",
        Colors.blueGrey, Icons.mic_off);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final screen = MediaQuery.of(context).size;
    final pos = _resolvePosition(screen);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (pos.dx + details.delta.dx)
                  .clamp(_kSideInset, screen.width - _kButtonSize - _kSideInset),
              (pos.dy + details.delta.dy)
                  .clamp(0, screen.height - _kButtonSize - _kBottomInset),
            );
          });
        },
        onPanEnd: (_) {
          setState(() => _dragging = false);
          final p = _position ?? pos;
          _persist(Offset(p.dx / screen.width, p.dy / screen.height));
        },
        onTap: _openRoom,
        child: AnimatedScale(
          scale: _dragging ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: _kButtonSize,
            height: _kButtonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.record_voice_over,
                    color: Colors.white, size: 24),
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade700, width: 1),
                    ),
                    child: Text(
                      '${widget.participantCount}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.green.shade800,
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
}
