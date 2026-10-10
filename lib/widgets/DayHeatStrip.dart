import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'GhostPlaceholder.dart';
import 'MinHeightBox.dart';

// The Japa screen's 30-day strip: one small square per day, darker for more
// rounds, with the day number under it. Tapping a day reports it to
// [onTapDay]. The card is at least 88 dp tall and grows with large text.
class DayHeatStrip extends StatelessWidget {
  const DayHeatStrip({
    super.key,
    required this.data,
    required this.fillFor,
    required this.onTapDay,
  });

  // Each entry: {'date': DateTime, 'rounds': int}.
  final List<Map<String, dynamic>> data;
  final Color Function(int rounds) fillFor;
  final void Function(DateTime day, int rounds) onTapDay;

  static const double minHeight = 88;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;

    return Container(
      constraints: const BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
        boxShadow: colors.cardShadows,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.map((entry) {
            final day = entry['date'] as DateTime;
            final rounds = entry['rounds'] as int;

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTapDay(day, rounds),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                  child: Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: fillFor(rounds),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: text.caption.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// The ghost of the strip: the same minimum height, growing with large text the
// way the day numbers under the squares do.
class DayHeatStripGhost extends StatelessWidget {
  const DayHeatStripGhost({super.key});

  @override
  Widget build(BuildContext context) {
    // 16 top + 8 tap padding + 30 square + 4 gap + the day-number line + 12.
    final height = 70 + ghostHeight(context, 14.3);
    return GhostPlaceholder(
      width: double.infinity,
      height: height < DayHeatStrip.minHeight ? DayHeatStrip.minHeight : height,
      radius: FolkShape.cardRadius,
      showBars: false,
    );
  }
}
