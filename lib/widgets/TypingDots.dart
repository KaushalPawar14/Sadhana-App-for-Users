import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';

// Three softly pulsing dots ("the assistant is replying"). One controller; the
// dots are offset in phase. It runs only while the app is in the foreground
// (and, as for any ticker, only while its route is on screen). With "reduce
// animations" on, the dots are still and the animation never starts.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color, this.dotSize = 7});

  final Color color;
  final double dotSize;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _reduced = false;

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

  void _sync() {
    final state = WidgetsBinding.instance.lifecycleState;
    final visible = state == null || state == AppLifecycleState.resumed;
    if (visible && !_reduced) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Replying',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: widget.dotSize * .8),
                  _dot(i),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dot(int index) {
    // Each dot swells and brightens in turn.
    var level = .55;
    if (!_reduced) {
      final t = (_controller.value - index * .18) % 1.0;
      level = t < .5
          ? Curves.easeInOut.transform(t * 2)
          : 1 - Curves.easeInOut.transform((t - .5) * 2);
    }
    // The brightening is in the dot's own colour (no `Opacity` layer per dot).
    final alpha = widget.color.a * (.35 + .65 * level);
    return Transform.scale(
      scale: .75 + .25 * level,
      child: Container(
        width: widget.dotSize,
        height: widget.dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: alpha),
        ),
      ),
    );
  }
}
