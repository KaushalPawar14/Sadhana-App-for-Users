import 'package:cloud_functions/cloud_functions.dart';

/// The words of a failed server call that are safe to show a student.
///
/// The server's own message is used when it is a sentence written for people (an `HttpsError` such as "This request is
/// no longer pending"). A bare status code ("INTERNAL"), a technical code (`[cloud_functions/...]`) or a transport-level
/// failure gives [fallback] instead - the student never sees raw error text.
String callableMessage(FirebaseFunctionsException e, String fallback) {
  const technical = {'internal', 'unknown', 'unavailable', 'deadline-exceeded', 'unauthenticated', 'data-loss', 'cancelled', 'aborted'};
  if (technical.contains(e.code)) return fallback;
  final m = (e.message ?? '').trim();
  if (m.isEmpty) return fallback;
  if (RegExp(r'^[A-Z0-9_ ]+$').hasMatch(m)) return fallback;
  if (m.contains('[cloud_functions/') || m.contains('Exception')) return fallback;
  return m;
}
