import 'SadhanaStats.dart' show sadhanaDateKey;

// The Insights graphs, from the student's OWN submitted reports.
//
// Nothing here is computed afresh: each graph reads the same report field the
// old Graphical Analysis (`scores/AllGraphs.dart`) read, the same way, and the
// two pies count exactly as it did. No totals, averages or combined scores are
// added, and LIT and ABCDE are never combined. A graph is one field of the
// report, one bar per day.
//
// Reports are keyed by their date id, `dd-MM-yyyy` (see `SadhanaReportSource`).
typedef Reports = Map<String, Map<String, dynamic>>;

enum InsightPeriod { weekly, monthly }

enum InsightKind {
  // A whole number per day (rounds, minutes).
  count,
  // 2 = fully, 1 = partly, 0 = missed.
  level,
  // A "HH:mm" time per day, drawn against a fixed ceiling.
  time,
  // All reports counted into Fully / Partial / Missed.
  pie,
}

class InsightGraphSpec {
  const InsightGraphSpec({
    required this.id,
    required this.name,
    required this.title,
    required this.field,
    required this.kind,
    this.cap,
    this.folkOnly = false,
  });

  final String id;

  // The short name under the card.
  final String name;

  // The card's heading.
  final String title;

  // The report field it reads.
  final String field;
  final InsightKind kind;

  // For a time graph: the old chart's ceiling in minutes (bars are cut there).
  final int? cap;

  // Only the FOLK form has this field (the Hostel / Localite form does not).
  final bool folkOnly;
}

// The graphs, in the order the carousel swipes through them, and where each one
// came from in the old Graphical Analysis.
const List<InsightGraphSpec> kInsightGraphs = [
  // Chanting 📿 — line chart of `chantRounds`.
  InsightGraphSpec(id: 'chanting', name: 'Chanting', title: 'Chanting rounds', field: 'chantRounds', kind: InsightKind.count),
  // Reading 📖 — line chart of `bookReading` (minutes).
  InsightGraphSpec(id: 'reading', name: 'Reading', title: 'Reading (minutes)', field: 'bookReading', kind: InsightKind.count),
  // Class Hearing 🎧 — its pie read `classHearing` (2 / 1 / 0) per day.
  InsightGraphSpec(id: 'hearing', name: 'Hearing', title: 'Class hearing', field: 'classHearing', kind: InsightKind.level),
  // Daily Services 🛐 — its pie read `dailyServices` (2 / 1 / 0) per day.
  InsightGraphSpec(id: 'services', name: 'Services', title: 'Daily services', field: 'dailyServices', kind: InsightKind.level, folkOnly: true),
  // Chanting Finish Timing ⏰ — bars of `finishTiming`, ceiling 10:00 PM.
  InsightGraphSpec(id: 'finish', name: 'Finish time', title: 'Chanting finish time', field: 'finishTiming', kind: InsightKind.time, cap: 1320),
  // Temple Entry ⛪ — bars of `templeEntry`, ceiling 10:00 AM (600 min).
  InsightGraphSpec(id: 'temple', name: 'Temple entry', title: 'Temple entry time', field: 'templeEntry', kind: InsightKind.time, cap: 600, folkOnly: true),
  // The two pies, as the old screen drew them (all reports, counted).
  InsightGraphSpec(id: 'hearingPie', name: 'Hearing split', title: 'Class hearing', field: 'classHearing', kind: InsightKind.pie),
  InsightGraphSpec(id: 'servicesPie', name: 'Services split', title: 'Daily services', field: 'dailyServices', kind: InsightKind.pie, folkOnly: true),
];

bool isHostelForm(String role) =>
    role == 'Stay at Hostel' || role == 'Stay at Localite';

