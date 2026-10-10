import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'GhostPlaceholder.dart';
import 'MinHeightBox.dart';

// How one calendar day is drawn. This only says how a day LOOKS; which state a
// day is in is decided by the calendar screen from its report data.
enum SadhanaDayState {
  // A report was filed for the day: green gradient circle, bold text.
  submitted,

  // A past day with no report: soft red circle, dark red text.
  missed,

  // Today, report not filed yet: filled ink circle, inverted text.
  today,

  // Today, report already filed: green gradient circle with an ink ring, so
  // today stays visible.
  todaySubmitted,

  // After today: no fill, muted text.
  future,
}

// One day of the Sadhana calendar: a 40 dp circle in its state's colours. A
// selected day gets an extra violet ring around the circle; the circle itself
// keeps its state colours.
class SadhanaDayCell extends StatefulWidget {
  const SadhanaDayCell({
    super.key,
    required this.day,
    required this.state,
    this.selected = false,
  });

  final int day;
  final SadhanaDayState state;
  final bool selected;

  static bool _isSubmitted(SadhanaDayState state) =>
      state == SadhanaDayState.submitted ||
      state == SadhanaDayState.todaySubmitted;

  @override
  State<SadhanaDayCell> createState() => _SadhanaDayCellState();

  static String _semanticState(SadhanaDayState state) => switch (state) {
        SadhanaDayState.submitted => 'submitted',
        SadhanaDayState.missed => 'missed',
        SadhanaDayState.today => 'today, not submitted yet',
        SadhanaDayState.todaySubmitted => 'today, submitted',
        SadhanaDayState.future => 'upcoming',
      };
}

