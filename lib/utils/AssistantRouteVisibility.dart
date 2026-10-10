import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/AssistantScreen.dart';

/// Tells the floating assistant button when the assistant screen itself is the
/// top route, so the button can step out of the way there (it would only
/// duplicate the screen and could cover its send button).
///
/// Attach [instance] to the inner `MaterialApp`'s `navigatorObservers`. It
/// follows the route stack and reads nothing but each route's name, so it does
/// not touch any screen's own navigation.
class AssistantRouteVisibility extends NavigatorObserver {
  AssistantRouteVisibility();

  static final AssistantRouteVisibility instance = AssistantRouteVisibility();

  /// True while the route on top is the assistant screen.
  final ValueNotifier<bool> onAssistant = ValueNotifier<bool>(false);

  Route<dynamic>? _top;

  void _setTop(Route<dynamic>? route) {
    _top = route;
    final isAssistant = route?.settings.name == kAssistantRouteName;
    // Navigator callbacks can arrive while the tree is building; deliver the
    // change afterwards so listeners never call setState mid-build.
    scheduleMicrotask(() => onAssistant.value = isAssistant);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _setTop(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _setTop(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _top) _setTop(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == _top) _setTop(newRoute);
  }
}
