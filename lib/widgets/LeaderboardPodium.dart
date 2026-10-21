import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../utils/LeaderboardData.dart';
import '../theme/FolkTokens.dart' show FolkMotion;
import 'RiseIn.dart';
import 'ScoreWidgets.dart' show FolkMedal;

/// An Olympic-style podium for the first three places: 2nd on the left, 1st in the middle (the tallest block),
/// 3rd on the right. Each place has its medal, the name (wraps, never cut off), the points, and a block with the
/// place number in the medal's own gradient. The viewer's own place is outlined. With fewer than three students the
/// missing places are left out (a lone winner stands in the middle).
///
/// MOTION (once, when the podium is first built; never replayed by a rebuild or by coming back to the page; static with
/// "reduce animations"): the bars RISE from the bottom of their slots, slowly and smoothly, 3rd then 2nd then 1st; each
/// place's medal, name and points then fade in after its own bar. Only a transform moves, so nothing around it jumps.
class LeaderboardPodium extends StatefulWidget {
  const LeaderboardPodium({super.key, required this.top, this.myName});

  /// The first (up to) three students, best first.
  final List<RankedStudent> top;
  final String? myName;

  static const double _firstBlock = 96;
  static const double _secondBlock = 72;
  static const double _thirdBlock = 52;

  /// The whole choreography: the 3rd bar starts at 0, the 2nd one stagger later, the 1st two staggers later; the info of
  /// each place fades in when its bar is up.
  static Duration get total => RiseMotion.barStagger * 2 + RiseMotion.bar + RiseMotion.info;

  @override
  State<LeaderboardPodium> createState() => _LeaderboardPodiumState();
}

class _LeaderboardPodiumState extends State<LeaderboardPodium> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: LeaderboardPodium.total);
  bool _started = false;

  @override
  bool get wantKeepAlive => true;

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

  /// The slice of the whole choreography between [from] and [to] (milliseconds), as its own 0..1 animation.
  Animation<double> _slice(int from, int to, Curve curve) {
    final total = LeaderboardPodium.total.inMilliseconds;
    return CurvedAnimation(parent: _controller, curve: Interval(from / total, to / total, curve: curve));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final top = widget.top;
    if (top.isEmpty) return const SizedBox.shrink();
    // left to right: 2nd, 1st, 3rd
    final order = <int>[if (top.length > 1) 1, 0, if (top.length > 2) 2];
    final stagger = RiseMotion.barStagger.inMilliseconds;
    final bar = RiseMotion.bar.inMilliseconds;
    final info = RiseMotion.info.inMilliseconds;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: () {
                // 3rd starts first, then 2nd, then 1st
                final start = (2 - i) * stagger;
                return _Place(
                  place: i,
                  student: top[i],
                  me: isMe(top[i].name, widget.myName),
                  bar: _slice(start, start + bar, RiseMotion.bars),
                  info: _slice(start + bar, start + bar + info, RiseMotion.rise),
                );
              }(),
            ),
          ),
      ],
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.place, required this.student, required this.me, required this.bar, required this.info});

  final int place; // 0-based
  final RankedStudent student;
  final bool me;

  /// 0 -> 1: the bar rises from the bottom of its slot. Then [info] (0 -> 1): the medal, name and points fade in.
  final Animation<double> bar;
  final Animation<double> info;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final medal = FolkMedal.forRank(place)!;
    final block = [LeaderboardPodium._firstBlock, LeaderboardPodium._secondBlock, LeaderboardPodium._thirdBlock][place];
    final emoji = ['🥇', '🥈', '🥉'][place];
    return Semantics(
      label: '${place + 1}${['st', 'nd', 'rd'][place]} place, ${student.name}, ${pointsText(student.points)}${me ? ', you' : ''}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // The medal, name and points fade in (and settle a few dp) once their bar is up.
          FadeTransition(
            key: ValueKey('podium-info-${place + 1}'),
            opacity: info,
            child: AnimatedBuilder(
              animation: info,
              builder: (context, child) => Transform.translate(offset: Offset(0, (1 - info.value) * 8), child: child),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: medal),
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    student.name,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyStrong.copyWith(fontWeight: me ? FontWeight.w800 : null),
                  ),
                  const SizedBox(height: 2),
                  Text(pointsText(student.points), textAlign: TextAlign.center, style: text.chip),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // The bar keeps its full size in the layout; it rises from the bottom edge of its own box (clipped there).
          ClipRect(
            child: AnimatedBuilder(
              animation: bar,
              builder: (context, child) => Transform.translate(offset: Offset(0, (1 - bar.value) * block), child: child),
              child: Container(
                key: ValueKey('podium-block-${place + 1}'),
                height: block,
                width: double.infinity,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  gradient: medal,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: me ? Border.all(color: colors.text, width: 2.5) : null,
                ),
                child: Text('${place + 1}', style: text.stat.copyWith(color: FolkColors.onGradient, fontSize: 26)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
