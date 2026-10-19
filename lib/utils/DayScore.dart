/// One day's points, for the "Sadhana submitted · N points" message.
///
/// This is a line-for-line port of `scoreDay` in functions/scoring.js (the server stays the source of truth for the
/// leaderboards; this is only what the student sees right after saving). `test/day_score_test.dart` runs the SAME shared
/// vectors file the server's tests run (`test/fixtures/scoring_vectors.json`, a copy of functions/test/scoring_vectors.json),
/// so the two can never disagree about a number.
///
/// Fed with the very map that is saved (`SadhanaReport.toMap()` / `HostelSadhana.toMap()` plus `extraLecture` on the FOLK
/// form), so it scores exactly what the server will read.
library;

import 'dart:math' as math;

const double _full = 50;
const double _partial = 25;

/// "FOLK" form or "Hostel & Localite" form.
enum ReportForm { folk, hostel }

// minutes since midnight; a time of day is "by" a limit when it is at or before it
const List<List<num>> _japa = [[10 * 60, 1.5], [14 * 60, 1.25], [18 * 60, 1.15]];
const List<List<num>> _sleepFolk = [[22 * 60, 1.5], [22 * 60 + 30, 1.25], [23 * 60, 1.15]];
const List<List<num>> _temple = [[5 * 60 + 35, 1.5], [5 * 60 + 45, 1.25], [6 * 60, 1.15]];
const List<List<num>> _wakeup = [[5 * 60 + 30, 1.5], [6 * 60, 1.25], [6 * 60 + 30, 1.15]];
const List<List<num>> _sleepHostel = [[22 * 60 + 30, 1.5], [23 * 60, 1.25], [23 * 60 + 30, 1.15]];

/// "HH:mm", "H:mm" or "h:mm a" -> minutes since midnight, or null.
int? minutesOf(Object? value) {
  final s = (value ?? '').toString().trim();
  var m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    return h < 24 && mi < 60 ? h * 60 + mi : null;
  }
  m = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$').firstMatch(s);
  if (m != null) {
    var h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h < 1 || h > 12 || mi > 59) return null;
    h = h % 12 + (m.group(3)!.toLowerCase().startsWith('p') ? 12 : 0);
    return h * 60 + mi;
  }
  return null;
}

double _tier(int? minutes, List<List<num>> tiers) {
  if (minutes == null) return 1.0;
  for (final t in tiers) {
    if (minutes <= t[0]) return t[1].toDouble();
  }
  return 1.0;
}

/// A sleep time as the form saves it: anything before noon is "after midnight" and counts as 11:59 PM.
int? _sleepMinutes(Object? value) {
  final m = minutesOf(value);
  return m != null && m < 12 * 60 ? 23 * 60 + 59 : m;
}

double japaMultiplier(Object? v) => _tier(minutesOf(v), _japa);
double folkSleepMultiplier(Object? v) => _tier(_sleepMinutes(v), _sleepFolk);
double templeMultiplier(Object? v) => _tier(minutesOf(v), _temple);
double wakeupMultiplier(Object? v) => _tier(minutesOf(v), _wakeup);
double hostelSleepMultiplier(Object? v) => _tier(_sleepMinutes(v), _sleepHostel);

double _count(Object? v) => v is num && v.isFinite && v > 0 ? v.toDouble() : 0;

/// 50 x rounds / commitment; a missing / 0 commitment is the standard 16 (the server's rule).
double chantingPoints(num rounds, num commitment) => commitment > 0 ? _full * _count(rounds) / commitment : 0;

/// 50 x minutes / commitment; with a commitment of 0 a flat 50 for any reading that day.
double readingPoints(num minutes, num commitment) {
  final m = _count(minutes);
  if (commitment > 0) return _full * m / commitment;
  return m > 0 ? _full : 0;
}

/// Fully (2) = 50, Partially (1) = 25, Not (0) = 0. Also the extra lecture's stored level.
double gradedPoints(Object? level) {
  final v = _count(level);
  return v >= 2 ? _full : (v >= 1 ? _partial : 0);
}

/// The day's points (multipliers included, NOT rounded): same as `scoreDay(...).total` on the server.
/// [report] is the saved map; [chantCommitment] <= 0 means the standard 16; [readCommitment] <= 0 means the flat 50.
double scoreDayTotal(
  Map<String, dynamic> report, {
  required ReportForm form,
  required int chantCommitment,
  required int readCommitment,
}) {
  final folk = form == ReportForm.folk;
  final chantC = chantCommitment > 0 ? chantCommitment : 16;
  final readC = readCommitment > 0 ? readCommitment : 0;
  final base = gradedPoints(report['classHearing']) +
      (folk ? gradedPoints(report['dailyServices']) : 0) +
      chantingPoints(_count(report['chantRounds']), chantC) +
      readingPoints(_count(report['bookReading']), readC) +
      (folk ? gradedPoints(report['extraLecture']) : 0);
  final multiplier = folk
      ? templeMultiplier(report['templeEntry']) * 1.0 * folkSleepMultiplier(report['sleepTiming']) * japaMultiplier(report['finishTiming'])
      : 1.0 * wakeupMultiplier(report['wakeUpTime']) * hostelSleepMultiplier(report['sleepTiming']) * japaMultiplier(report['finishTiming']);
  return base * multiplier;
}

/// A sensible whole number: rounded to the nearest point (halves up, like the server's `Math.round`).
int wholePoints(double total) => (total + 1e-9).round();

/// The green message after a successful save: "Sadhana submitted · 150 points".
String sadhanaSubmittedMessage(double dayTotal) {
  final n = math.max(0, wholePoints(dayTotal));
  return 'Sadhana submitted · $n ${n == 1 ? 'point' : 'points'}';
}