class _SadhanaDayCellState extends State<SadhanaDayCell>
    with SingleTickerProviderStateMixin {
  // Plays once when a day BECOMES submitted while it is on screen (a report was
  // just filed): the green circle scales in over ~250 ms. It never plays when
  // the calendar first draws an already-submitted day.
  // At rest it sits at the end (full size); only [forward] from 0 plays it.
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );

  @override
  void didUpdateWidget(SadhanaDayCell old) {
    super.didUpdateWidget(old);
    if (!SadhanaDayCell._isSubmitted(old.state) &&
        SadhanaDayCell._isSubmitted(widget.state) &&
        !FolkMotion.reduced(context)) {
      _fill.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final day = widget.day;
    final selected = widget.selected;
    final colors = context.folk;
    final text = context.folkText;

    final bool gradient = state == SadhanaDayState.submitted ||
        state == SadhanaDayState.todaySubmitted;

    final Color? fill = switch (state) {
      SadhanaDayState.missed => colors.calendarMissedBg,
      SadhanaDayState.today => colors.primaryBg,
      _ => null,
    };

    final Color textColor = switch (state) {
      SadhanaDayState.submitted ||
      SadhanaDayState.todaySubmitted =>
        FolkColors.onGradient,
      SadhanaDayState.missed => colors.calendarMissedText,
      SadhanaDayState.today => colors.primaryFg,
      SadhanaDayState.future => colors.disabledText,
    };

    final FontWeight weight = switch (state) {
      SadhanaDayState.missed => FontWeight.w600,
      SadhanaDayState.future => FontWeight.w500,
      _ => FontWeight.w700,
    };

    return Semantics(
      selected: selected,
      label: '$day, ${SadhanaDayCell._semanticState(state)}',
      excludeSemantics: true,
      // The biggest square the cell allows, so every day is a true circle.
      child: ScaleTransition(
        scale: Tween<double>(begin: .8, end: 1)
            .animate(CurvedAnimation(parent: _fill, curve: FolkMotion.out)),
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Always 2 dp wide, transparent when not selected, so a day's circle
                // is the same size selected or not.
                border: Border.all(
                  color: selected
                      ? FolkCalendarTokens.selectedRing
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  gradient: gradient ? FolkGradients.calendarSubmitted : null,
                  border: state == SadhanaDayState.todaySubmitted
                      ? Border.all(color: colors.primaryBg, width: 2.5)
                      : null,
                ),
                child: Text(
                  '$day',
                  style: text.body.copyWith(
                    fontSize: 14,
                    fontWeight: weight,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// The key under the calendar: Submitted / Missed / Today. Visual only.
class SadhanaLegend extends StatelessWidget {
  const SadhanaLegend({super.key});

  static const List<String> _labels = ['Submitted', 'Missed', 'Today'];

  // How tall the legend is when it has [maxWidth] to lay out in: one line, or
  // more when large text makes the three items wrap. Measured with the same
  // text style, so the calendar ghost can match the real card exactly.
  static double heightFor(BuildContext context, double maxWidth) {
    // The same style the legend's Text resolves to, default text style included.
    final style = DefaultTextStyle.of(context).style.merge(context.folkText.caption);
    final scaler = MediaQuery.textScalerOf(context);
    var lines = 1;
    var x = 0.0;
    var lineHeight = 12.0;
    for (final label in _labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final width = 12 + 6 + painter.width;
      if (painter.height > lineHeight) lineHeight = painter.height;
      if (x == 0) {
        x = width;
      } else if (x + FolkSpace.lg + width <= maxWidth) {
        x += FolkSpace.lg + width;
      } else {
        lines++;
        x = width;
      }
    }
    final height = lines * lineHeight + (lines - 1) * FolkSpace.sm;
    return height < SadhanaCalendarGhost.legendHeight
        ? SadhanaCalendarGhost.legendHeight
        : height;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final style = context.folkText.caption;

    Widget item(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
            Text(label, style: style),
          ],
        );

    return MinHeightBox(
        minHeight: SadhanaCalendarGhost.legendHeight,
        alignment: Alignment.center,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: FolkSpace.lg,
          runSpacing: FolkSpace.sm,
          children: [
            item(FolkCalendarTokens.legendSubmitted, 'Submitted'),
            item(FolkCalendarTokens.legendMissed, 'Missed'),
            item(colors.primaryBg, 'Today'),
          ],
        ));
  }
}

// The ghost of the calendar card, shown until the report dates arrive. It is
// exactly the height the real card will be, so nothing moves when the calendar
// replaces it: card padding, the header (a 48 dp arrow row plus 12 dp), the
// weekday row, one row per week of the month, and the legend line.
class SadhanaCalendarGhost extends StatelessWidget {
  const SadhanaCalendarGhost({
    super.key,
    required this.month,
    required this.rowHeight,
  });

  final DateTime month;
  final double rowHeight;

  static const double cardPadding = FolkSpace.lg;
  static const double headerHeight = 48 + FolkSpace.md;
  static const double weekdayRowHeight = 30;
  static const double legendGap = 14;
  // A 12 dp caption line (Material's default text height of 1.43 applies).
  static const double legendHeight = 17.2;

  // Weeks the calendar shows for [month] (weeks start on Sunday, and a month
  // takes only the weeks it needs).
  static int weeksIn(DateTime month) {
    final offset = DateTime(month.year, month.month, 1).weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ((offset + days) / 7).ceil();
  }

  static double cardHeight(DateTime month, double rowHeight,
          {double legend = legendHeight}) =>
      cardPadding * 2 +
      headerHeight +
      weekdayRowHeight +
      weeksIn(month) * rowHeight +
      legendGap +
      legend;

  @override
  Widget build(BuildContext context) {
    return GhostPlaceholder(
      width: double.infinity,
      height: cardHeight(month, rowHeight,
          legend: SadhanaLegend.heightFor(
              context,
              MediaQuery.sizeOf(context).width -
                  2 * FolkSpace.pagePadding -
                  2 * cardPadding)),
      radius: FolkShape.cardRadius,
      showBars: false,
    );
  }
}
