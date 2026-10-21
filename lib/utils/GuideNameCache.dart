import 'package:shared_preferences/shared_preferences.dart';

/// The assigned guide's display name, remembered on the phone ("My Guide" shows it at once on the next visit, even before
/// the user document arrives or while offline). The server keeps the real value on the student's own user document
/// (`users.guideName`); this is only a local copy of the last one seen. Any failure just means "no cached name".
/// The guide name the server stamped on the student's user document (`guideName`): the string ('' = no guide assigned), or
/// null when the document has not been stamped yet (the app then asks the `getMyGuide` callable once, as before).
String? stampedGuideName(Map<String, dynamic>? data) {
  final v = data == null ? null : data['guideName'];
  return v is String ? v.trim() : null;
}

abstract final class GuideNameCache {
  static String _key(String uid) => 'my-guide-name-$uid';

  static Future<String?> read(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key(uid));
      return v == null || v.trim().isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String uid, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(uid), name);
    } catch (_) {}
  }
}
