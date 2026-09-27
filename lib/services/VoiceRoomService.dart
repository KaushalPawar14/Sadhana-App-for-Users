/// The voice-connection interface and a STUBBED implementation.
///
/// ⚠️ **The real ZegoCloud wiring was removed (2026-09-09)** — the product
/// owner's decision to drop the `zego_express_engine` dependency entirely
/// (~26 MB: a 20.5 MB native library plus 5.7 MB of Web-platform JS assets
/// that never executed on this Android app in the first place — see the
/// size audit this task acted on). [StubVoiceRoomService] is now the ONLY
/// implementation, and [createVoiceRoomService] always returns it — but
/// every call site that used to reach it (`RduaFriendsScreen.dart`'s start/
/// join actions, `VoiceRoomOverlay.dart`'s reopen tap) now shows a
/// "Voice rooms are coming in a future update" SnackBar instead of ever
/// calling it, so in practice nothing in the UI reaches this file's
/// `joinRoom` any more either. This interface, the stub, and
/// `ActiveVoiceRoomSession` below are all kept exactly as they were —
/// deliberately, not an oversight — so a future real implementation can be
/// dropped back in behind [createVoiceRoomService] with no call-site
/// changes, exactly as this split was originally designed for. The
/// `getVoiceRoomToken`/`sendRoomInvites` Cloud Functions are untouched and
/// still deployed for the same reason.
///
/// Everything in Parts 5-6 (room creation, broadcast, the persistent "who's
/// in the room" icon) is built against this interface and Firestore's own
/// `voiceRooms.participantUids` — NOT against this service — for the
/// participant roster. That split is deliberate: "who is in the room" is
/// real, working, Firestore-backed data regardless of which voice backend
/// is wired in; this interface's only job is the actual audio transport
/// (connect, mic on/off). Swapping which implementation is used needs no
/// change to any call site — only [createVoiceRoomService] below.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

enum VoiceConnectionState { disconnected, connecting, connected, failed }

/// The live audio-connection state machine for one room. One instance per
/// active room session — created on join, disposed on leave.
abstract class VoiceRoomService {
  Stream<VoiceConnectionState> get connectionState;

  /// The most recently known connection state, read synchronously.
  /// Mirrors [connectionState] the same way [isMicMuted] mirrors
  /// [micMuted] — needed because [connectionState] is a broadcast stream,
  /// which never replays its last event to a NEW listener. Without this, a
  /// [VoiceRoomScreen] re-subscribing to an already-connected session
  /// (e.g. reopened from the minimize overlay) would show "Connecting…"
  /// forever, since no further state-change event may ever fire on an
  /// already-stable connection.
  VoiceConnectionState get currentConnectionState;

  bool get isMicMuted;

  /// Broadcast so multiple listeners (the room screen AND the persistent
  /// overlay icon) can both react to a mic-mute change without one
  /// stealing the stream from the other.
  Stream<bool> get micMuted;

  Future<void> joinRoom({
    required String roomId,
    required String uid,
    required String displayName,
  });

  Future<void> leaveRoom();

  Future<void> toggleMic();

  void dispose();
}

/// STUB — simulates connection state transitions locally with no network
/// call of any kind. `connecting` -> `connected` after a short, fixed
/// delay (standing in for whatever real handshake latency ZegoCloud would
/// have), matching only the SHAPE a real implementation would have so the
/// UI built against it does not need to change when a real one lands.
///
/// ⚠️ TEMPORARY. Replace with a real ZegoCloud Voice/Group Call
/// implementation once the product owner has created an account and
/// provided credentials — see this file's own header and the HARD STOP in
/// the task that built this.
class StubVoiceRoomService implements VoiceRoomService {
  final _connectionController =
      StreamController<VoiceConnectionState>.broadcast();
  final _micController = StreamController<bool>.broadcast();

  bool _micMuted = false;
  Timer? _connectTimer;
  VoiceConnectionState _connectionState = VoiceConnectionState.disconnected;

  @override
  Stream<VoiceConnectionState> get connectionState => _connectionController.stream;

  @override
  VoiceConnectionState get currentConnectionState => _connectionState;

  @override
  bool get isMicMuted => _micMuted;

  @override
  Stream<bool> get micMuted => _micController.stream;

  void _setState(VoiceConnectionState next) {
    _connectionState = next;
    _connectionController.add(next);
  }

