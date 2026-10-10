// The two numbers above the Sadhana calendar, worked out from the set of dates
// the student has submitted a report for — the very set the calendar already
// colours its days from (`mergedAvailableDatesStream`). Nothing is read or
// stored for them.
//
// A date is the report's own document id, `dd-MM-yyyy`, used as it is.

String sadhanaDateKey(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

class MonthTally {
  const MonthTally({required this.submitted, required this.counted});

  // Days in the shown month the student submitted a report for.
  final int submitted;

  // Days that could have been submitted: the days before today (plus today when
  // it has been submitted) in the current month, the whole month for a past one.
  final int counted;

  // Nothing to count yet (the first day of a month, before today's report).
  bool get isEmpty => counted == 0;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

// "N of M — days submitted" for [month].
MonthTally monthTally({
  required Set<String> dates,
  required DateTime month,
  required DateTime today,
}) {
  final t = _day(today);
  final monthStart = DateTime(month.year, month.month);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final isCurrent = month.year == t.year && month.month == t.month;
  final isFuture = monthStart.isAfter(t);

  var submitted = 0;
  for (var d = 1; d <= daysInMonth; d++) {
    final day = DateTime(month.year, month.month, d);
    if (day.isAfter(t)) break;
    if (dates.contains(sadhanaDateKey(day))) submitted++;
  }

  if (isFuture) return const MonthTally(submitted: 0, counted: 0);
  if (!isCurrent) return MonthTally(submitted: submitted, counted: daysInMonth);

  final todaySubmitted = dates.contains(sadhanaDateKey(t));
  return MonthTally(
    submitted: submitted,
    counted: (t.day - 1) + (todaySubmitted ? 1 : 0),
  );
}

// "N days — current streak": consecutive submitted days ending today, or
// yesterday when today has not been submitted yet. It can only count back
// through the reports that are still kept.
int currentStreak({required Set<String> dates, required DateTime today}) {
  var day = _day(today);
  if (!dates.contains(sadhanaDateKey(day))) {
    day = DateTime(day.year, day.month, day.day - 1); // by calendar day
  }
  var streak = 0;
  while (dates.contains(sadhanaDateKey(day))) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}
