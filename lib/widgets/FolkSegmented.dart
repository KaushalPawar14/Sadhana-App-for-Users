import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/UnseenDot.dart';
import 'PressScale.dart';

class FolkSegment<T> {
  const FolkSegment({required this.value, required this.label, this.dot = false});

  final T value;
  final String label;

  /// The green results "new" dot beside the label (only the Leaderboard's Monthly segment uses it).
  final bool dot;
}

// A small segmented control: a soft track with one ink pill on the selected
// option (Light / Dark / Auto). Each option is 44 dp tall inside a 2 dp track,
// so the whole control is 48 dp tall. The pill slides between options.
class FolkSegmented<T> extends StatelessWidget {
  const FolkSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  }) : assert(segments.length >= 2);

  final List<FolkSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  static const double _optionHeight = 44;
  static const double _trackPadding = 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final duration = FolkMotion.of(context, FolkMotion.navMorph);
    final selectedIndex = segments.indexWhere((s) => s.value == value);

    return Container(
      padding: const EdgeInsets.all(_trackPadding),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius:
            BorderRadius.circular((_optionHeight + _trackPadding * 2) / 2),
      ),
      child: Stack(
        children: [
          // The sliding pill sits behind the labels.
          Positioned.fill(
            child: AnimatedAlign(
              duration: duration,
              curve: FolkMotion.standard,
              alignment: Alignment(
                segments.length == 1
                    ? 0
                    : -1 +
                        2 *
                            (selectedIndex < 0 ? 0 : selectedIndex) /
                            (segments.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / segments.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selectedIndex < 0
                        ? Colors.transparent
                        : colors.primaryBg,
                    borderRadius: BorderRadius.circular(_optionHeight / 2),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final segment in segments)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: segment.value == value,
                    label: segment.label,
                    excludeSemantics: true,
                    onTap: () => onChanged(segment.value),
                    child: PressScale(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(segment.value),
                        child: SizedBox(
                          height: _optionHeight,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: duration,
                              style: text.chip.copyWith(
                                color: segment.value == value
                                    ? colors.primaryFg
                                    : colors.mutedText,
                              ),
                              child: UnseenBadge(
                                show: segment.dot,
                                offset: const Offset(-9, -3),
                                dotSize: 8,
                                child: Text(
                                  segment.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
