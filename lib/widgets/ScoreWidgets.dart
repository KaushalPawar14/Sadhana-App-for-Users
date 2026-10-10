import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkCard.dart';
import 'GhostPlaceholder.dart';

// Pieces shared by the leaderboards, results and winner screens.

// Medal gradients: light, like every card gradient, with the dark ink text on
// top, in light and dark themes alike.
abstract final class FolkMedal {
  static const LinearGradient gold = LinearGradient(
    colors: [Color(0xFFFFE9B8), Color(0xFFFFC978)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient silver = LinearGradient(
    colors: [Color(0xFFEDEFF5), Color(0xFFC9CFDD)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient bronze = LinearGradient(
    colors: [Color(0xFFFFDCC2), Color(0xFFEBA877)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 0 = first place; null past third.
  static LinearGradient? forRank(int index) => switch (index) {
        0 => gold,
        1 => silver,
        2 => bronze,
        _ => null,
      };
}

// A slow, gentle bob (up by [dy], and a small grow by [scaleTo]) that repeats.
// It stands still with "reduce animations" on, and while the app is in the
// background; its ticker stops with the route like any other.
class IdleFloat extends StatefulWidget {
  const IdleFloat({
    super.key,
    required this.child,
    this.dy = 0,
    this.scaleTo = 1,
    this.period = const Duration(seconds: 2),
  });

  final Widget child;
  final double dy;
  final double scaleTo;
  final Duration period;

  @override
  State<IdleFloat> createState() => _IdleFloatState();
}

class _IdleFloatState extends State<IdleFloat>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);
  late final Animation<double> _eased =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  bool _visible = true;
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (_reduced || !_visible) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
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
    return AnimatedBuilder(
      animation: _eased,
      // Its own repaint layer: the card is drawn once and only moved.
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final v = _reduced ? 0.0 : _eased.value;
        return Transform.translate(
          offset: Offset(0, -widget.dy * v),
          child: widget.scaleTo == 1
              ? child
              : Transform.scale(
                  scale: 1 + (widget.scaleTo - 1) * v,
                  child: child,
                ),
        );
      },
    );
  }
}

// One row of a ranked list: the place, the name (wraps, never cut off) and the
// score. The first three places sit on a medal gradient.
class LeaderboardRankRow extends StatelessWidget {
  const LeaderboardRankRow({
    super.key,
    required this.rank,
    required this.name,
    required this.valueLabel,
  });

  final int rank; // 1-based
  final String name;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final medal = FolkMedal.forRank(rank - 1);
    return FolkCard(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: FolkShape.tileRadius,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: medal,
              color: medal == null ? colors.surfaceSecondary : null,
            ),
            child: Text(
              '$rank',
              style: text.bodyStrong.copyWith(
                color: medal == null ? colors.text : FolkColors.onGradient,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: text.bodyStrong)),
          const SizedBox(width: 8),
          Text(valueLabel, style: text.chip),
        ],
      ),
    );
  }
}

// One of the top three on a podium: a medal circle, the name and the score.
// [pulse] adds the slow bob.
class LeaderboardPodiumPlace extends StatelessWidget {
  const LeaderboardPodiumPlace({
    super.key,
    required this.medal,
    required this.gradient,
    required this.name,
    required this.valueLabel,
    required this.size,
  });

  final String medal; // the medal emoji
  final LinearGradient gradient;
  final String name;
  final String valueLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return IdleFloat(
      dy: 6,
      scaleTo: 1.06,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
            child: Text(medal, style: TextStyle(fontSize: size / 2)),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size * 2.5),
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: text.bodyStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(valueLabel, textAlign: TextAlign.center, style: text.chip),
        ],
      ),
    );
  }
}

// A labelled figure on a results card (SB Class: 2.00, with its change).
class ScoreStatTile extends StatelessWidget {
  const ScoreStatTile({super.key, required this.label, required this.footer});

  final String label;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.chip.copyWith(fontSize: 13)),
          const SizedBox(height: 4),
          footer,
        ],
      ),
    );
  }
}

// The front of a winner card: a medal (Lottie, passed in), the name and the
// score, on the place's medal gradient.
class WinnerFrontCard extends StatelessWidget {
  const WinnerFrontCard({
    super.key,
    required this.width,
    required this.gradient,
    required this.medal,
    required this.name,
    required this.scoreLabel,
  });

  final double width;
  final LinearGradient gradient;
  final Widget medal;
  final String name;
  final String scoreLabel;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
      ),
      child: Column(
        children: [
          Expanded(flex: 5, child: Center(child: medal)),
          Expanded(
            flex: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.cardTitle.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: FolkColors.onGradientIconTile,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            color: FolkColors.onGradient, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            scoreLabel,
                            style: text.chip
                                .copyWith(color: FolkColors.onGradient),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The back of a winner card: the name and each score, on the violet gradient.
class WinnerBackCard extends StatelessWidget {
  const WinnerBackCard({
    super.key,
    required this.width,
    required this.name,
    required this.rows,
  });

  final double width;
  final String name;

  // (label, value text) pairs, in the order to show them.
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: FolkGradients.violet,
        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: FolkColors.onGradientIconTile,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.cardTitle.copyWith(fontSize: 18),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (final (label, value) in rows)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: FolkColors.onGradientIconTile,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: text.onGradientSmall.copyWith(
                              color: FolkColors.onGradient,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          value,
                          style: text.chip
                              .copyWith(color: FolkColors.onGradient),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Ghost rows while a leaderboard loads.
class LeaderboardGhost extends StatelessWidget {
  const LeaderboardGhost({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    // The rows are 68 dp each, so a short space (the history page under its tabs,
    // a small window) cannot hold them all. They sit in a scroll view that the
    // student cannot scroll: it gives the column all the height it wants and the
    // space simply clips what does not fit, so it never overflows at any height.
    return GhostScope(
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(FolkSpace.pagePadding),
          child: Column(
            children: [
              for (var i = 0; i < rows; i++) ...[
                const GhostPlaceholder(
                  width: double.infinity,
                  height: 68,
                  radius: FolkShape.tileRadius,
                  showBars: false,
                ),
                const SizedBox(height: FolkSpace.cardGap),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
