import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Thin wrappers over the student-facing Cloud Functions (functions/
/// studentCallables.js). They exist because the strict Firestore rules stop a
/// student reading other students' `users` documents or any `adminUsers`
/// document: the checks that needed such reads now run on the server.
///
/// Region asia-south1, like every other function this app calls.
typedef StudentCallableInvoker = Future<Map<String, dynamic>> Function(
    String name, Map<String, dynamic> data);

class StudentApi {
  StudentApi(this._invoke);

  static StudentApi instance = StudentApi(_defaultInvoke);

  /// Swaps the transport in tests.
  @visibleForTesting
  static void useForTests(StudentCallableInvoker? invoker) =>
      instance = StudentApi(invoker ?? _defaultInvoke);

  final StudentCallableInvoker _invoke;

  static Future<Map<String, dynamic>> _defaultInvoke(
      String name, Map<String, dynamic> data) async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable(name)
        .call<dynamic>(data);
    final raw = result.data;
    return raw is Map ? _deepMap(raw) : <String, dynamic>{};
  }

  static Map<String, dynamic> _deepMap(Map raw) =>
      {for (final e in raw.entries) e.key.toString(): _deep(e.value)};

  static dynamic _deep(dynamic v) {
    if (v is Map) return _deepMap(v);
    if (v is List) return v.map(_deep).toList();
    return v;
  }

  /// Registration: is this name free? Compared trimmed, whitespace-collapsed
  /// and case-folded, ignoring manual entries and your own saved name.
  Future<bool> checkNameAvailable(String name) async {
    final r = await _invoke('checkNameAvailable', {'name': name});
    final available = r['available'];
    if (available is! bool) {
      throw StateError('Unexpected answer from checkNameAvailable');
    }
    return available;
  }

  /// Registration: does a guide already have this mobile number on the manual
  /// roster? [role] is the residence the guide recorded, only for a UNIQUE match.
  Future<({int count, String role})> findManualMatch(String mobile) async {
    final r = await _invoke('findManualMatch', {'mobile': mobile});
    return (
      count: (r['count'] as num?)?.toInt() ?? 0,
      role: (r['role'] ?? '').toString(),
    );
  }

  /// "My Guide": the display name of the admin you are assigned to ('' = none).
  Future<({String displayName, String role})> getMyGuide() async {
    final r = await _invoke('getMyGuide', {});
    return (
      displayName: (r['displayName'] ?? '').toString(),
      role: (r['role'] ?? '').toString(),
    );
  }

  /// Your gender plus the names / uids of the female students (what the app used
  /// to build by reading every `users` document).
  /// [category] is the student's competition category: `folk` or
  /// `hostel_localite` (an older server that does not send it means `folk`).
  Future<({String mine, String category, Set<String> femaleNames, Set<String> femaleUids})>
      getGenderDirectory() async {
    final r = await _invoke('getGenderDirectory', {});
    Set<String> set(Object? v) =>
        {for (final x in (v as List? ?? const [])) x.toString()};
    return (
      mine: (r['mine'] ?? 'male').toString(),
      category: (r['category'] ?? 'folk').toString(),
      femaleNames: set(r['femaleNames']),
      femaleUids: set(r['femaleUids']),
    );
  }

  /// Friend search: students of YOUR gender whose name contains [query].
  Future<List<Map<String, dynamic>>> searchStudents(String query) async {
    final r = await _invoke('searchStudents', {'query': query});
    return [
      for (final x in (r['results'] as List? ?? const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
  }

  /// Accepts a pending friend request addressed to you (the server writes both
  /// friend lists).
  Future<void> acceptFriendRequest(String requestId) async {
    await _invoke('acceptFriendRequest', {'requestId': requestId});
  }
}
