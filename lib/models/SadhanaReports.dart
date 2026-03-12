// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
//
// class SadhanaReport {
//   TimeOfDay templeEntry;   // Time only
//   int chantRounds;
//   int bookReading;
//   int classHearing;
//   int dailyServices;
//   TimeOfDay finishTiming;  // Time only
//   TimeOfDay sleepTiming;
//
//   SadhanaReport({
//     required this.templeEntry,
//     required this.chantRounds,
//     required this.bookReading,
//     required this.classHearing,
//     required this.dailyServices,
//     required this.finishTiming,
//     required this.sleepTiming
//   });
//
//   Map<String, dynamic> toMap() {
//     return {
//       'templeEntry': '${templeEntry.hour}:${templeEntry.minute}',
//       'chantRounds': chantRounds,
//       'bookReading': bookReading,
//       'classHearing': classHearing,
//       'dailyServices': dailyServices,
//       'finishTiming': '${finishTiming.hour}:${finishTiming.minute}',
//       'sleepTiming': '${sleepTiming.hour}:${sleepTiming.minute}',
//     };
//   }
//   factory SadhanaReport.fromMap(Map<String, dynamic> map) {
//     return SadhanaReport(
//       templeEntry: _parseTime(map['templeEntry']), // Parse time for templeEntry
//       chantRounds: map['chantRounds'],
//       bookReading: map['bookReading'],
//       classHearing: map['classHearing'],
//       dailyServices: map['dailyServices'],
//       finishTiming: _parseTime(map['finishTiming']), // Parse time for finishTiming
//       sleepTiming: _parseTime(map['finishTiming']), // Parse time for finishTiming
//     );
//   }
// }
//
// TimeOfDay _parseTime(String timeString) {
//   final time = DateFormat('h:mm a').parse(timeString);
//   return TimeOfDay(hour: time.hour, minute: time.minute);
// }
//
//
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SadhanaReport {
  final TimeOfDay templeEntry;
  final int chantRounds;
  final int bookReading;
  final int classHearing;
  final int dailyServices;
  final TimeOfDay finishTiming;
  final TimeOfDay sleepTiming;

  SadhanaReport({
    required this.templeEntry,
    required this.chantRounds,
    required this.bookReading,
    required this.classHearing,
    required this.dailyServices,
    required this.finishTiming,
    required this.sleepTiming,
  });

  /// Convert object → Map (always 24h: HH:mm)
  Map<String, dynamic> toMap() {
    return {
      'templeEntry': _format24Hour(templeEntry),
      'chantRounds': chantRounds,
      'bookReading': bookReading,
      'classHearing': classHearing,
      'dailyServices': dailyServices,
      'finishTiming': _format24Hour(finishTiming),
      'sleepTiming': _format24Hour(sleepTiming),
    };
  }

  /// Convert Map → object (accepts both "22:00" and "10:00 PM")
  factory SadhanaReport.fromMap(Map<String, dynamic> map) {
    return SadhanaReport(
      templeEntry: _parseTime(map['templeEntry']),
      chantRounds: (map['chantRounds'] as num).toInt(),
      bookReading: (map['bookReading'] as num).toInt(),
      classHearing: (map['classHearing'] as num).toInt(),
      dailyServices: (map['dailyServices'] as num).toInt(),
      finishTiming: _parseTime(map['finishTiming']),
      sleepTiming: _parseTime(map['sleepTiming']),
    );
  }
}

/// Format TimeOfDay → String in 24h (HH:mm)
String _format24Hour(TimeOfDay time) {
  final now = DateTime.now();
  final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return DateFormat('HH:mm').format(dt); // "08:00" or "20:00"
}

/// Parse → TimeOfDay (handles "22:00", "9:05", "10:00 PM")
TimeOfDay _parseTime(String timeString) {
  final formats = [
    DateFormat('HH:mm'),
    DateFormat('H:mm'),
    DateFormat('h:mm a'),
  ];

  for (final format in formats) {
    try {
      final dt = format.parse(timeString);
      return TimeOfDay(hour: dt.hour, minute: dt.minute); // ✅ always 24h
    } catch (_) {}
  }

  throw FormatException("Invalid time format: $timeString");
}
