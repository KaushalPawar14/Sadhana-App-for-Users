import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// What the two Sadhana report forms (FOLK and hostel/localite) share around
// the save: how a save fails, how long it may take, what is said to the
// student, and how the numbers and times on the form are checked. The write
// itself is not here; it stays in each form's own `saveSadhanaReport`.

enum SadhanaSaveFailure {
  // No signed-in user, no users/{uid} document, or no name on it: nothing is
  // written, so a report can never land under a made-up name.
  profileIncomplete,

  // The server did not answer in time (or the network is unavailable).
  timeout,

  // The server refused the write.
  permission,

  // Anything else.
  failed,
}

class SadhanaSaveException implements Exception {
  const SadhanaSaveException(this.failure);

  final SadhanaSaveFailure failure;

  @override
  String toString() => 'SadhanaSaveException($failure)';
}

// How long a save may take before the student is told the server could not be
// reached.
const Duration kSadhanaSaveTimeout = Duration(seconds: 15);

// Runs [save] and turns every way it can fail into a [SadhanaSaveException].
// Returns only if [save] completed.
Future<void> runSadhanaSave(
  Future<void> Function() save, {
  Duration timeout = kSadhanaSaveTimeout,
}) async {
  try {
    await save().timeout(timeout);
  } on SadhanaSaveException {
    rethrow;
  } on TimeoutException {
    throw const SadhanaSaveException(SadhanaSaveFailure.timeout);
  } on FirebaseException catch (e) {
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        throw const SadhanaSaveException(SadhanaSaveFailure.timeout);
      case 'permission-denied':
        throw const SadhanaSaveException(SadhanaSaveFailure.permission);
      default:
        throw const SadhanaSaveException(SadhanaSaveFailure.failed);
    }
  } catch (_) {
    throw const SadhanaSaveException(SadhanaSaveFailure.failed);
  }
}

String sadhanaSaveMessage(SadhanaSaveFailure failure) {
  switch (failure) {
    case SadhanaSaveFailure.profileIncomplete:
      return 'Your profile is incomplete — please contact your guide.';
    case SadhanaSaveFailure.timeout:
      return "Couldn't reach the server — please try again";
    case SadhanaSaveFailure.permission:
      return "Your report wasn't saved — you may not have permission. "
          'Please contact your guide.';
    case SadhanaSaveFailure.failed:
      return "Couldn't save your report — please try again";
  }
}

// The student's stored name, or a [SadhanaSaveException] when there is none.
// A report is keyed by this name, so it must be a real one: the users document
// has to exist and `name` has to be a non-empty string. The name is returned
// exactly as stored (never trimmed, never defaulted).
String requireStudentName({
  required bool userExists,
  required Object? storedName,
}) {
  if (!userExists || storedName is! String || storedName.trim().isEmpty) {
    throw const SadhanaSaveException(SadhanaSaveFailure.profileIncomplete);
  }
  return storedName;
}

const String kWholeNumberMessage =
    'Enter a whole number, like 16 — no decimals, commas or symbols';

// A whole number: digits only (one to nine of them). Anything else — a
// decimal point, a comma, a sign, letters, spaces inside — is rejected.
// Leading and trailing spaces are ignored.
int? parseWholeNumber(String raw) {
  final text = raw.trim();
  if (!RegExp(r'^[0-9]{1,9}$').hasMatch(text)) return null;
  return int.tryParse(text);
}

// The same three time formats the forms' own `_parseTime` accepts, but null
// (not midnight) when none fits.
TimeOfDay? tryParseTime(String raw) {
  final formats = [
    DateFormat('HH:mm'),
    DateFormat('H:mm'),
    DateFormat('h:mm a'),
  ];
  for (final format in formats) {
    try {
      final dt = format.parseStrict(raw.trim());
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {}
  }
  return null;
}

// Sleep time after midnight. A sleep time from 00:00 to 11:59 means the student
// went to bed after midnight, which must score the same as 11:59 PM: the sleep
// multiplier compares minutes since midnight, so 00:30 would otherwise read as the
// EARLIEST bedtime of the day and earn the biggest bonus. It is saved as 23:59.
// A PM time (12:00 to 23:59) is saved as chosen.
const String kSleepAfterMidnightNote = 'Times after midnight are recorded as 11:59 PM.';

TimeOfDay normalizeSleepTime(TimeOfDay t) =>
    t.hour < 12 ? const TimeOfDay(hour: 23, minute: 59) : t;
