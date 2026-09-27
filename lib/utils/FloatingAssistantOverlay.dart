import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/AssistantScreen.dart';
import 'SeenMarkers.dart';
import 'UnseenDot.dart';

/// The assistant's persistent entry point — Stage 5 of the AI assistant
/// redesign (built 2026-08-24).
///
/// ---------------------------------------------------------------------------
/// Root-level, not per-screen
/// ---------------------------------------------------------------------------
/// Wraps the `child` passed to `MaterialApp.builder` in `main.dart`'s
/// `AnimatedLogin`, **not** a widget dropped into `CurvedNavBar` or any
/// individual page. `builder`'s `child` is the entire `Navigator` — whichever
/// route is on top after any `push`/`pop` — so a `Stack` here sits above
/// **every** screen the signed-in app can show, survives navigation, and
/// needs no per-screen wiring. A version anchored inside `CurvedNavBar`
/// instead would vanish the moment any page was pushed on top of it, since a
/// pushed route replaces what's on screen within the same `Navigator`.
///
/// ---------------------------------------------------------------------------
/// Replaces the previous entry point
/// ---------------------------------------------------------------------------
/// The old path was a card in `Phase7Placeholders.dart`'s `Phase7Section`
/// (`_assistantCard`, embedded in the Journey tab only) that pushed
/// `AssistantScreen`. That card and its invocation were removed — see the
/// diff on that file — so `AssistantScreen` now has exactly one door: this
/// button, reachable from anywhere instead of one tab.
///
/// ---------------------------------------------------------------------------
/// Visibility
/// ---------------------------------------------------------------------------
/// Shown only when a student is signed in (`userChanges()`), so it never
/// appears over `SplashScreen`, `WelcomePage`, `CompleteProfilePage` or the
/// sign-in flow — an assistant button before there is anyone to assist would
/// be confusing, and none of those screens have a `uid` to hand it anyway.
///
/// Uses `userChanges()`, not `authStateChanges()` (bug investigation,
/// 2026-09-16): `authStateChanges()` does not reliably emit right after an
/// in-session `signInWithCredential`/`signInWithEmailAndPassword` — a real,
/// documented firebase_auth/FlutterFire bug (see
/// `services/PostAuthRouter.dart`'s own comment for the issue links), which
/// meant this icon never appeared until a full app restart. `userChanges()`
/// is the stream Firebase's own documented workaround (`currentUser
/// ?.reload()`, now called from `routeAfterAuthentication`) reliably
/// triggers — it is a strict superset of `authStateChanges()` (also fires on
/// sign-out), so nothing about hiding the icon on logout changes.
///
/// ---------------------------------------------------------------------------
/// Position: draggable, persisted, fails safely
/// ---------------------------------------------------------------------------
/// Stored as a **fraction of the screen** (0.0-1.0 on each axis) via
/// `shared_preferences` — already a dependency, already used the same way by
/// `Calendar.dart` and `ChantingScreen.dart` (Rule 1) — rather than raw
/// pixels. A fraction survives rotation and a different device size; a saved
/// pixel offset would not, and could push the button off-screen entirely on a
/// smaller phone.
///
/// **Default on first-ever launch: bottom-right**, inset from both edges and
/// held clear of `CurvedNavigationBar`'s 60px bar plus its own upward bulge —
/// see `_kBottomInset`. Every subsequent launch restores the student's own
/// last position; dragging saves immediately, not only on app close, so a
/// mid-session kill still remembers.
class FloatingAssistantOverlay extends StatelessWidget {
  final Widget child;

  const FloatingAssistantOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.userChanges(),
          builder: (context, snap) {
            final user = snap.data;
            if (user == null) return const SizedBox.shrink();
            return _DraggableButton(uid: user.uid);
          },
        ),
      ],
    );
  }
}

const String _kPrefsDx = 'assistant_button_dx_fraction';
const String _kPrefsDy = 'assistant_button_dy_fraction';

/// Diameter of the button. Also used to keep it fully on-screen when clamping
/// a restored or dragged position.
const double _kButtonSize = 58;

/// Clear of `CurvedNavigationBar`'s `height: 60` plus the curved bulge its
/// selected icon rises into, plus breathing room above that.
const double _kBottomInset = 96;

const double _kSideInset = 14;