  @override
  Future<void> joinRoom({
    required String roomId,
    required String uid,
    required String displayName,
  }) async {
    _setState(VoiceConnectionState.connecting);
    _connectTimer?.cancel();
    // Simulated handshake delay only — no network call, no ZegoCloud SDK
    // import, nothing that reaches outside this process.
    _connectTimer = Timer(const Duration(milliseconds: 600), () {
      _setState(VoiceConnectionState.connected);
    });
  }

  @override
  Future<void> leaveRoom() async {
    _connectTimer?.cancel();
    _setState(VoiceConnectionState.disconnected);
  }

  @override
  Future<void> toggleMic() async {
    _micMuted = !_micMuted;
    _micController.add(_micMuted);
  }

  @override
  void dispose() {
    _connectTimer?.cancel();
    _connectionController.close();
    _micController.close();
  }
}

/// The one place an implementation gets chosen, kept as a single injection
/// point (Rule 1) — no call site elsewhere in the app instantiates
/// [StubVoiceRoomService] directly. Always the stub now (see this file's
/// own header) — a future real implementation is a one-line change here,
/// not a call-site change.
VoiceRoomService createVoiceRoomService() => StubVoiceRoomService();

/// Holds the ONE live [VoiceRoomService] connection across a
/// minimize/reopen cycle. Without this, `VoiceRoomScreen` reopening after
/// being minimized (see that file's own header) would call
/// [createVoiceRoomService] again in `initState()`, creating a SECOND
/// engine/second `loginRoom` for the same student in the same room while
/// the first one is still live — not just wasteful, but liable to
/// misbehave (the underlying `ZegoExpressEngine` is a single static/
/// singleton instance per the real SDK's own API shape).
///
/// [VoiceRoomScreen] is the only caller: it asks for the service for its
/// `roomId` in `initState()` (getting back the SAME instance if it is
/// reopening an already-live room, or a fresh one on a genuine first
/// join), and calls [clear] only from its two explicit ending paths
/// (`_leaveRoom`/`_endRoomForEveryone`) — never from a minimize or a
/// hardware-back pop, which is what lets the connection outlive the
/// screen that created it.
class ActiveVoiceRoomSession {
  ActiveVoiceRoomSession._();

  static VoiceRoomService? _service;
  static String? _roomId;

  /// Whether `VoiceRoomScreen` for [_roomId] is CURRENTLY the top route —
  /// i.e. joined AND not minimized. A [ValueNotifier], not a bare static
  /// bool: `VoiceRoomOverlay`'s icon must re-render the INSTANT this
  /// flips (screen opens -> icon should hide now; screen minimizes ->
  /// icon should reappear now). A bare field mutates silently — nothing
  /// would tell the overlay's `StreamBuilder` to rebuild, so the icon
  /// would stay stale until some unrelated Firestore snapshot happened to
  /// arrive. `ValueListenableBuilder` (see `VoiceRoomOverlay.dart`) reacts
  /// to this directly, independent of Firestore's own update cadence.
  static final ValueNotifier<bool> screenVisible = ValueNotifier(false);

  /// True when [roomId] already has a live (or connecting) session — the
  /// signal `VoiceRoomScreen` uses to skip re-running `joinRoom`/the
  /// `participantUids` write on reopen, and that `VoiceRoomOverlay` uses
  /// to confirm [screenVisible] actually refers to THIS room before
  /// trusting it.
  static bool isActive(String roomId) =>
      _service != null && _roomId == roomId;

  /// The connection for [roomId]: the SAME instance already in use if
  /// [isActive] is true, otherwise a freshly created (not yet joined) one
  /// that the caller must still call `joinRoom` on.
  static VoiceRoomService serviceFor(String roomId) {
    if (isActive(roomId)) return _service!;
    // Defensive only — a student is only ever expected to be in one
    // active room at a time, so this should not happen in practice, but a
    // stale session for a DIFFERENT room is torn down rather than
    // silently leaked/left running.
    _service?.dispose();
    final service = createVoiceRoomService();
    _service = service;
    _roomId = roomId;
    return service;
  }

  /// Marks whether [roomId]'s room screen is the current top route. A
  /// no-op if [roomId] is not the currently-active session (e.g. a stale
  /// call from a screen instance that a leave/end has already superseded).
  static void setScreenVisible(String roomId, bool visible) {
    if (_roomId != roomId) return;
    screenVisible.value = visible;
  }

  /// Explicit teardown — called ONLY by `VoiceRoomScreen`'s real leave/end
  /// paths, never by a screen pop/minimize/back button.
  static void clear(String roomId) {
    if (_roomId != roomId) return;
    _service = null;
    _roomId = null;
    screenVisible.value = false;
  }
}
