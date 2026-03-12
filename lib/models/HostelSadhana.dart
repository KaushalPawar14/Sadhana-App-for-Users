import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HostelSadhana {
  final TimeOfDay wakeUpTime;
  final int chantRounds;
  final int bookReading;
  final int classHearing;
  final TimeOfDay finishTiming;
  final TimeOfDay sleepTiming;

  HostelSadhana({
    required this.wakeUpTime,
    required this.chantRounds,
    required this.bookReading,
    required this.classHearing,
    required this.finishTiming,
    required this.sleepTiming,
  });

  /// Convert object → Map (always 24h: HH:mm)
  Map<String, dynamic> toMap() {
    return {
      'wakeUpTime': _format24Hour(wakeUpTime),
      'chantRounds': chantRounds,
      'bookReading': bookReading,
      'classHearing': classHearing,
      'finishTiming': _format24Hour(finishTiming),
      'sleepTiming': _format24Hour(sleepTiming),
    };
  }

  /// Convert Map → object (accepts both "22:00" and "10:00 PM")
  factory HostelSadhana.fromMap(Map<String, dynamic> map) {
    return HostelSadhana(
      wakeUpTime: _parseTime(map['wakeUpTime']),
      chantRounds: (map['chantRounds'] as num).toInt(),
      bookReading: (map['bookReading'] as num).toInt(),
      classHearing: (map['classHearing'] as num).toInt(),
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