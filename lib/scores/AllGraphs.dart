import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/SadhanaReportSource.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';

// Chart colours. Traffic-light meaning is kept (on time / late / very late;
// fully / partially / missed) in the app's own tones; the data itself is violet.
const Color _kGood = FolkCalendarTokens.legendSubmitted;
const Color _kMid = Color(0xFFFFC978);
const Color _kLate = FolkCalendarTokens.legendMissed;
const Color _kData = FolkCalendarTokens.selectedRing;

class AllGraph extends StatefulWidget {
  final String? username;
  const AllGraph({super.key, required this.username});

  @override
  State<AllGraph> createState() => _ChantingGraphState();
}

class _ChantingGraphState extends State<AllGraph> {

  bool loading = true;
  List<int> chantingRounds = [];
  List<int> bookReadingData = [];
  List<int> templeEntryData = [];
  List<int> finishTimingData = [];
  Map<String, int> classHearingCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};
  Map<String, int> dailyServicesCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};

  /// Every date-doc for this student, merged across both residence
  /// collections — Master Task 2026-09-11, so history filed before a
  /// residence switch still counts here. Fetched once and shared by all
  /// three processing methods below (Part 3 item 4 — this was already three
  /// separate reads of the same subcollection before this task; merging by
  /// re-reading it three times per collection would have made that worse,
  /// so it is now one shared fetch feeding all three instead). See
  /// utils/SadhanaReportSource.dart's own header for the one-per-date rule.
  Map<String, Map<String, dynamic>> _mergedReports = {};

  @override
  void initState() {
    super.initState();
    _loadAndProcess();
  }

  Future<void> _loadAndProcess() async {
    setState(() => loading = true);
    try {
      _mergedReports =
          await fetchMergedDateReports((widget.username ?? '').trim());
      _processChantingData();
      _processTempleEntryData();
      _processPieChartData();
    } catch (e) {
      print("Error fetching data: $e");
      chantingRounds = [];
      bookReadingData = [];
      templeEntryData = [];
      finishTimingData = [];
    }
    if (mounted) setState(() => loading = false);
  }

  void _processPieChartData() {
    // Reset counts
    classHearingCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};
    dailyServicesCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};

    for (final data in _mergedReports.values) {
      // 🔹 classHearing
      if (data.containsKey('classHearing')) {
        final val = data['classHearing'] as int;
        if (val == 2) classHearingCount['Fully'] = classHearingCount['Fully']! + 1;
        else if (val == 1) classHearingCount['Partial'] = classHearingCount['Partial']! + 1;
        else classHearingCount['Missed'] = classHearingCount['Missed']! + 1;
      }

      // 🔹 dailyServices
      if (data.containsKey('dailyServices')) {
        final val = data['dailyServices'] as int;
        if (val == 2) dailyServicesCount['Fully'] = dailyServicesCount['Fully']! + 1;
        else if (val == 1) dailyServicesCount['Partial'] = dailyServicesCount['Partial']! + 1;
        else dailyServicesCount['Missed'] = dailyServicesCount['Missed']! + 1;
      }
    }
  }

  void _processTempleEntryData() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 29));
    final dateFormat = DateFormat('dd-MM-yyyy');

    Map<String, String> templeMap = {};
    Map<String, String> finishMap = {};

    for (final entry in _mergedReports.entries) {
      final dateString = entry.key;
      final data = entry.value;

      if (data.containsKey('templeEntry')) {
        templeMap[dateString] = data['templeEntry'] as String;
      }

      if (data.containsKey('finishTiming')) {
        finishMap[dateString] = data['finishTiming'] as String;
      }
    }

    List<int> templeList = [];
    List<int> finishList = [];

    for (int i = 0; i < 30; i++) {
      final day = thirtyDaysAgo.add(Duration(days: i));
      final dayKey = dateFormat.format(day);

      if (templeMap.containsKey(dayKey)) {
        final timeStr = templeMap[dayKey]!; // "HH:mm"
        final parts = timeStr.split(":");
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;
          final totalMinutes = hour * 60 + minute;
          templeList.add(totalMinutes);
        }
      }

      if (finishMap.containsKey(dayKey)) {
        final timeStr = finishMap[dayKey]!; // "HH:mm"
        final parts = timeStr.split(":");
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;
          final totalMinutes = hour * 60 + minute;
          finishList.add(totalMinutes);
        }
      }
    }

    templeEntryData = templeList;
    finishTimingData = finishList;
  }

  void _processChantingData() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 29));
    final dateFormat = DateFormat('dd-MM-yyyy');

    Map<String, int> roundsMap = {};
    Map<String, int> readingMap = {}; // 🔹 New map for reading

    for (final entry in _mergedReports.entries) {
      final dateString = entry.key;
      final data = entry.value;

      if (data.containsKey('chantRounds')) {
        roundsMap[dateString] = data['chantRounds'] as int;
      }

      if (data.containsKey('bookReading')) {
        readingMap[dateString] = data['bookReading'] as int; // 🔹 Get reading
      }
    }

    List<int> roundsList = [];
    List<int> readingList = []; // 🔹 New list for reading

    for (int i = 0; i < 30; i++) {
      final day = thirtyDaysAgo.add(Duration(days: i));
      final dayKey = dateFormat.format(day);

      if (roundsMap.containsKey(dayKey)) {
        roundsList.add(roundsMap[dayKey]!); // Chanting Data
      }

      if (readingMap.containsKey(dayKey)) {
        readingList.add(readingMap[dayKey]!); // 🔹 Reading data
      }
    }

    chantingRounds = roundsList;
    bookReadingData = readingList; // 🔹 Set reading state
  }

  // A titled card holding one chart and what goes with it.
  Widget _graphCard({String? title, required Widget child}) {
    final text = context.folkText;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: FolkSpace.pagePadding, vertical: 8),
      child: FolkCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title, style: text.topBarTitle),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }

  // The chart area while the reports load.
  Widget _chartGhost() => const GhostPlaceholder(
        width: double.infinity,
        height: 240,
        showBars: false,
      );

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: widget.username ?? "",
      body: GhostScope(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 12, bottom: 32),
          child: Column(
            children: [
              _graphCard(
                title: 'Chanting 📿',
                child: loading
                    ? _chartGhost()
                    : Column(children: [
                        SizedBox(
                          height: 240,
                          child: MyLineChart(chantingRounds: chantingRounds),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Total: ${chantingRounds.fold(0, (a, b) => a + b)} rounds',
                          style: text.bodyStrong,
                        ),
                      ]),
              ),

              // 🔸 Reading Chart
              _graphCard(
                title: 'Reading 📖',
                child: loading
                    ? _chartGhost()
                    : Column(
                        children: [
                          SizedBox(
                            height: 240,
                            child: MyLineChart(chantingRounds: bookReadingData),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            bookReadingData.isEmpty
                                ? 'No Data'
                                : 'Average: ${(bookReadingData.reduce((a, b) => a + b) / bookReadingData.length).toStringAsFixed(1)} mins',
                            style: text.bodyStrong,
                          ),
                        ],
                      ),
              ),
              _graphCard(
                title: 'Temple Entry ⛪',
                child: loading
                    ? _chartGhost()
                    : TempleEntryChart(data: templeEntryData),
              ),
              _graphCard(
                title: 'Chanting Finish Timing ⏰',
                child: loading
                    ? _chartGhost()
                    : FinishTimingChart(data: finishTimingData),
              ),
              _graphCard(
                child: MyPieChart(data: classHearingCount, title: "Class Hearing 🎧"),
              ),
              _graphCard(
                child: MyPieChart(data: dailyServicesCount, title: "Daily Services 🛐"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyPieChart extends StatelessWidget {
  final Map<String, int> data;
  final String title;

  const MyPieChart({super.key, required this.data, required this.title});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Center(child: Text("No data"));

    final sections = data.entries.map((e) {
      Color color;
      if (e.key == 'Fully') color = _kGood;
      else if (e.key == 'Partial') color = _kMid;
      else color = _kLate;

      final percent = (e.value / total * 100);
      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${percent.toStringAsFixed(1)}%',
        radius: 75,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: FolkColors.onGradient,
        ),
      );
    }).toList();
    return Column(
      children: [
        Text(title, style: context.folkText.topBarTitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 250,
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
              centerSpaceRadius: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 16,
          runSpacing: 8,
          children: [
            LegendItem(color: _kGood, text: "Fully"),
            LegendItem(color: _kMid, text: "Partial"),
            LegendItem(color: _kLate, text: "Missed"),
          ],
        ),
      ],
    );
  }
}

class FinishTimingChart extends StatelessWidget {
  final List<int> data;
  const FinishTimingChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final barGroups = List.generate(data.length, (index) {
      // Cap bars at max 10:00 PM (1320 minutes)
      final cappedValue = data[index] > 1320 ? 1320 : data[index];

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: cappedValue.toDouble(),
            gradient: _barGradient,
          ),
        ],
      );
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              barGroups: barGroups,
              titlesData: FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                    y: 780, color: _kGood, strokeWidth: 2), // 1:00 PM
                HorizontalLine(
                    y: 960, color: _kMid, strokeWidth: 2), // 4:00 PM
                HorizontalLine(
                    y: 1320, color: _kLate, strokeWidth: 2), // 10:00 PM
              ]),
              alignment: BarChartAlignment.spaceAround,
              maxY: 1320, // ✅ Cap Y axis at 10:00 PM
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ✅ Legend
        const Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 16,
          runSpacing: 8,
          children: [
            LegendItem(color: _kGood, text: "1:00 PM"),
            LegendItem(color: _kMid, text: "4:00 PM"),
            LegendItem(color: _kLate, text: "10:00 PM"),
          ],
        )
      ],
    );
  }
}

