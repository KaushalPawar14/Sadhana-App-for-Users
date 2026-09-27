import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Force-update gate — follow-up task, 2026-09-10. Mirrors the Guide app's
/// own `utils/ForceUpdateCheck.dart` exactly (same document, same
/// reasoning — see that file's own header for the full Rule 12
/// justification and the "fails open everywhere" contract) except this
/// app reads the `students` field of the shared `appConfig/versions`
/// document rather than `guides`.
class ForceUpdateCheck {
  static const Duration _timeout = Duration(seconds: 6);

  static Future<bool> isUpdateRequired() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('versions')
          .get()
          .timeout(_timeout);

      if (!snap.exists) return false;

      final appField = snap.data()?['students'];
      if (appField is! Map) return false;

      final minBuild = appField['minBuildNumber'];
      if (minBuild is! int) return false;

      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber);
      if (currentBuild == null) return false;

      return currentBuild < minBuild;
    } catch (_) {
      return false;
    }
  }
}
