import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/InsightsData.dart';
import 'FolkCard.dart';
import 'GhostPlaceholder.dart';
import 'InsightBars.dart';
import 'MinHeightBox.dart' show ghostHeight;

// The Insights graph card: one graph at a time, swiped sideways, looping for
// good (the last graph is followed by the first). Under the card the current
// graph's name is centred, with the previous and next names faint on either side;
// tapping one of them goes there.
//
// [reports] is null while the student's reports are still loading (a ghost of
// the same size); with a graph but no data in the period, a friendly line of the
// same size. Everything is the student's own data.
class InsightsGraphCarousel extends StatefulWidget {
  const InsightsGraphCarousel({
    super.key,
    required this.graphs,
    required this.period,
    required this.reports,
    required this.today,
  });

  final List<InsightGraphSpec> graphs;
  final InsightPeriod period;
  final Reports? reports;
  final DateTime today;

  @override
  State<InsightsGraphCarousel> createState() => _InsightsGraphCarouselState();
}

// Pages are numbered round a big middle so a swipe works both ways for ever.
const int _kLoops = 1000;

class _InsightsGraphCarouselState extends State<InsightsGraphCarousel> {
  late PageController _controller;
  int _page = 0;

  int get _n => widget.graphs.length;
  int get _index => _n == 0 ? 0 : _page % _n;

