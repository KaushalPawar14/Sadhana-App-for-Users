import 'package:flutter/foundation.dart';

import 'Commitments.dart';
import 'DayScore.dart';
import 'SadhanaSave.dart';

/// The scoring questions of the Sadhana forms (FOLK and Hostel & Localite).
enum PointsTopic { temple, wakeup, sleep, japa, sbClass, services, chanting, reading, extraLecture }

/// The live points of a Sadhana form: for each scoring question the points (or the multiplier) its CURRENT answer earns,
/// and the day's total so far. Everything comes from [DayScore] (the same rules as the server, checked against the shared
/// test vectors), so the numbers shown while filling the form are the numbers the day will get.
///
/// [read] returns the answers as the saved report map would hold them (`chantRounds`, `bookReading`, `classHearing`,
/// `dailyServices`, `extraLecture` as numbers or null; the four times as "HH:mm" or ""). The screen calls [bump] whenever
/// an answer changes; [tick] is what the chips listen to, so only the chips repaint.
class LiveFormPoints {
  LiveFormPoints({required this.form, required this.read});

  final ReportForm form;
  final Map<String, Object?> Function() read;
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// The student's commitments (until they are read: the server's defaults, 16 rounds and reading 0).
  Commitments commitments = const Commitments(readingMinutes: 0);

  void bump() => tick.value++;

  void setCommitments(Commitments c) {
    commitments = c;
    bump();
  }

  void dispose() => tick.dispose();

  int get _chantC => commitments.rounds > 0 ? commitments.rounds : kDefaultChantCommitment;
  int get _readC => commitments.readingMinutes ?? 0;

  /// Which topics this form has.
  bool has(PointsTopic t) => switch (t) {
        PointsTopic.temple || PointsTopic.services || PointsTopic.extraLecture => form == ReportForm.folk,
        PointsTopic.wakeup => form == ReportForm.hostel,
        _ => true,
      };

  num? _number(Object? v) => v is num ? v : (v is String ? parseWholeNumber(v) : null);

  /// The chip text of [topic] for the current answer, or null while it is not answered: "+50 pts", "+62.5 pts", "×1.5".
  String? chipFor(PointsTopic topic) {
    if (!has(topic)) return null;
    final r = read();
    String? time(String key) {
      final v = r[key];
      return v is String && minutesOf(v) != null ? v : null;
    }

    String pts(double p) => '+${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(1)} pts';
    switch (topic) {
      case PointsTopic.chanting:
        final n = _number(r['chantRounds']);
        return n == null ? null : pts(chantingPoints(n, _chantC));
      case PointsTopic.reading:
        final n = _number(r['bookReading']);
        return n == null ? null : pts(readingPoints(n, _readC));
      case PointsTopic.sbClass:
        final n = _number(r['classHearing']);
        return n == null ? null : pts(gradedPoints(n));
      case PointsTopic.services:
        final n = _number(r['dailyServices']);
        return n == null ? null : pts(gradedPoints(n));
      case PointsTopic.extraLecture:
        final n = _number(r['extraLecture']);
        return n == null ? null : pts(gradedPoints(n));
      case PointsTopic.temple:
        final t = time('templeEntry');
        return t == null ? null : multiplierText(templeMultiplier(t));
      case PointsTopic.wakeup:
        final t = time('wakeUpTime');
        return t == null ? null : multiplierText(wakeupMultiplier(t));
      case PointsTopic.sleep:
        final t = time('sleepTiming');
        return t == null ? null : multiplierText(form == ReportForm.folk ? folkSleepMultiplier(t) : hostelSleepMultiplier(t));
      case PointsTopic.japa:
        final t = time('finishTiming');
        return t == null ? null : multiplierText(japaMultiplier(t));
    }
  }

  /// Is the chip of [topic] a multiplier (as opposed to points)?
  static bool isMultiplier(PointsTopic t) => t == PointsTopic.temple || t == PointsTopic.wakeup || t == PointsTopic.sleep || t == PointsTopic.japa;

  /// The day's points so far (multipliers included, not rounded): what the day gets if it were submitted now.
  double get total {
    final r = read();
    return scoreDayTotal({
      for (final e in r.entries) e.key: e.value is String && !_isTimeKey(e.key) ? _number(e.value) : e.value,
    }, form: form, chantCommitment: _chantC, readCommitment: _readC);
  }

  static bool _isTimeKey(String k) => k == 'templeEntry' || k == 'wakeUpTime' || k == 'sleepTiming' || k == 'finishTiming';

  /// "Today so far: 150 points".
  String get totalText {
    final n = wholePoints(total);
    return 'Today so far: $n ${n == 1 ? 'point' : 'points'}';
  }
}
