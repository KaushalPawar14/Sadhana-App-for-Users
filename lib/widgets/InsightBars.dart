import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/InsightsData.dart';

// One bar per day. Weekly: seven wide rounded bars, a letter under each
// (M T W T F S S). Monthly: one thin rounded bar per day with a day number under
// only a few of them (1, 5, 10 ...), so 31 bars stay light at 360 dp. Today's bar
// is the saffron one, the rest soft violet; a day with no report has no bar.
//
// [chartHeight] is the whole chart (bars and labels); the labels take what their
// text needs at the student's text size and the bars take the rest.
class InsightBars extends StatelessWidget {
  const InsightBars({
    super.key,
    required this.bars,
    required this.scaleMax,
    required this.monthly,
    required this.chartHeight,
    this.semanticLabel,
  });

  final List<BarPoint> bars;
  final double scaleMax;
  final bool monthly;
  final double chartHeight;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final labelStyle = text.caption;
    final scaler = MediaQuery.textScalerOf(context);
    final labelHeight = scaler.scale(12) * 1.4 + 8;
    final barsHeight = (chartHeight - labelHeight).clamp(40.0, chartHeight);

    Widget slot(BarPoint b) {
      final v = b.value;
      Widget bar = const SizedBox.shrink();
      if (v != null && !b.isFuture) {
        final frac = (v / scaleMax).clamp(0.0, 1.0);
        // A zero is still drawn, as a small stub, so "missed" can be told from
        // "no report".
        final h = (frac * barsHeight).clamp(5.0, barsHeight);
        bar = Container(
          width: monthly ? null : 30,
          height: h,
          margin: monthly ? const EdgeInsets.symmetric(horizontal: 1.5) : null,
          decoration: BoxDecoration(
            gradient: b.isToday ? FolkGradients.insightToday : null,
            color: b.isToday ? null : colors.chartBarInactive,
            borderRadius: BorderRadius.circular(monthly ? 4 : 12),
          ),
        );
      }
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: barsHeight,
              child: Align(alignment: Alignment.bottomCenter, child: bar),
            ),
            SizedBox(
              height: labelHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                // A label may be wider than its thin slot; it centres on it.
                child: OverflowBox(
                  minWidth: 0,
                  maxWidth: 48,
                  child: Text(
                    b.label,
                    maxLines: 1,
                    softWrap: false,
                    style: labelStyle,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      container: semanticLabel != null,
      child: SizedBox(
        height: chartHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [for (final b in bars) slot(b)],
        ),
      ),
    );
  }
}
