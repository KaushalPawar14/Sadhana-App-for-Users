import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../pages/BookPageList.dart';
import '../pages/Calendar.dart';
import '../pages/ChantingCompetition.dart';
import '../pages/RduaFriendsScreen.dart';

/// Notification deep-linking — Master Task, 2026-09-10, Part 3.
///
/// The ONE place a notification's `data` payload turns into a real
/// navigation action. Every FCM send in this project now carries a `dest`
/// string identifying which screen to open, plus whatever ids that screen
/// needs (see `functions/shared.js`, `functions/*.js`, and
/// `Guides/.../Services/Notifications.dart`'s own updated doc comments for
/// the sending side of this same scheme). This file is the ONLY place
/// that reads `dest` and decides what to push — every existing screen is
/// reached with its own already-established constructor, never a new
/// parallel navigation path.
///
/// ⚠️ **Reuses `studentNavigatorKey` from `main.dart`** (attached to the
/// INNER `MaterialApp`, the one every real screen actually lives in — see
/// that field's own doc comment for why) rather than declaring a second
/// key. `navigatorKey.currentState` is null before that `MaterialApp` has
/// first built (e.g. a notification tap arriving mid-launch, before
/// `AnimatedLogin` has even resolved which home screen to show) — routing
/// bails out silently in that case rather than crashing or queuing an
/// action against a not-yet-existing Navigator; the app still opens
/// normally to its own default screen, just without the extra jump.
///
/// ⚠️ **Fails safe by construction, not by knowing every failure mode in
/// advance.** An unrecognised or missing `dest`, a malformed payload, or
/// any error raised while resolving a destination (e.g. the current
/// user's own `users` doc failing to load) is caught by the single
/// try/catch wrapping the whole dispatch below and simply does nothing
/// further — the user is left on whatever screen the app already opened
/// to, never a broken page, never a crash.
///
/// ⚠️ **Splash-race fix (Master Task, 2026-09-10 — Part 1/2).** This used
/// to check `studentNavigatorKey.currentState` right here and silently
/// give up if it was null — which, on a cold start, it reliably WAS: the
/// old `getInitialMessage()` call resolves in well under a second, while
/// `SplashScreen`'s own fixed `Future.delayed(Duration(seconds: 5))`
/// (`pages/SplashScreen.dart`) hadn't pushed `AnimatedLogin` yet — meaning
/// the INNER `MaterialApp` this key is attached to did not exist yet.
/// That silent no-op, with nothing queued to retry, is Part 1's real bug:
/// a cold-start notification tap navigated nowhere, every time, not
/// intermittently. Confirmed by reading the exact 5-second timer, not
/// assumed. Fixed by [_appReady]/[_pendingRoute] below, which queue the
/// route instead of discarding it, and apply it once [markAppReady] fires
/// — see that function's own doc comment for why THAT moment, and only
/// that moment, is the one to wait for.
bool _appReady = false;
Map<String, dynamic>? _pendingRoute;

/// Called exactly once, from `AnimatedLogin`'s own `initState()` in
/// `main.dart`, via `WidgetsBinding.instance.addPostFrameCallback` — NOT
/// tied to `SplashScreen`'s own timer duration, which would just be a
/// second place to keep in sync with the first. A post-frame callback
/// scheduled from `AnimatedLogin.initState()` is guaranteed to fire only
/// after that frame — the one that built `AnimatedLogin`'s own inner
/// `MaterialApp`, and with it the real `Navigator` this whole file
/// targets — has actually been laid out. That is the true condition being
/// waited for; the splash's specific delay is just how a cold start
/// currently happens to reach it.
///
/// Distinguishes the three launch states (Part 2 item 2) by nothing more
/// than whether this has already run in this process: a cold start begins
/// with [_appReady] false (the splash is still showing, or about to run),
/// so [routeNotification] queues rather than pushes; a background/
/// foreground tap happens well after `AnimatedLogin.initState()` already
/// ran once for this process, so [_appReady] is already true and the
/// route applies immediately, exactly as if no splash existed — because
/// for that launch state, none is in the way. `AnimatedLogin` itself is
/// only ever constructed once per process (every later "go to the signed-
/// in shell" transition replaces routes on its OWN inner Navigator via
/// `pushAndRemoveUntil`, never rebuilds `AnimatedLogin`), so this callback
/// firing more than once, or [_appReady] ever reverting to false, cannot
/// happen within a single running process.
///
/// Consumed exactly once (Part 2 item 4): [_pendingRoute] is read and
/// cleared to null in the same breath it is dispatched, so a later resume
/// or a later call to this same function has nothing left to replay.
void markAppReady() {
  _appReady = true;
  final pending = _pendingRoute;
  _pendingRoute = null;
  if (pending != null) _dispatch(pending);
}

