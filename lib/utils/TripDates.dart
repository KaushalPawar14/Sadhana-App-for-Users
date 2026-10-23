import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// A trip's last day: its `endDate`, or — for a trip made before end dates
/// existed — its one `tripDate`. An end that falls before the start is ignored,
/// matching the server (`functions/expeditions.js`, `tripEndDate`), so a
/// hand-edited trip never reads as ending before it begins.
DateTime? tripEndOf(Map<String, dynamic> trip) {
  final start = trip['tripDate'];
  final end = trip['endDate'];
  final s = start is Timestamp ? start.toDate() : null;
  final e = end is Timestamp ? end.toDate() : null;
  if (e != null &&
      (s == null ||
          !DateTime(e.year, e.month, e.day)
              .isBefore(DateTime(s.year, s.month, s.day)))) {
    return e;
  }
  return s;
}

/// "25 Aug 2026" for a one-day trip, "18 Oct – 20 Oct 2026" for a longer one,
/// "Not set" with no date.
String tripDatesText(Map<String, dynamic> trip) {
  final start = trip['tripDate'];
  final end = tripEndOf(trip);
  final full = DateFormat('dd MMM yyyy');
  if (start is! Timestamp) return 'Not set';
  if (end == null) return full.format(start.toDate());
  final s = start.toDate();
  final sameDay = s.year == end.year && s.month == end.month && s.day == end.day;
  if (sameDay) return full.format(s);
  return s.year == end.year
      ? '${DateFormat('dd MMM').format(s)} – ${full.format(end)}'
      : '${full.format(s)} – ${full.format(end)}';
}