// The graphs that apply to this student: those whose field exists in their
// reports. A student with no reports yet gets the graphs of their own form
// (the FOLK form has temple entry and daily services; the Hostel / Localite
// form has neither).
List<InsightGraphSpec> applicableGraphs(Reports reports, String role) {
  bool has(String field) => reports.values.any((r) => r.containsKey(field));
  if (reports.isEmpty) {
    return [
      for (final g in kInsightGraphs)
        if (!(g.folkOnly && isHostelForm(role))) g,
    ];
  }
  return [
    for (final g in kInsightGraphs)
      if (has(g.field)) g,
  ];
}

class BarPoint {
  const BarPoint({
    required this.day,
    required this.label,
    required this.value,
    required this.isToday,
    required this.isFuture,
  });

  final DateTime day;

  // What sits under the bar: "M".."S" (weekly), or a day number on a few days
  // (monthly), else empty.
  final String label;

  // The day's value, or null when there is no report for it.
  final double? value;
  final bool isToday;
  final bool isFuture;
}

const List<String> _weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const Set<int> _monthLabelDays = {1, 5, 10, 15, 20, 25, 30};

// The days drawn for [period]: Monday to Sunday of this week, or every day of
// this month.
List<DateTime> daysOf(InsightPeriod period, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  if (period == InsightPeriod.weekly) {
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    return [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
  }
  final n = DateTime(t.year, t.month + 1, 0).day;
  return [for (var d = 1; d <= n; d++) DateTime(t.year, t.month, d)];
}

// A "HH:mm" time as minutes, parsed as the old charts did: two parts split on
// ":" or the day is skipped; an unreadable part counts as 0.
int? parseMinutes(Object? raw) {
  if (raw is! String) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  return hour * 60 + minute;
}

double? _valueOf(InsightGraphSpec g, Map<String, dynamic>? report) {
  if (report == null || !report.containsKey(g.field)) return null;
  final v = report[g.field];
  switch (g.kind) {
    case InsightKind.count:
    case InsightKind.level:
      return v is num ? v.toInt().toDouble() : null;
    case InsightKind.time:
      final m = parseMinutes(v);
      if (m == null) return null;
      // The old charts cut each bar at their ceiling.
      return (m > g.cap! ? g.cap! : m).toDouble();
    case InsightKind.pie:
      return null;
  }
}

List<BarPoint> barsFor({
  required InsightGraphSpec graph,
  required InsightPeriod period,
  required Reports reports,
  required DateTime today,
}) {
  final t = DateTime(today.year, today.month, today.day);
  return [
    for (final day in daysOf(period, today))
      BarPoint(
        day: day,
        label: period == InsightPeriod.weekly
            ? _weekLetters[day.weekday - 1]
            : (_monthLabelDays.contains(day.day) ? '${day.day}' : ''),
        value: _valueOf(graph, reports[sadhanaDateKey(day)]),
        isToday: day == t,
        isFuture: day.isAfter(t),
      ),
  ];
}

// The tallest a bar can be, for [graph]: a count graph scales to its own
// largest bar in view, a level graph to 2, a time graph to its ceiling.
double scaleMax(InsightGraphSpec graph, List<BarPoint> bars) {
  switch (graph.kind) {
    case InsightKind.level:
      return 2;
    case InsightKind.time:
      return graph.cap!.toDouble();
    case InsightKind.count:
    case InsightKind.pie:
      var max = 1.0;
      for (final b in bars) {
        if (b.value != null && b.value! > max) max = b.value!;
      }
      return max;
  }
}

bool hasAnyValue(List<BarPoint> bars) => bars.any((b) => b.value != null);

// The two pies, counted exactly as the old Graphical Analysis did: every report
// that has the field, 2 = Fully, 1 = Partial, anything else = Missed.
Map<String, int> pieCounts(Reports reports, String field) {
  final counts = {'Fully': 0, 'Partial': 0, 'Missed': 0};
  for (final data in reports.values) {
    if (!data.containsKey(field)) continue;
    final v = data[field];
    final val = v is num ? v.toInt() : -1;
    if (val == 2) {
      counts['Fully'] = counts['Fully']! + 1;
    } else if (val == 1) {
      counts['Partial'] = counts['Partial']! + 1;
    } else {
      counts['Missed'] = counts['Missed']! + 1;
    }
  }
  return counts;
}

// -----------------------------------------------------------------------------
// The one small stat beside a graph's title
// -----------------------------------------------------------------------------
//
// Worked out from the same reports the graph is drawn from, for the same days
// (Monday-Sunday, or the month so far). Only days that have a report count; days
// without one are left out, and a period with none gives null (no stat shown).
// Each stat is ONE metric of ONE graph; none is combined with another.
//
//   chanting  "Highest 16"      the largest `chantRounds` of a reported day
//   reading   "Avg 35 min"      the mean `bookReading` of the reported days
//   hearing   "Heard 71%"       the average score of the reported days, each day
//                               scoring `classHearing` / 2 (Fully 2 = 100%,
//                               Partial 1 = 50%, Missed 0 = 0%):
//                               sum of values / (2 x reported days) x 100, rounded
//   services  "Done 86%"        the same, for `dailyServices`
//   finish    "Avg 10:42 PM"    mean `finishTiming`, a late-night time after
//                               midnight counting as LATER than 11 PM (see below)
//   temple    "Avg 5:05 AM"     mean `templeEntry`
//   the pies  none
//
// What is stored: `classHearing` is 2 = Fully, 1 = Partial, 0 = Missed
// ("SB Class": Fully / Partial / Missed); `dailyServices` is 2 = Done fully,
// 1 = Done partially, 0 = Not done (Questions.dart). "Heard" / "Done" is a score: each day scores value / 2, so a Partial day counts as half
// (values 2, 1, 0 -> 3 / 6 = 50%).
//
// Finish times: the stat uses the times as stored, not the bars' 10:00 PM ceiling
// (a 11 PM finish is 11 PM, not 10). A time from 00:00 to 03:59 is a finish after
// midnight, so it is counted as that time PLUS 24 hours (00:30 -> 24:30), after
// 23:00. The mean of 23:30 and 00:30 is therefore 00:00 (midnight), not 12:00. The
// mean is shown back on the clock (24:42 -> 12:42 AM). From 04:00 on a time is the
// same day.
const int _lateNightEndsAt = 4 * 60;

// "10:42 PM", "5:05 AM", "12:30 AM": [minutes] on a 12-hour clock.
String formatClock(int minutes) {
  final m = ((minutes % 1440) + 1440) % 1440;
  final h24 = m ~/ 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${(m % 60).toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
}

String? statFor({
  required InsightGraphSpec graph,
  required InsightPeriod period,
  required Reports reports,
  required DateTime today,
}) {
  if (graph.kind == InsightKind.pie) return null;
  final t = DateTime(today.year, today.month, today.day);
  final values = <double>[];
  for (final day in daysOf(period, today)) {
    if (day.isAfter(t)) continue;
    final report = reports[sadhanaDateKey(day)];
    if (report == null || !report.containsKey(graph.field)) continue;
    final v = report[graph.field];
    if (graph.kind == InsightKind.time) {
      final m = parseMinutes(v);
      if (m == null || m < 0 || m >= 1440) continue;
      values.add((graph.id == 'finish' && m < _lateNightEndsAt ? m + 1440 : m).toDouble());
    } else if (v is num) {
      values.add(v.toInt().toDouble());
    }
  }
  if (values.isEmpty) return null;
  final n = values.length;
  final sum = values.fold<double>(0, (a, b) => a + b);
  switch (graph.id) {
    case 'chanting':
      return 'Highest ${values.reduce((a, b) => a > b ? a : b).toInt()}';
    case 'reading':
      return 'Avg ${(sum / n).round()} min';
    case 'hearing':
      return 'Heard ${(sum * 100 / (2 * n)).round()}%';
    case 'services':
      return 'Done ${(sum * 100 / (2 * n)).round()}%';
    case 'finish':
    case 'temple':
      return 'Avg ${formatClock((sum / n).round())}';
  }
  return null;
}