class TempleEntryChart extends StatelessWidget {
  final List<int> data;
  const TempleEntryChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final barGroups = List.generate(data.length, (index) {
      // Cap each bar at 12:00 pm (720 mins)
      final cappedValue = data[index] > 600 ? 600 : data[index];

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: cappedValue.toDouble(),
            gradient: _barGradient,
          ),
        ],
      );
    });

    // Always cap chart’s Y-axis at 12:00 pm (720 minutes)
    const double maxY = 600;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              barGroups: barGroups,
              titlesData: FlTitlesData(show: false), // Hide titles
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                    y: 330, color: _kGood, strokeWidth: 2), // 5:30
                HorizontalLine(
                    y: 390, color: _kMid, strokeWidth: 2), // 6:30
                HorizontalLine(
                    y: 450, color: _kLate, strokeWidth: 2), // 7:30
              ]),
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Legend Section
        const Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 16,
          runSpacing: 8,
          children: [
            LegendItem(color: _kGood, text: "5:30 AM"),
            LegendItem(color: _kMid, text: "6:30 AM"),
            LegendItem(color: _kLate, text: "7:30 AM"),
          ],
        )
      ],
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const LegendItem({super.key, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: context.folkText.small.copyWith(fontSize: 14)),
      ],
    );
  }
}

