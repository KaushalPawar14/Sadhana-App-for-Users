import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';

// The play / pause glyph that morphs when the state flips: the old icon turns
// and shrinks away as the new one turns and grows in (~180 ms). With "reduce
// animations" on it simply swaps.
class PlayPauseIcon extends StatelessWidget {
  const PlayPauseIcon({
    super.key,
    required this.playing,
    required this.color,
    this.size = 22,
  });

  final bool playing;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: FolkMotion.of(context, const Duration(milliseconds: 180)),
      transitionBuilder: (child, animation) => RotationTransition(
        turns: Tween<double>(begin: .75, end: 1).animate(animation),
        child: ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
      child: Icon(
        playing ? Icons.pause : Icons.play_arrow,
        key: ValueKey<bool>(playing),
        size: size,
        color: color,
      ),
    );
  }
}
