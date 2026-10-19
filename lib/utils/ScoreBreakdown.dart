/// Reads of the competition document for the "Your Score" breakdown. The points
/// themselves are set by the server (functions/scoring.js): each item below is
/// already multiplied by that day's multipliers, so the items add up to the total.

/// The multipliers are stored as per-day SUMS (so two periods can be added); the
/// breakdown shows the average over the days filed, e.g. 1.31. No days = 1.00.
String averageMultiplier(num sum, num days) =>
    days <= 0 ? '1.00' : (sum / days).toStringAsFixed(2);

/// The multiplier lines of the breakdown, in the order they are shown:
/// FOLK: temple, japa, sleep. Hostel & Localite: wake-up, japa, sleep.
/// [prefix] is `weekly` or `monthly`.
List<({String label, String value})> multiplierLines(
  Map<String, dynamic> data,
  String prefix, {
  required bool hostelLocalite,
}) {
  num n(String k) => data['$prefix.$k'] is num ? data['$prefix.$k'] as num : 0;
  final days = n('days_count');
  return [
    if (hostelLocalite)
      (label: '⏰ Wake-up', value: averageMultiplier(n('wakeup_multiplier'), days))
    else
      (label: '🛕 Temple', value: averageMultiplier(n('temple_multiplier'), days)),
    (label: '📿 Japa', value: averageMultiplier(n('japa_multiplier'), days)),
    (label: '😴 Sleep', value: averageMultiplier(n('sleeping_multiplier'), days)),
  ];
}

const String kBreakdownCaption =
    'Each day: points × the multipliers below. The multipliers shown are your averages.';
