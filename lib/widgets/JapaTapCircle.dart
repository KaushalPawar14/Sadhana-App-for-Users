import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// The Japa tap circle: a 272 dp circle in a full-width tap zone, with a progress ring, the
// true bead count in the middle, and the Part 7B motion around it.
//
// COUNTING NEVER DEPENDS ON ANIMATION. A tap calls [onTap] first, in the same
// event, before any animation is touched; no animation delays, debounces or
// blocks a tap, and every animation below is cosmetic only. The number shown is
// always [beads] exactly; the ring is the only thing that eases toward it.
//
// Animations (each reduced to nothing when "reduce animations" is on):
//  * idle glow pulse — scale 1.0 <-> 1.02 and a breathing glow over ~3 s. It
//    runs only while [idleEnabled] is true (the screen passes false when the
//    app is in the background; a screen that is not on top mutes tickers by
//    itself), stops the moment the student taps, and resumes 1.5 s after the
//    last tap.
//  * tap ripple — ONE controller, restarted by each tap, so rapid tapping can
//    never stack or leak ripples: at most one ring is ever alive.
//  * press scale 0.97 while a finger is down (PressScale).
//  * ring fill — eases to beads / beadsPerRound over ~300 ms. On a natural
//    round completion it fills to 100%, a glow burst plays, then it resets.
//  * count cross-fade — the number fades and rises in ~120 ms.
class JapaTapCircle extends StatefulWidget {
  const JapaTapCircle({
    super.key,
    required this.beads,
    required this.rounds,
    required this.onTap,
    this.idleEnabled = true,
    this.beadsPerRound = 108,
  });

  final int beads;

  // Completed rounds today. Used only to recognise a natural round completion
  // (so the burst plays); never displayed here.
  final int rounds;
  final VoidCallback onTap;
  final bool idleEnabled;
  final int beadsPerRound;

  static const Duration idleResumeDelay = Duration(milliseconds: 1500);

  @override
  State<JapaTapCircle> createState() => _JapaTapCircleState();
}