class _DraggableButton extends StatefulWidget {
  final String uid;

  const _DraggableButton({required this.uid});

  @override
  State<_DraggableButton> createState() => _DraggableButtonState();
}

class _DraggableButtonState extends State<_DraggableButton> {
  Offset? _position; // top-left, in logical pixels for the current screen
  bool _loaded = false;
  bool _dragging = false;

  /// Follow-up task, 2026-09-10, Part 1 item 1 — "has today's daily
  /// encouragement message been seen" is a plain [SeenMarkers] comparison,
  /// no AI involved. "Latest activity" is simply the start of today, on
  /// this device's own clock — matching every other "today" comparison
  /// already made client-side in this app (`AssistantScreen.dart`'s own
  /// `todaySessionKey()`, `DateFormat('dd-MM-yyyy').format(DateTime.now())`
  /// — no existing IST-conversion convention exists on the Student app
  /// side to mirror instead). Built once, here, never in `build()`; does
  /// not auto-flip at midnight if the app is left open across it, the same
  /// pragmatic scope every other `SeenMarkers` consumer in this codebase
  /// already accepts (correct whenever checked, not a live clock).
  late final Stream<bool> _unseenStream;

  @override
  void initState() {
    super.initState();
    final startOfToday = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    _unseenStream = SeenMarkers.unseenFrom(
      Stream.value(Timestamp.fromDate(startOfToday)),
      SeenMarkers.seenAt(widget.uid, 'dailyEncouragement'),
    );
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble(_kPrefsDx);
    final dy = prefs.getDouble(_kPrefsDy);
    if (!mounted) return;

    setState(() {
      // Fractions are resolved to real pixels in build(), once the
      // constraints are known — see _resolvePosition. Storing them raw here
      // is what makes the saved spot correct after a rotation or on a
      // different device.
      _pendingFraction = (dx != null && dy != null) ? Offset(dx, dy) : null;
      _loaded = true;
    });
  }

  Offset? _pendingFraction;

  Future<void> _persist(Offset fraction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefsDx, fraction.dx);
    await prefs.setDouble(_kPrefsDy, fraction.dy);
  }

  Offset _resolvePosition(Size screen) {
    final maxX = screen.width - _kButtonSize - _kSideInset;
    final maxY = screen.height - _kButtonSize - _kBottomInset;

    if (_position != null) {
      // Already resolved this session — clamp only (screen size can't change
      // mid-session on a phone, but this is cheap insurance).
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

    // First-ever launch: bottom-right.
    return Offset(maxX, maxY);
  }

  void _openAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kAssistantRouteName),
        builder: (_) => AssistantScreen(uid: widget.uid),
      ),
    );
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
        // A plain tap (no drag) opens the assistant. Flutter's gesture arena
        // disambiguates tap from pan by movement threshold on its own — no
        // manual bookkeeping needed to tell them apart.
        onTap: _openAssistant,
        child: AnimatedScale(
          scale: _dragging ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 120),
          // Follow-up task, 2026-09-10, Part 3 — robot form, modern
          // colouring, frosted glass. Only this visual subtree changed;
          // the `GestureDetector`/`AnimatedScale`/`Positioned` above are
          // untouched, so drag, tap and persisted position behave exactly
          // as before (item 1/4).
          child: StreamBuilder<bool>(
            stream: _unseenStream,
            builder: (context, snap) => UnseenBadge(
              show: snap.data ?? false,
              // Kept INSIDE the button's own bounds (not poking past the
              // edge) so it is never clipped by a physical screen edge
              // when the button is dragged to the very top or side of the
              // screen (item 2) — the same restrained placement this
              // app's other unseen dots already use.
              offset: const Offset(6, 6),
              // Robot form, modern colouring, frosted glass — Follow-up
              // task, 2026-09-10, Part 3.
              child: ClipOval(
                child: BackdropFilter(
                  // Frosted glass: blur whatever is behind the button,
                  // then paint a translucent (not fully transparent) fill
                  // over it — the blur alone would look like a lens, not
                  // glass, without a tinted layer on top.
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: _kButtonSize,
                    height: _kButtonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6A5AE0).withOpacity(.55),
                          const Color(0xFF17C3B2).withOpacity(.55),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.22),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.smart_toy_rounded,
                        color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
