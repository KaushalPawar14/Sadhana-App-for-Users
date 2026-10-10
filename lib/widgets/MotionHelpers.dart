import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';
import 'EntryAnimation.dart';

// Small motion helpers shared by the screens. Each one is cosmetic: none of
// them is ever between a tap (or a value) and what the app does with it.

// Lets the rows of a list that are NEW since the last draw rise in once, while
// the first draw (rows that were already there) and later redraws stay still.
//
// Use one per list: wrap each row with [wrap] inside the item builder and call
// [markDrawn] with the item count each time the list is built.
class NewItemRise {
  int _seen = -1;
  final Set<int> _risen = {};

  Widget wrap(int index, Widget child) {
    if (_seen >= 0 && index >= _seen) _risen.add(index);
    // A row that once rose keeps the same widget type, so rebuilding it never
    // restarts or drops the animation.
    return _risen.contains(index)
        ? EntryAnimation(key: ValueKey('rise-$index'), index: 0, child: child)
        : child;
  }

  void markDrawn(int count) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _seen = count);
  }
}

// Slides [child] up from below while fading it in, and back down when it is
// removed (pass null). ~280 ms; with "reduce animations" on it just appears.
class SlideUpSwitcher extends StatelessWidget {
  const SlideUpSwitcher({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: FolkMotion.of(context, const Duration(milliseconds: 280)),
      switchInCurve: FolkMotion.out,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .6),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child == null
          ? const SizedBox.shrink(key: ValueKey<String>('empty'))
          : KeyedSubtree(key: const ValueKey<String>('shown'), child: child!),
    );
  }
}

// Eases a progress value toward each new reading (~220 ms, linear) instead of
// jumping, and follows exactly while [following] is true (the finger is
// dragging) or "reduce animations" is on. The value is only ever drawn, never
// used for anything else.
class EasedProgress extends StatelessWidget {
  const EasedProgress({
    super.key,
    required this.value,
    required this.builder,
    this.following = false,
  });

  final double value;
  final bool following;
  final Widget Function(BuildContext context, double shown) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: following || FolkMotion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.linear,
      builder: (context, shown, _) => builder(context, shown),
    );
  }
}
