import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// A student's daily commitments, which the points are measured against
/// (chanting: rounds; reading: minutes). The points themselves are worked out on
/// the server (functions/scoring.js) - this file only asks the typo question and
/// shows the commitment.
class Commitments {
  const Commitments({this.rounds = kDefaultChantCommitment, this.readingMinutes, this.roundsSet = true});

  /// Rounds a day. Missing (older profiles) counts as the standard 16 for scoring and
  /// for the typo check - exactly what the server does - until the student sets it
  /// ([roundsSet] false: the app asks).
  final int rounds;

  /// False when the profile has no chanting commitment saved yet.
  final bool roundsSet;

  /// Minutes of reading a day. Null = not set yet; 0 = a beginner (any reading
  /// scores a flat 50).
  final int? readingMinutes;

  bool get readingSet => readingMinutes != null;

  /// Both commitments are saved: nothing to ask.
  bool get complete => roundsSet && readingSet;

  factory Commitments.fromUser(Map<String, dynamic>? user) {
    final r = user?['commitmentRounds'];
    final m = user?['readingCommitmentMinutes'];
    return Commitments(
      rounds: r is num && r > 0 ? r.toInt() : kDefaultChantCommitment,
      roundsSet: r is num && r > 0,
      readingMinutes: m is num && m >= 0 ? m.toInt() : null,
    );
  }
}

const int kDefaultChantCommitment = 16;

/// More than this many times the commitment is probably a typing slip.
const int kTypoFactor = 4;

/// The reading commitment is a whole number of minutes, 0 to a day's worth
/// (the same bounds the rules enforce). Null = not a valid entry.
const int kMaxReadingCommitment = 1440;

/// The chanting commitment is a whole number of rounds, at least 1 (and a sane most).
const int kMaxChantCommitment = 192;

int? parseChantCommitment(String text) {
  final t = text.trim();
  if (t.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(t)) return null;
  final v = int.parse(t);
  return v >= 1 && v <= kMaxChantCommitment ? v : null;
}

int? parseReadingCommitment(String text) {
  final t = text.trim();
  if (t.isEmpty || !RegExp(r'^\d{1,4}$').hasMatch(t)) return null;
  final v = int.parse(t);
  return v > kMaxReadingCommitment ? null : v;
}

/// Same rule as `looksLikeTypo` in functions/scoring.js: more than 4x the
/// commitment asks; a commitment of 0 (or none) never asks; no cap otherwise.
bool looksLikeTypo(num entered, num commitment) =>
    commitment > 0 && entered > kTypoFactor * commitment;

/// Reads the signed-in student's commitments. A failed read (offline) gives a COMPLETE
/// answer built from the defaults, so a form is never blocked by a read that failed;
/// the next successful read asks for whatever is really missing.
Future<Commitments> loadMyCommitments() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Commitments(readingMinutes: 0);
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    return Commitments.fromUser(doc.data());
  } catch (_) {
    return const Commitments(readingMinutes: 0);
  }
}

/// "You entered 160 - is that correct?" Returns true when the student confirms.
Future<bool> confirmUnusualAmount(
  BuildContext context, {
  required String what,
  required int entered,
  required String unit,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('You entered $entered'),
      content: Text('$what: $entered $unit - is that correct?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('No, let me fix it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Yes, it is correct'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The one line the Profile shows: "16 rounds · 30 min reading".
String commitmentLine(Commitments c) {
  final reading = c.readingMinutes == null
      ? 'reading not set'
      : (c.readingMinutes == 0 ? 'no reading target' : '${c.readingMinutes} min reading');
  return '${c.rounds} rounds · $reading';
}
