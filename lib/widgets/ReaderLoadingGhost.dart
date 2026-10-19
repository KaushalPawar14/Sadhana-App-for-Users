import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';

/// What a book shows while it opens: a title bar and paragraph-shaped lines, in the CURRENT reading
/// colours (Light, Dark or Sepia), breathing softly. It replaces the circular spinner. It is laid out like the
/// reading page itself (same side padding, a title line then paragraphs), so the text fades in over it
/// without anything moving. With "reduce motion" it is still.
class ReaderLoadingGhost extends StatefulWidget {
  const ReaderLoadingGhost({super.key, required this.background, required this.line});

  /// The reading page's background (what the page looks like at rest).
  final Color background;

  /// The colour the lines are drawn with, before the breathing fades them (the reading mode's secondary text).
  final Color line;

  /// The side padding of the reading page's text.
  static const double sidePadding = 20;

  @override
  State<ReaderLoadingGhost> createState() => _ReaderLoadingGhostState();
}

class _ReaderLoadingGhostState extends State<ReaderLoadingGhost> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = FolkMotion.reduced(context);
    if (reduced != _reduced || !_controller.isAnimating && !reduced) {
      _reduced = reduced;
      if (reduced) {
        _controller.stop();
        _controller.value = .5;
      } else {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Paragraphs: how many lines each has and how long the last one is (a fraction of the width).
  static const List<(int, double)> _paragraphs = [(5, .62), (4, .8), (6, .45), (3, .7), (5, .55), (4, .85), (5, .4)];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Opening the book',
      child: ColoredBox(
        key: const ValueKey('reader-loading-ghost'),
        color: widget.background,
        child: LayoutBuilder(
          builder: (context, box) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                // between 10 % and 22 % of the line colour
                final alpha = .10 + .12 * (_reduced ? .5 : Curves.easeInOut.transform(_controller.value));
                final color = widget.line.withValues(alpha: alpha);
                Widget bar(double widthFactor, double height) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: widthFactor,
                        child: Container(
                          height: height,
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
                        ),
                      ),
                    );
                return ClipRect(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(ReaderLoadingGhost.sidePadding, 24, ReaderLoadingGhost.sidePadding, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // the title bar
                        bar(.55, 22),
                        const SizedBox(height: 28),
                        for (final p in _paragraphs) ...[
                          for (var i = 0; i < p.$1; i++) ...[
                            bar(i == p.$1 - 1 ? p.$2 : 1, 12),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
