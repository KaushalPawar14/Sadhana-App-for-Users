import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/InsightsData.dart';

// The Weekly / Monthly switch at the top of Insights: a white (dark: surface)
// pill with the chosen side filled in the ink colour. Each side is a full
// 48 dp-high touch target.
class InsightsPeriodSwitch extends StatelessWidget {
  const InsightsPeriodSwitch({
    super.key,
    required this.period,
    required this.onChanged,
  });

  final InsightPeriod period;
  final ValueChanged<InsightPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    Widget side(InsightPeriod p, String label) {
      final selected = p == period;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          onTap: () => onChanged(p),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: FolkMotion.of(context, const Duration(milliseconds: 180)),
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? colors.primaryBg : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.folkText.chip.copyWith(
                    color: selected ? colors.primaryFg : colors.mutedText),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: colors.iconShadows,
      ),
      child: Row(
        children: [
          side(InsightPeriod.weekly, 'Weekly'),
          side(InsightPeriod.monthly, 'Monthly'),
        ],
      ),
    );
  }
}