class MyLineChart extends StatelessWidget {
  final List<int> chantingRounds;

  const MyLineChart({super.key, required this.chantingRounds});

  @override
  Widget build(BuildContext context) {
    if (chantingRounds.isEmpty) {
      return const Center(child: Text("No data"));
    }

    // Convert chantingRounds into FlSpot (x,y points)
    final spots = List.generate(
      chantingRounds.length,
          (index) => FlSpot(index.toDouble(), chantingRounds[index].toDouble()),
    );

    // ✅ Dynamic maxY with padding
    final minValue = chantingRounds.reduce((a, b) => a < b ? a : b).toDouble();
    final maxValue = chantingRounds.reduce((a, b) => a > b ? a : b).toDouble();

    // Add 20% padding on top for visual spacing
    final maxY = maxValue + (maxValue * 0.2);
    final minY = minValue - (minValue * 0.1); // small padding at bottom
    final finalMinY = minY < 0 ? 0 : minY; // don't go below 0
    return Builder(builder: (context) {
      final colors = context.folk;
      return LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: colors.surfaceSecondary, strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
                FlLine(color: colors.surfaceSecondary, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    child: Text(value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.mutedText,
                        )),
                    meta: meta,
                    space: 5,
                  );
                  return Text(value.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueAccent,
                      ));
                },
              ),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: chantingRounds.length.toDouble() - 1,
          minY: 0, // ✅ dynamic bottom
          maxY: maxY, // ✅ dynamic top
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _kData,
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _kData.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: FlDotData(show: true),
            ),
          ],
        ),
      );
    });
  }
}

BarTouchData get barTouchData => BarTouchData(
  enabled: false,
  touchTooltipData: BarTouchTooltipData(
      tooltipPadding: EdgeInsets.zero,
      tooltipMargin: 8,
      getTooltipItem: (
          BarChartGroupData group,
          int groupIndex,
          BarChartRodData rod,
          int rodIndex,
          ) {
        return BarTooltipItem(
            rod.toY.toString(),
            const TextStyle(
                color: Colors.cyan, fontWeight: FontWeight.bold));
      }),
);

FlTitlesData get titlesData => FlTitlesData(
  show: true,
  bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: false,
        reservedSize: 30,
        // getTitlesWidget: getTitles,
      )),
  leftTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
  topTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
  rightTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
);

FlBorderData get borderData => FlBorderData(show: false);

LinearGradient get _barGradient => LinearGradient(
  colors: [
    Color(0xFFDDD2FF),
    _kData,
  ],
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
);

