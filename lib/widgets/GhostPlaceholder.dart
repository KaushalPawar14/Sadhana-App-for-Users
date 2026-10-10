import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';

// Loading / empty "ghost" of a widget: same size and radius, a soft tinted
// shape that breathes slowly.
//
// Every ghost under one [GhostScope] shares a single animation, so they pulse
// in sync. The scope only RUNS that animation while at least one ghost is
// actually on screen under it, so a screen whose content has loaded has no
// ticker going at all. It also stops when the app is backgrounded and, with
// "reduce animations" on, stays still. (A route that is not on top mutes its
// tickers by itself, through TickerMode.)
class GhostScope extends StatefulWidget {
  const GhostScope({super.key, required this.child});

  final Widget child;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GhostPulse>()?.animation;

  static _GhostScopeState? _stateOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_GhostPulse>()?.scope;

  @override
  State<GhostScope> createState() => _GhostScopeState();
}

class _GhostScopeState extends State<GhostScope>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FolkMotion.ghostPulse,
  );
  late final Animation<double> _pulse =
      CurvedAnimation(parent: _controller, curve: FolkMotion.standard);
  bool _reduced = false;
  int _ghosts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = FolkMotion.reduced(context);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  // Called by each ghost as it appears and disappears.
  void register() {
    _ghosts++;
    _sync();
  }

  void unregister() {
    _ghosts--;
    _sync();
  }

  void _sync() {
    final state = WidgetsBinding.instance.lifecycleState;
    final visible = state == null || state == AppLifecycleState.resumed;
    final run = _ghosts > 0 && visible && !_reduced;
    if (run) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      if (_controller.isAnimating) _controller.stop();
      // Only touch the value when it actually changes: setting it notifies the
      // ghosts that are already drawn, which must not happen mid-build.
      final rest = _reduced ? .5 : 0.0;
      if (_controller.value != rest) _controller.value = rest;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _GhostPulse(animation: _pulse, scope: this, child: widget.child);
}

class _GhostPulse extends InheritedWidget {
  const _GhostPulse({
    required this.animation,
    required this.scope,
    required super.child,
  });

  final Animation<double> animation;
  final _GhostScopeState scope;

  @override
  bool updateShouldNotify(_GhostPulse oldWidget) =>
      animation != oldWidget.animation;
}

class GhostPlaceholder extends StatelessWidget {
  const GhostPlaceholder({
    super.key,
    this.width,
    this.height,
    this.radius = FolkShape.cardRadius,
    this.showBars = true,
    this.onGradient = false,
  });

  final double? width;
  final double? height;
  final double radius;

  // Two short rounded bars where a title and subtitle will appear.
  final bool showBars;

  // True when the ghost sits on a gradient tile: a slightly stronger tint of
  // the dark ink so it still reads on the colour.
  final bool onGradient;

  // 8% of the ink colour, breathing between 45% and 100% of that.
  static const double _baseOpacity = .08;
  static const double _lowest = .45;

  @override
  Widget build(BuildContext context) {
    final body = _GhostBody(widget: this);
    // A lone ghost with no scope above it gets its own.
    return GhostScope._stateOf(context) == null
        ? GhostScope(child: body)
        : body;
  }
}

class _GhostBody extends StatefulWidget {
  const _GhostBody({required this.widget});

  final GhostPlaceholder widget;

  @override
  State<_GhostBody> createState() => _GhostBodyState();
}

class _GhostBodyState extends State<_GhostBody> {
  _GhostScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = GhostScope._stateOf(context);
    if (scope != _scope) {
      _scope?.unregister();
      _scope = scope;
      _scope?.register();
    }
  }

  @override
  void dispose() {
    _scope?.unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.widget;
    final pulse = GhostScope.maybeOf(context);
    final colors = context.folk;
    final base = w.onGradient ? FolkColors.onGradient : colors.ghostBase;
    final baseOpacity = w.onGradient ? .14 : GhostPlaceholder._baseOpacity;

    Widget draw(double value) {
      final level =
          GhostPlaceholder._lowest + (1 - GhostPlaceholder._lowest) * value;
      final fill = base.withValues(alpha: baseOpacity * level);
      return Container(
        width: w.width,
        height: w.height,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w.radius),
          boxShadow: w.onGradient ? null : colors.cardShadows,
          color: fill,
        ),
        child: w.showBars
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _bar(fill, 120, 14),
                  const SizedBox(height: 8),
                  _bar(fill, 72, 10),
                ],
              )
            : null,
      );
    }

    if (pulse == null) return draw(.5);
    // Its own repaint layer: the pulse repaints only the ghost, not the page.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) => draw(pulse.value),
      ),
    );
  }

  Widget _bar(Color color, double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
}

// Shows [ghost] while [loading], then cross-fades (200-300 ms) into [child].
// Give both the same size and nothing moves. With "reduce animations" on the
// swap is instant.
class GhostCrossFade extends StatelessWidget {
  const GhostCrossFade({
    super.key,
    required this.loading,
    required this.ghost,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool loading;
  final Widget ghost;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: FolkMotion.of(context, FolkMotion.ghostCrossFade),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [
          ...previous,
          if (current != null) current,
        ],
      ),
      child: loading
          ? KeyedSubtree(key: const ValueKey<String>('ghost'), child: ghost)
          : KeyedSubtree(key: const ValueKey<String>('content'), child: child),
    );
  }
}

// The one short, friendly line that goes with ghosts ("No episodes yet").
class GhostMessage extends StatelessWidget {
  const GhostMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: FolkSpace.lg),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.folkText.small,
        ),
      );
}
