import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/LeaderboardData.dart';
import '../utils/ScoreBreakdown.dart';
import 'FolkCard.dart';
import 'GhostPlaceholder.dart';
import 'ScoreWidgets.dart';

/// "+12.3%" / "-4.0%" / "0%" with its arrow: the change against the previous period. [value] null = still loading.
class ChangeChip extends StatelessWidget {
  const ChangeChip({super.key, required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final v = value;
    if (v == null) {
      return const SizedBox(width: 12, height: 12, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.transparent)));
    }
    final IconData icon;
    final Color color;
    final String label;
    if (v > 0.05) {
      icon = Icons.arrow_upward;
      color = FolkCalendarTokens.legendSubmitted;
      label = '+${v.toStringAsFixed(1)}%';
    } else if (v < -0.05) {
      icon = Icons.arrow_downward;
      color = FolkCalendarTokens.legendMissed;
      label = '-${v.abs().toStringAsFixed(1)}%';
    } else {
      icon = Icons.remove;
      color = colors.mutedText;
      label = '0%';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(label, style: text.caption.copyWith(fontSize: 12, fontWeight: FontWeight.bold, color: colors.text)),
      ],
    );
  }
}

/// The student's own points for a period and how they compare with the previous one (this is the old Weekly /
/// Monthly Performance card, moved onto the Leaderboard's Scores tab): the total, its change, each item's points
/// (already including the day's multipliers, so they add up to the total) with their own change, and the average
/// multipliers. [data] is the student's `competition` document (null: no points yet); [changes] the percentage
/// changes against the previous period (null while they load).
class OwnScoreCard extends StatelessWidget {
  const OwnScoreCard({super.key, required this.period, required this.data, required this.changes, required this.hostelLocalite});

  final BoardPeriod period;
  final Map<String, dynamic>? data;
  final Map<String, double>? changes;
  final bool hostelLocalite;

  double _n(String field) {
    final v = data?['${period.key}.$field'];
    return v is num ? v.toDouble() : 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final p = period.key;

    Widget chip(String label, String field, {bool isInt = false}) {
      final value = isInt ? _n(field).toInt().toString() : _n(field).toStringAsFixed(2);
      return ScoreStatTile(label: '$label: $value', footer: ChangeChip(value: changes == null ? null : (changes!['$p.$field'] ?? 0)));
    }

    final lines = multiplierLines(data ?? const {}, p, hostelLocalite: hostelLocalite);
    return FolkCard(
      key: const ValueKey('own-score-card'),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('Your points ${period.thisPeriod}', style: text.topBarTitle),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_n('total_score').toStringAsFixed(2), key: const ValueKey('own-total'), style: text.stat.copyWith(color: colors.text)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChangeChip(value: changes == null ? null : (changes!['$p.total_score'] ?? 0)),
                      const SizedBox(width: 6),
                      Text('vs last ${period == BoardPeriod.weekly ? 'week' : 'month'}', style: text.caption),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              chip('💻 SB Class', 'bhagavatam_class'),
              if (!hostelLocalite) chip('🛕 Service', 'daily_service'),
              chip('📿 Chanting', 'chanting_rounds'),
              chip('📚 Reading', 'book_reading'),
              if (!hostelLocalite) chip('🎧 Lecture', 'extra_lecture'),
              chip('📅 Days', 'days_count', isInt: true),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(FolkShape.tileRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kBreakdownCaption, style: text.caption),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (final line in lines) Text('${line.label} x ${line.value}', style: text.bodyStrong),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's ghost while the student's points load.
class OwnScoreCardGhost extends StatelessWidget {
  const OwnScoreCardGhost({super.key});

  @override
  Widget build(BuildContext context) =>
      const GhostPlaceholder(width: double.infinity, height: 280, radius: FolkShape.cardRadius, showBars: false);
}