Future<void> routeNotification(Map<String, dynamic>? data) async {
  // Routing diagnostics (Master Task, 2026-09-10 — Part 1 item 2) —
  // checkpoint 2 ("is the router being called") and, via `_appReady`,
  // enough to tell a cold-start queue from an immediate dispatch.
  print('[notif-route] routeNotification called, data=$data, '
      'appReady=$_appReady');

  if (data == null || data.isEmpty) return;

  if (!_appReady) {
    // Cold start, still before `markAppReady()` — queue rather than
    // discard. Overwrites any earlier still-pending value deliberately:
    // `getInitialMessage()` only ever reports the ONE message that
    // actually launched the app, so there is never more than one
    // genuine candidate to hold during this window.
    _pendingRoute = data;
    return;
  }

  await _dispatch(data);
}

Future<void> _dispatch(Map<String, dynamic> data) async {
  final dest = (data['dest'] ?? '').toString();
  if (dest.isEmpty) return;

  final navState = studentNavigatorKey.currentState;
  // Routing diagnostics (Master Task, 2026-09-10 — Part 1 item 2) —
  // checkpoint 4 ("is the navigator key non-null at that moment").
  print('[notif-route] dispatching dest=$dest, navigatorReady=${navState != null}');
  if (navState == null) return;

  try {
    switch (dest) {
      case 'student_calendar':
        await _openCalendar(navState);
        break;

      case 'student_books':
        navState.push(
          MaterialPageRoute(builder: (_) => BooksSelectionScreen()),
        );
        break;

      case 'student_chanting':
        navState.push(
          MaterialPageRoute(builder: (_) => const ChantingCompetitionPage()),
        );
        break;

      case 'student_friends':
        navState.push(
          MaterialPageRoute(builder: (_) => const RduaFriendsScreen()),
        );
        break;

      // Any `dest` this app does not recognise (a value only a newer
      // build knows about, a value only the OTHER app's router
      // recognises, or a genuinely malformed payload) is exactly the
      // "unknown destination" case Part 3 item 4 asks for — falls
      // through to no-op, same as an empty `dest` above.
      default:
        break;
    }
  } catch (_) {
    // See this file's own header — any failure here fails safe.
  }
}

/// `CalendarPage` needs the CURRENT student's own `username`/`role`
/// (`CurvedNavBar`'s own `_fetchUserName()` resolves the exact same two
/// fields the exact same way, for the exact same reason — this is not a
/// new lookup pattern). A signed-out user, or a `users` doc that fails to
/// load or has no name, has nothing to open — handled by simply
/// returning, letting the outer try/catch or an empty-name check fail
/// safe rather than pushing a page with nothing to show.
Future<void> _openCalendar(NavigatorState navState) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final name = (doc.data()?['name'] ?? '').toString();
  final role = (doc.data()?['role'] ?? '').toString();
  if (name.isEmpty) return;

  navState.push(
    MaterialPageRoute(builder: (_) => CalendarPage(username: name, role: role)),
  );
}