  @override
  void initState() {
    super.initState();
    _page = _n * _kLoops;
    _controller = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(InsightsGraphCarousel old) {
    super.didUpdateWidget(old);
    if (old.graphs.length != _n) {
      // The list of graphs changed size (reports arrived): stay on the same
      // graph if it is still there, else start again.
      final id = old.graphs.isEmpty ? null : old.graphs[_page % old.graphs.length].id;
      final at = id == null ? -1 : widget.graphs.indexWhere((g) => g.id == id);
      _page = _n * _kLoops + (at < 0 ? 0 : at);
      _controller.dispose();
      _controller = PageController(initialPage: _page);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final duration = FolkMotion.of(context, const Duration(milliseconds: 320));
    if (duration == Duration.zero) {
      // "Reduce animations": go there at once.
      _controller.jumpToPage(_page + delta);
      return;
    }
    _controller.animateToPage(
      _page + delta,
      duration: duration,
      curve: FolkMotion.standard,
    );
  }

  // The card's size, from the student's text size: heading, title, chart.
  double _chartHeight(BuildContext context) => 176;

  double _slideHeight(BuildContext context) =>
      ghostHeight(context, 11 * 1.6) +
      6 +
      ghostHeight(context, 20 * 1.5) +
      14 +
      _chartHeight(context);

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final colors = context.folk;

    if (_n == 0) {
      return FolkCard(
        padding: const EdgeInsets.all(18),
        child: SizedBox(
          height: _slideHeight(context),
          child: Center(
            child: Text(
              'Your graphs will appear here after your first Sadhana report.',
              textAlign: TextAlign.center,
              style: text.small,
            ),
          ),
        ),
      );
    }

    final names = [for (final g in widget.graphs) g.name];
    final prev = names[(_index - 1 + _n) % _n];
    final next = names[(_index + 1) % _n];

    Widget side(String label, int delta, Alignment align) => Expanded(
          child: Semantics(
            button: true,
            label: delta < 0 ? 'Previous graph: $label' : 'Next graph: $label',
            excludeSemantics: true,
            onTap: () => _go(delta),
            child: InkWell(
              onTap: () => _go(delta),
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: FolkShape.touchTarget),
                child: Align(
                  alignment: align,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.small.copyWith(
                        color: colors.mutedText.withValues(alpha: .6)),
                  ),
                ),
              ),
            ),
          ),
        );

    return Column(
      children: [
        FolkCard(
          padding: const EdgeInsets.all(18),
          child: SizedBox(
            height: _slideHeight(context),
            child: PageView.builder(
              // A new set of graphs is a new PageView (its own controller).
              key: ValueKey(widget.graphs.map((g) => g.id).join(',')),
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p),
              itemCount: _n * _kLoops * 2,
              itemBuilder: (context, page) => _Slide(
                graph: widget.graphs[page % _n],
                period: widget.period,
                reports: widget.reports,
                today: widget.today,
                chartHeight: _chartHeight(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (_n > 1)
              side(prev, -1, Alignment.centerLeft)
            else
              const Spacer(),
            Expanded(
              flex: 2,
              child: Semantics(
                header: true,
                child: Text(
                  names[_index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.bodyStrong,
                ),
              ),
            ),
            if (_n > 1)
              side(next, 1, Alignment.centerRight)
            else
              const Spacer(),
          ],
        ),
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.graph,
    required this.period,
    required this.reports,
    required this.today,
    required this.chartHeight,
  });

  final InsightGraphSpec graph;
  final InsightPeriod period;
  final Reports? reports;
  final DateTime today;
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final isPie = graph.kind == InsightKind.pie;
    final periodWord = period == InsightPeriod.weekly ? 'week' : 'month';

    final String? stat = (reports == null || isPie)
        ? null
        : statFor(graph: graph, period: period, reports: reports!, today: today);

    Widget chart;
    if (reports == null) {
      chart = GhostPlaceholder(
          width: double.infinity, height: chartHeight, showBars: false);
    } else if (isPie) {
      chart = _Pie(counts: pieCounts(reports!, graph.field), height: chartHeight);
    } else {
      final bars = barsFor(
          graph: graph, period: period, reports: reports!, today: today);
      if (!hasAnyValue(bars)) {
        chart = SizedBox(
          height: chartHeight,
          child: Center(
            child: Text(
              'No ${graph.title.toLowerCase()} reported this $periodWord yet.',
              textAlign: TextAlign.center,
              style: text.small,
            ),
          ),
        );
      } else {
        chart = InsightBars(
          bars: bars,
          scaleMax: scaleMax(graph, bars),
          monthly: period == InsightPeriod.monthly,
          chartHeight: chartHeight,
          semanticLabel: _summary(graph, bars, periodWord),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (isPie
                  ? 'ALL YOUR REPORTS'
                  : period == InsightPeriod.weekly
                      ? 'WEEKLY PERFORMANCE'
                      : 'MONTHLY PERFORMANCE'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.label,
        ),
        const SizedBox(height: 6),
        // The title on the left, one small stat on the right (a bar graph with
        // data only). The title gives way first: it ellipsizes, and the stat is
        // capped to its own width so nothing overflows at any text size.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(graph.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: text.topBarTitle),
            ),
            if (stat != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  stat,
                  key: const ValueKey('graph-stat'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: text.caption,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        chart,
      ],
    );
  }

  String _summary(InsightGraphSpec g, List<BarPoint> bars, String periodWord) {
    String fmt(double v) {
      if (g.kind == InsightKind.time) {
        final m = v.toInt();
        return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      }
      return v.toInt().toString();
    }

    final parts = [
      for (final b in bars)
        if (b.value != null) '${b.day.day}: ${fmt(b.value!)}',
    ];
    return '${g.title}, this $periodWord. ${parts.join(', ')}';
  }
}

// The old Graphical Analysis pie: Fully / Partial / Missed shares of every
// report that has the field, the same colours and percentages.
class _Pie extends StatelessWidget {
  const _Pie({required this.counts, required this.height});

  final Map<String, int> counts;
  final double height;

  static const Color _good = FolkCalendarTokens.legendSubmitted;
  static const Color _mid = Color(0xFFFFC978);
  static const Color _late = FolkCalendarTokens.legendMissed;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return SizedBox(
        height: height,
        child: Center(
            child: Text('No reports to show yet.',
                textAlign: TextAlign.center, style: text.small)),
      );
    }
    Color colorOf(String k) => k == 'Fully' ? _good : (k == 'Partial' ? _mid : _late);
    final sections = [
      for (final e in counts.entries)
        if (e.value > 0)
          PieChartSectionData(
            color: colorOf(e.key),
            value: e.value.toDouble(),
            title: '${(e.value / total * 100).toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: FolkColors.onGradient,
            ),
          ),
    ];
    return Semantics(
      label: 'Fully ${counts['Fully']}, partial ${counts['Partial']}, missed ${counts['Missed']}',
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Expanded(
              child: PieChart(
                PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 0),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final k in ['Fully', 'Partial', 'Missed'])
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: colorOf(k), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(k, style: text.caption),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
