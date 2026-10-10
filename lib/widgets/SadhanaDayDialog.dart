import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkDialog.dart';
import 'GhostPlaceholder.dart';
import 'RoundIconButton.dart';

// What a submitted day's report says, as a dialog: the date at the top with a
// close (X) button, then one clean row per stat (an icon tile, the label, the
// value). The X, a tap outside and the system back button all close it.
//
// [load] is the one read the Calendar already made for a tapped day
// (`fetchMergedDateReport`); it runs once, here. While it runs the rows are
// ghosts; with no report (or a failed read) a friendly line takes their place.
class SadhanaDayDialog extends StatefulWidget {
  const SadhanaDayDialog({super.key, required this.date, required this.load});

  final DateTime date;
  final Future<Map<String, dynamic>?> Function() load;

  static Future<void> show(
    BuildContext context, {
    required DateTime date,
    required Future<Map<String, dynamic>?> Function() load,
  }) =>
      showDialog<void>(
        context: context,
        animationStyle:
            FolkMotion.reduced(context) ? AnimationStyle.noAnimation : null,
        builder: (_) => SadhanaDayDialog(date: date, load: load),
      );

  @override
  State<SadhanaDayDialog> createState() => _SadhanaDayDialogState();
}

class _SadhanaDayStat {
  const _SadhanaDayStat(this.label, this.value, this.icon);
  final String label;
  final Object? value;
  final IconData icon;
}

class _SadhanaDayDialogState extends State<SadhanaDayDialog> {
  late final Future<Map<String, dynamic>?> _future = widget.load();

  // The same stats, in the same order, with the same labels as the card this
  // replaces (the emoji left off).
  List<_SadhanaDayStat> _statsOf(Map<String, dynamic> data) => [
        if (data.containsKey('chantRounds'))
          _SadhanaDayStat('Chanting Rounds', data['chantRounds'], Icons.bubble_chart),
        if (data.containsKey('bookReading'))
          _SadhanaDayStat('Book Reading', data['bookReading'], Icons.menu_book),
        if (data.containsKey('classHearing'))
          _SadhanaDayStat('Class Hearing', data['classHearing'], Icons.headphones),
        if (data.containsKey('dailyServices'))
          _SadhanaDayStat('Daily Services', data['dailyServices'], Icons.volunteer_activism),
        if (data.containsKey('templeEntry'))
          _SadhanaDayStat('Temple Entry', data['templeEntry'], Icons.temple_hindu),
        if (data.containsKey('finishTiming'))
          _SadhanaDayStat('Finish Timing', data['finishTiming'], Icons.access_time),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Dialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: FolkDialog.shape(),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: FolkSpace.pagePadding, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sadhana report', style: text.small),
                      const SizedBox(height: 2),
                      Semantics(
                        header: true,
                        child: Text(
                          DateFormat('EEEE, d MMM yyyy').format(widget.date),
                          style: text.topBarTitle.copyWith(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RoundIconButton(
                  icon: Icons.close_rounded,
                  semanticLabel: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const _GhostRows();
                    }
                    final data = snapshot.data;
                    final stats = snapshot.hasError || data == null || data.isEmpty
                        ? const <_SadhanaDayStat>[]
                        : _statsOf(data);
                    if (stats.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            "There are no details for this day.",
                            textAlign: TextAlign.center,
                            style: text.small,
                          ),
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [for (final s in stats) _StatRow(stat: s)],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stat});

  final _SadhanaDayStat stat;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(stat.icon, color: colors.text, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(stat.label, style: text.bodyStrong)),
          const SizedBox(width: 8),
          Text(stat.value.toString(), style: text.bodyStrong),
        ],
      ),
    );
  }
}

// Three ghost rows, the same size as the real ones.
class _GhostRows extends StatelessWidget {
  const _GhostRows();

  @override
  Widget build(BuildContext context) {
    return GhostScope(
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: GhostPlaceholder(
                  width: double.infinity, height: 42, radius: 14, showBars: false),
            ),
        ],
      ),
    );
  }
}
