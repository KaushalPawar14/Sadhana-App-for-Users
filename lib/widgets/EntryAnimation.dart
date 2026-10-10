import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';

// Screen-entry animation: fades in and slides up ~14 dp over ~300 ms. Give each
// widget on a screen the next [index] and they arrive one after another, 50 ms
// apart. Plays once, when the widget is first built. With "reduce animations"
// on, the child is simply there.
class EntryAnimation extends StatefulWidget {
  const EntryAnimation({super.key, required this.index, required this.child});

  // Position in the stagger. Capped so a long list never waits long.
  final int index;
  final Widget child;

  static const int _maxIndex = 8;

  @override
  State<EntryAnimation> createState() => _EntryAnimationState();
}

class _EntryAnimationState extends State<EntryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final steps = widget.index.clamp(0, EntryAnimation._maxIndex);
    final delay = FolkMotion.entryStagger * steps;
    final total = delay + FolkMotion.entry;
    _controller = AnimationController(vsync: this, duration: total);
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: FolkMotion.out,
      ),
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
    // `FadeTransition` rather than an `Opacity` rebuilt every frame: the child
    // is painted once into its own layer and only the layer's alpha changes,
    // so a whole screen's cards are not re-recorded for each step of the fade.
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - _progress.value) * FolkMotion.entryOffset),
          child: child,
        ),
      ),
    );
  }
}
