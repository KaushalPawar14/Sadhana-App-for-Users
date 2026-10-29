/// ALL SADHANA NUMBERS COME FROM THE SADHANA FORM ONLY.
///
/// The chanting number on the ABCDE home screen is the rounds the student reported in the daily sadhana FORM over the last 30 days. It is
/// never the in-app japa counter (`users/{uid}.lifetimeRounds`): that counter stays a personal tool on the Chanting screen.
///
/// A report document is keyed `dd-MM-yyyy` and holds the PREVIOUS day's practice (a report filed on day N records day N-1).
int formRoundsLast30(Map<String, Map<String, dynamic>> reports, DateTime now, {int days = 30}) {
  final today = DateTime(now.year, now.month, now.day);
  final first = today.subtract(Duration(days: days));
  var total = 0;
  for (final e in reports.entries) {
    final m = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(e.key);
    if (m == null) continue;
    final key = DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    final practiceDay = key.subtract(const Duration(days: 1));
    if (practiceDay.isBefore(first) || !practiceDay.isBefore(today)) continue;
    final raw = e.value['chantRounds'];
    if (raw is num && raw > 0) total += raw.toInt();
  }
  return total;
}