class _JapaTapCircleState extends State<JapaTapCircle>
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: FolkMotion.japaIdle,
  );
  late final AnimationController _ring = AnimationController(vsync: this);
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: FolkMotion.ripple,
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  Timer? _idleResume;
  Timer? _holdFull;
  bool _reduced = false;

  double get _target => widget.beads / widget.beadsPerRound;

  @override
  void initState() {
    super.initState();
    _ring.value = _target;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = FolkMotion.reduced(context);
    if (reduced != _reduced || !_idle.isAnimating) {
      _reduced = reduced;
      _updateIdle();
    }
  }

  @override
  void didUpdateWidget(JapaTapCircle old) {
    super.didUpdateWidget(old);
    if (widget.idleEnabled != old.idleEnabled) _updateIdle();

    final naturalCompletion = widget.rounds == old.rounds + 1 &&
        widget.beads == 0 &&
        old.beads == widget.beadsPerRound - 1;

    if (naturalCompletion) {
      if (_reduced) {
        _ring.value = _target;
      } else {
        _ring.animateTo(1,
            duration: FolkMotion.ringFill, curve: FolkMotion.out);
        _burst.forward(from: 0);
        _holdFull?.cancel();
        _holdFull = Timer(
          FolkMotion.ringFill + const Duration(milliseconds: 60),
          () {
            if (mounted) _ring.value = _target;
          },
        );
      }
    } else if (widget.beads != old.beads || widget.rounds != old.rounds) {
      if (_holdFull?.isActive ?? false) {
        _holdFull!.cancel();
        _ring.value = 0;
      }
      if (_reduced) {
        _ring.value = _target;
      } else {
        _ring.animateTo(_target,
            duration: FolkMotion.ringFill, curve: FolkMotion.out);
      }
    }
  }

  void _updateIdle() {
    final run = widget.idleEnabled && !_reduced;
    if (run) {
      if (!_idle.isAnimating) _idle.repeat(reverse: true);
    } else {
      _idle.stop();
      _idle.value = 0;
    }
  }

  void _handleTap() {
    // Count first. Nothing below can delay, drop or change that.
    widget.onTap();

    if (_reduced) return;
    // One controller, restarted: ripples can never pile up.
    _ripple.forward(from: 0);

    // Actively tapping: settle the idle pulse and keep it off until the
    // student pauses.
    if (_idle.isAnimating) {
      _idle.animateBack(0, duration: const Duration(milliseconds: 200));
    }
    _idleResume?.cancel();
    _idleResume = Timer(JapaTapCircle.idleResumeDelay, () {
      if (mounted) _updateIdle();
    });
  }

  @override
  void dispose() {
    _idleResume?.cancel();
    _holdFull?.cancel();
    _idle.dispose();
    _ring.dispose();
    _ripple.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final box = FolkJapaTokens.tapBox;

    // The number can never be wider than the circle: it scales down rather than
    // wrapping (three digits at 96 dp with a wide fallback font).
    final number = SizedBox(
        width: 170,
        child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedSwitcher(
              duration:
                  _reduced ? Duration.zero : const Duration(milliseconds: 120),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, .12), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                '${widget.beads}',
                key: ValueKey<int>(widget.beads),
                style: text.japaCount.copyWith(
                  color: FolkJapaTokens.onTap,
                  height: 1,
                ),
              ),
            )));

    return Semantics(
      button: true,
      label: 'Tap to count. ${widget.beads} of ${widget.beadsPerRound} beads',
      excludeSemantics: true,
      onTap: _handleTap,
      // The tappable zone is the full width available and at least the full
      // height of the circle row — as large as the old tap area. Taps anywhere
      // in it call the same handler; the circle and its ripple stay centred
      // and the same size.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: PressScale(
          child: SizedBox(
            width: double.infinity,
            height: box,
            child: Center(
              child: RepaintBoundary(
                child: SizedBox(
                  width: box,
                  height: box,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CirclePainter(
                            ring: _ring,
                            ripple: _ripple,
                            burst: _burst,
                            track: colors.japaRingTrack,
                            listenable:
                                Listenable.merge([_ring, _ripple, _burst]),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _idle,
                        builder: (context, child) {
                          final v = Curves.easeInOut.transform(_idle.value);
                          return Transform.scale(
                            key: const ValueKey<String>('japa-idle-scale'),
                            scale: 1 + .02 * v,
                            child: Container(
                              width: FolkJapaTokens.tapRadius * 2,
                              height: FolkJapaTokens.tapRadius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: FolkGradients.japaTap,
                                boxShadow: [
                                  BoxShadow(
                                    color: FolkJapaTokens.ringProgress
                                        .withValues(alpha: .12 + .16 * v),
                                    blurRadius: 24 + 10 * v,
                                    spreadRadius: 2 * v,
                                  ),
                                ],
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            number,
                            const SizedBox(height: 4),
                            Text(
                              'of ${widget.beadsPerRound} beads',
                              style: text.small.copyWith(
                                  color: FolkJapaTokens.onTapSecondary),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Tap to count'.toUpperCase(),
                              style: text.label
                                  .copyWith(color: FolkJapaTokens.onTap),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _CirclePainter extends CustomPainter {
  _CirclePainter({
    required this.ring,
    required this.ripple,
    required this.burst,
    required this.track,
    required Listenable listenable,
  }) : super(repaint: listenable);

  final Animation<double> ring;
  final Animation<double> ripple;
  final Animation<double> burst;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r = FolkJapaTokens.ringRadius;
    const w = FolkJapaTokens.ringWidth;
    const amber = FolkJapaTokens.ringProgress;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;

    // Track, then progress from 12 o'clock. Like the mockup, a bead count of 0
    // still shows a small dot (7 px of arc) where the ring starts.
    canvas.drawCircle(center, r, stroke..color = track);
    final sweep = math.max(ring.value.clamp(0.0, 1.0) * 2 * math.pi, 7 / r);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      sweep,
      false,
      stroke..color = amber,
    );

    // Round-complete glow burst.
    final b = burst.value;
    if (b > 0 && b < 1) {
      final fade = 1 - b;
      canvas.drawCircle(
        center,
        FolkJapaTokens.tapRadius + 30 * Curves.easeOut.transform(b),
        Paint()..color = amber.withValues(alpha: .22 * fade),
      );
      canvas.drawCircle(
        center,
        r + 6 * b,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * fade + 2
          ..color = amber.withValues(alpha: .5 * fade),
      );
    }

    // Tap ripple: one soft ring expanding from the circle's edge.
    final t = ripple.value;
    if (t > 0 && t < 1) {
      canvas.drawCircle(
        center,
        FolkJapaTokens.tapRadius + 26 * Curves.easeOut.transform(t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = amber.withValues(alpha: .38 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_CirclePainter old) => old.track != track;
}
