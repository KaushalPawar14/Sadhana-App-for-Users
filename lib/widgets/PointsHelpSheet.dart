import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/Commitments.dart';
import '../utils/DayScore.dart';
import '../utils/FormPoints.dart';
import '../utils/PointsHelp.dart';
import 'PrimaryButton.dart';

/// The small "i" button of a scoring question (a 44 dp target).
class PointsInfoButton extends StatelessWidget {
  const PointsInfoButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: Icon(Icons.info_outline_rounded, size: 22, color: context.folk.mutedText)),
        ),
      ),
    );
  }
}

/// Opens the help of one scoring question ([topic] null: how the total works) as a theme bottom sheet.
Future<void> showPointsHelp(BuildContext context, {required PointsTopic? topic, required ReportForm form, required Commitments commitments}) {
  final help = pointsHelp(topic, form, commitments);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
    builder: (_) => PointsHelpSheet(help: help),
  );
}

class PointsHelpSheet extends StatelessWidget {
  const PointsHelpSheet({super.key, required this.help});

  final PointsHelp help;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Container(
      key: const ValueKey('points-help-sheet'),
      decoration: BoxDecoration(color: colors.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(FolkShape.cardRadius))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 42, height: 4, decoration: BoxDecoration(color: colors.surfaceSecondary, borderRadius: BorderRadius.circular(4))),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(help.title, key: const ValueKey('points-help-title'), style: text.topBarTitle.copyWith(fontSize: 18)),
                  const SizedBox(height: 12),
                  for (final p in help.paragraphs) ...[Text(p, style: text.body), const SizedBox(height: 8)],
                  if (help.rows.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: colors.surfaceSecondary, borderRadius: BorderRadius.circular(FolkShape.tileRadius)),
                      child: Column(
                        children: [
                          for (final r in help.rows)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: Text(r.$1, style: text.body)),
                                  const SizedBox(width: 12),
                                  Text(r.$2, style: text.bodyStrong),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (help.footer != null) ...[const SizedBox(height: 12), Text(help.footer!, style: text.small)],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: PrimaryButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}

/// "Today so far: 150 points" (with its own "i"), just above Submit; repaints only when an answer changes.
class TodayTotal extends StatelessWidget {
  const TodayTotal({super.key, required this.points});

  final LiveFormPoints points;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final colors = context.folk;
    return ValueListenableBuilder<int>(
      valueListenable: points.tick,
      builder: (context, _, __) => Container(
        key: const ValueKey('today-total'),
        padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(FolkShape.tileRadius)),
        child: Row(
          children: [
            Expanded(child: Text(points.totalText, key: const ValueKey('today-total-text'), style: text.bodyStrong)),
            PointsInfoButton(
              label: 'How the points add up',
              onPressed: () => showPointsHelp(context, topic: null, form: points.form, commitments: points.commitments),
            ),
          ],
        ),
      ),
    );
  }
}
