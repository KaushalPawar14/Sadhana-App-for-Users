import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether the student has reached the main app (the tab host) — i.e. signed in
/// AND finished registration. The floating assistant button and the voice-room
/// button show only then.
///
/// Signing in is not enough: a new student is signed in while they are still on
/// Welcome, the email form and CompleteProfile (name, gender, mobile, then date
/// of birth, rounds and residence). The tab host (`CurvedNavBar`) is only ever
/// built once the profile is complete (see `main.dart`, `PostAuthRouter.dart`,
/// `CompleteProfile.dart` and `Login.dart`), so it tells this object when it
/// appears and when it goes. A count, not a flag: when one tab host replaces
/// another the new one appears before the old one is gone.
///
/// Signing out takes the tab host off the screen, which hides the buttons
/// again; the next sign-in follows the same rule.
class MainAppReached {
  MainAppReached();

  static final MainAppReached instance = MainAppReached();

  final ValueNotifier<bool> reached = ValueNotifier<bool>(false);
  int _hosts = 0;

  void enter() {
    _hosts++;
    _publish();
  }

  void leave() {
    if (_hosts > 0) _hosts--;
    _publish();
  }

  // The tab host changes this while the tree is being built or torn down;
  // deliver afterwards so listeners never call setState mid-build.
  void _publish() {
    scheduleMicrotask(() {
      final now = _hosts > 0;
      if (reached.value != now) reached.value = now;
    });
  }
}
