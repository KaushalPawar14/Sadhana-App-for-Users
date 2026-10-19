import 'SameGender.dart';

/// The Leaderboard page's data: everything comes from the students' `competition` documents (own category and
/// own gender only), which the SERVER keeps up to date from the reports (functions/scoring.js):
///  * the total points of a period (`weekly.total_score` / `monthly.total_score`): multipliers applied;
///  * each field's own points, WITHOUT multipliers: `pts_chanting`, `pts_reading`, `pts_hearing` (SB class + extra
///    lecture), `pts_service` (FOLK only).
/// A period is `weekly` (Sunday to Saturday) or `monthly` (the calendar month).
enum BoardPeriod { weekly, monthly }

extension BoardPeriodX on BoardPeriod {
  String get key => name;
  String get label => this == BoardPeriod.weekly ? 'Weekly' : 'Monthly';

  /// "this week" / "this month".
  String get thisPeriod => this == BoardPeriod.weekly ? 'this week' : 'this month';
}

/// The four fields of "Best performers".
enum BestField { chanting, reading, hearing, service }

extension BestFieldX on BestField {
  /// The field after `weekly.pts_` / `monthly.pts_`.
  String get key => name;

  String get title => switch (this) {
        BestField.chanting => 'Best Chanting',
        BestField.reading => 'Best Reading',
        BestField.hearing => 'Best Hearing',
        BestField.service => 'Best Service',
      };

  /// Shown under the title: what the points are made of.
  String get hint => switch (this) {
        BestField.chanting => 'rounds against the commitment',
        BestField.reading => 'minutes against the commitment',
        BestField.hearing => 'Bhagavatam class + extra lecture',
        BestField.service => 'daily services',
      };

  /// Daily services are on the FOLK form only.
  bool get folkOnly => this == BestField.service;
}

/// "62.5 pts" / "50 pts".
String pointsText(num p) => '${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(1)} pts';

class RankedStudent {
  const RankedStudent(this.name, this.points);
  final String name;
  final double points;
}

double _num(Object? v) => v is num ? v.toDouble() : 0;

/// A period's figure from a `competition` document. The server writes flat, literally dotted names
/// (`weekly.total_score`); a document held as nested maps (`{weekly: {total_score}}`, which is how an in-memory
/// test database stores a dotted write) reads the same.
double figure(Map<String, dynamic> data, BoardPeriod period, String field) {
  final flat = data['${period.key}.$field'];
  if (flat is num) return flat.toDouble();
  final nested = data[period.key];
  return nested is Map ? _num(nested[field]) : 0;
}

/// A student's display name: the document's `Name`, else the document id.
String nameOf(String docId, Map<String, dynamic> data) {
  final n = data['Name'];
  return n is String && n.trim().isNotEmpty ? n.trim() : docId.trim();
}

/// Every student of the group ranked by [field] of [period] (`weekly.total_score`, `monthly.pts_chanting`...),
/// best first; ties are in name order. [include] keeps only the viewer's own gender. A student with nothing yet
/// scores 0 (never dropped), and the `flag` document of the old scorecard days is never a student.
List<RankedStudent> rank(
  Map<String, Map<String, dynamic>> docs,
  BoardPeriod period,
  String field, {
  bool Function(String docId)? include,
}) {
  final out = <RankedStudent>[];
  for (final e in docs.entries) {
    if (e.key == 'flag') continue;
    if (include != null && !include(e.key)) continue;
    out.add(RankedStudent(nameOf(e.key, e.value), figure(e.value, period, field)));
  }
  out.sort((a, b) {
    final c = b.points.compareTo(a.points);
    return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// The total-points ranking of a period (multipliers applied).
List<RankedStudent> totalRanking(Map<String, Map<String, dynamic>> docs, BoardPeriod period, {bool Function(String)? include}) =>
    rank(docs, period, 'total_score', include: include);

/// The best [count] of a field for a period: per-item points, NO multipliers. Only students who scored something
/// are listed (an empty list means nobody has points in it yet).
List<RankedStudent> bestOf(
  Map<String, Map<String, dynamic>> docs,
  BoardPeriod period,
  BestField field, {
  int count = 5,
  bool Function(String)? include,
}) =>
    rank(docs, period, 'pts_${field.key}', include: include).where((r) => r.points > 0).take(count).toList();

/// Is [name] (the viewer's own name) this row? Compared trimmed and case-insensitively, like the rest of the app.
bool isMe(String rowName, String? myName) =>
    myName != null && myName.trim().isNotEmpty && rowName.trim().toLowerCase() == myName.trim().toLowerCase();

/// The competition documents of the viewer's own category and gender, as read by the page.
typedef DocsReader = Future<Map<String, Map<String, dynamic>>> Function();

/// The students the viewer sees on the boards: [GenderDirectory.sameByName] keeps their own gender.
bool Function(String) sameGenderOnly(GenderDirectory directory) => directory.sameByName;
