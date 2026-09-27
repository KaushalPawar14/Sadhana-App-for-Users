import 'package:cloud_firestore/cloud_firestore.dart';

/// Client-side "does a guide already have this student on the manual
/// roster?" check for registration (Master Task 2026-09-11, Part 2).
///
/// Mirrors `Guides/.../utils/ManualStudents.dart`'s `normalizeMobileNumber`
/// and `functions/manualStudents.js`'s own copy of the same algorithm —
/// necessarily a third, separate implementation (this app cannot share a
/// source file with either), but the SAME algorithm, so all three sides
/// agree on what "the same mobile number" means: strip everything but
/// digits, then keep only the last 10 when more than 10 remain (handles a
/// `+91`/`91` country-code prefix or a leading `0`).
String normalizeMobileNumber(String raw) {
  final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.length <= 10) return digitsOnly;
  return digitsOnly.substring(digitsOnly.length - 10);
}

/// Every manual entry (`isManualEntry == true`) whose own `mobileNumber`
/// equals [normalizedMobile] exactly — a single equality filter (this
/// project's established no-composite-index convention), filtered down to
/// manual entries in code rather than a second `where()` clause, exactly
/// mirroring `functions/manualStudents.js`'s own `findMatchingManualEntries`.
///
/// This is a CLIENT-SIDE convenience check only, purely to decide which
/// fields to show next during registration — it does not itself perform or
/// authorize any merge. The authoritative merge (and its own multiple-match
/// conflict handling) still happens exactly as today, entirely inside
/// `mergeManualEntryOnRegistration` once registration writes `mobileNumber`.
/// Do not add a parallel merge path here.
Future<List<Map<String, dynamic>>> findMatchingManualEntries(
  String normalizedMobile,
) async {
  if (normalizedMobile.isEmpty) return const [];
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .where('mobileNumber', isEqualTo: normalizedMobile)
      .get();

  final matches = <Map<String, dynamic>>[];
  for (final doc in snap.docs) {
    final data = doc.data();
    if (data['isManualEntry'] == true) {
      matches.add(data);
    }
  }
  return matches;
}
