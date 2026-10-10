import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';

// A gentle "look here" pulse for a floating button: two soft rings spread out
// from it and fade, and the button gives a small swell, for [pulse] (about
// 1.2 s) once every [interval] (about 6 s). It is not continuous: between
// pulses nothing is animating and no ticker runs — only one waiting Timer, which
// costs nothing per frame.
//
// It never runs when it should not: not while the app is in the background,
// not while its route is hidden (TickerMode off), and not at all with "reduce
// animations" on. The rings are painted in their own repaint layer, with no
// blur and no backdrop filter.
class AttentionPulse extends StatefulWidget {
  const AttentionPulse({
    super.key,
    required this.child,
    required this.size,
    this.colors = const [Color(0xFF6A5AE0), Color(0xFF17C3B2)],
    this.interval = const Duration(seconds: 6),
    this.pulse = const Duration(milliseconds: 1200),
    this.firstDelay = const Duration(seconds: 2),
  });

  final Widget child;

  // The child's diameter; the rings start at its edge.
  final double size;
  final List<Color> colors;

  // Start-to-start time between pulses.
  final Duration interval;

  // How long one pulse lasts.
  final Duration pulse;

  // Wait before the first pulse after the button appears.
  final Duration firstDelay;

  @override
  State<AttentionPulse> createState() => _AttentionPulseState();
}

class _AttentionPulseState extends State<AttentionPulse>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final Animation<double> _swell;
  Timer? _timer;
  ValueListenable<bool>? _tickerMode;
  bool _reduced = false;
  bool _firstScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this, duration: widget.pulse)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _controller.value = 0;
          _schedule(widget.interval - widget.pulse);
        }
      });
    // The button swells over the first part of the pulse and settles.
    _swell = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.07)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.07, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 70,
      ),
    ]).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = FolkMotion.reduced(context);
    final notifier = TickerMode.getNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = notifier..addListener(_sync);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  bool get _active {
    final life = WidgetsBinding.instance.lifecycleState;
    final foreground = life == null || life == AppLifecycleState.resumed;
    return foreground && !_reduced && (_tickerMode?.value ?? true);
  }

  void _sync() {
    if (!mounted) return;
    if (_active) {
      if (_timer == null && !_controller.isAnimating) {
        _schedule(_firstScheduled ? widget.interval - widget.pulse : widget.firstDelay);
      }
    } else {
      _timer?.cancel();
      _timer = null;
      if (_controller.isAnimating) _controller.stop();
      if (_controller.value != 0) _controller.value = 0;
    }
  }

  void _schedule(Duration wait) {
    _firstScheduled = true;
    _timer?.cancel();
    if (!_active) {
      _timer = null;
      return;
    }
    _timer = Timer(wait, () {
      _timer = null;
      if (!mounted || !_active) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_sync);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The rings, in their own layer; they paint outside the button's box.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RingsPainter(
                  progress: _controller,
                  size: widget.size,
                  colors: widget.colors,
                ),
              ),
            ),
          ),
        ),
        ScaleTransition(scale: _swell, child: widget.child),
      ],
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.progress,
    required this.size,
    required this.colors,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double size;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size box) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final center = box.center(Offset.zero);
    final base = size / 2;
    for (var i = 0; i < 2; i++) {
      // The second ring follows the first a little later.
      final p = ((t - i * .22) / .78).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final eased = Curves.easeOutCubic.transform(p);
      final radius = base * (1 + .8 * eased);
      final fade = 1 - p;
      final color = i == 0 ? colors.first : colors.last;
      // A soft filled halo under the ring (a radial fade, no blur).
      final halo = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: .0),
            color.withValues(alpha: .22 * fade),
            color.withValues(alpha: 0),
          ],
          stops: const [.55, .8, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.18));
      canvas.drawCircle(center, radius * 1.18, halo);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 + 2.2 * fade
          ..color = color.withValues(alpha: .55 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.size != size || old.colors != colors || old.progress != progress;
}
