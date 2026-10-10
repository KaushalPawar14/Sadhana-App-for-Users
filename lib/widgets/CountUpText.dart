import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';

// A whole number that counts up from 0 (~600 ms) ONCE, the first time it is
// shown with [ready] true. After that it is just the number: when the value
// changes later (a round was completed, a refresh arrived) it shows the new,
// true value immediately — never an animation toward it.
//
// With "reduce animations" on there is no count-up at all.
class CountUpText extends StatefulWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.style,
    this.ready = true,
  });

  final int value;
  final TextStyle style;

  // False while the number is still loading; the count-up waits for true.
  final bool ready;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

enum _Phase { waiting, running, done }

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  _Phase _phase = _Phase.waiting;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FolkMotion.countUp,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _phase = _Phase.done);
        }
      });
  }

  // The first dependency callback runs before the first build, so the count-up
  // starts from 0 on the very first frame (no flash of the full number).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    if (_phase == _Phase.waiting) {
      _maybeStart();
    } else if (_phase == _Phase.running && widget.value != old.value) {
      // The value moved while counting up: show the true value now.
      _controller.stop();
      _phase = _Phase.done;
    }
  }

  void _maybeStart() {
    if (!mounted || _phase != _Phase.waiting || !widget.ready) return;
    if (FolkMotion.reduced(context) || widget.value <= 0) {
      _phase = _Phase.done;
      return;
    }
    _phase = _Phase.running;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase != _Phase.running) {
      return Text('${widget.value}', style: widget.style);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Text('${(widget.value * t).round()}', style: widget.style);
      },
    );
  }
}
