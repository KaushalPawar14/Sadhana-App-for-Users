import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';

/// The Leaderboard's calm, premium motion: one set of timings for the podium, the rows, the Scores cards and the
/// Results pages, so they all feel like one piece.
abstract final class RiseMotion {
  /// A podium bar rises from the bottom of its slot (slow, smooth settle).
  static const Duration bar = Duration(milliseconds: 760);

  /// The gap between the bars starting: 3rd, then 2nd, then 1st.
  static const Duration barStagger = Duration(milliseconds: 240);

  /// The medal, name and points fade in after their bar has risen.
  static const Duration info = Duration(milliseconds: 360);

  /// When the first list row starts: just after the last bar has risen (3rd starts at 0, 2nd at 240, 1st at 480; the 1st
  /// bar is up at 480 + 760 = 1240 ms).
  static const Duration rowsStart = Duration(milliseconds: 1300);

  /// The rows below the podium: a quick stagger, a short rise. Only the first [rows] rows animate (the ones on screen);
  /// a row further down is simply there when it scrolls in.
  static const Duration rowStagger = Duration(milliseconds: 45);
  static const Duration row = Duration(milliseconds: 340);
  static const int rows = 10;

  /// A card of the Scores tab / the Results pages: a gentle rise.
  static const Duration card = Duration(milliseconds: 520);
  static const Duration cardStagger = Duration(milliseconds: 80);

  static const double rowOffset = 12;
  static const double cardOffset = 22;
  static const Curve rise = Curves.easeOutCubic;
  static const Curve bars = Curves.easeOutQuart;
}

/// A gentle one-time rise: the child fades in and moves up by [offset] while it settles, after [delay]. It plays when
/// the widget is first built and never again (rebuilding, scrolling away and back, or coming back to the page do not
/// replay it: the widget keeps itself alive inside a list). With "reduce animations" on, the child is simply there.
///
/// The child keeps its place in the layout the whole time (only a transform moves it), so nothing around it jumps.
class RiseIn extends StatefulWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = RiseMotion.card,
    this.offset = RiseMotion.cardOffset,
    this.curve = RiseMotion.rise,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final Curve curve;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + widget.duration;
    _controller = AnimationController(vsync: this, duration: total);
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(widget.delay.inMilliseconds / total.inMilliseconds, 1, curve: widget.curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (FolkMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - _progress.value) * widget.offset),
          child: child,
        ),
      ),
    );
  }
}
