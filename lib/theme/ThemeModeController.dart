import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FolkThemeMode { light, dark, auto }

// The Light / Dark / Auto choice. Stored on this device only (SharedPreferences),
// never in Firestore. Auto follows the system brightness.
class ThemeModeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeModeController._(this._prefs, this._mode) {
    WidgetsBinding.instance.addObserver(this);
  }

  static const String prefsKey = 'folk_theme_mode';
  static const String _legacyKey = 'isDarkMode';

  final SharedPreferences _prefs;
  FolkThemeMode _mode;

  // First launch with the new setting: an old explicit choice is kept
  // (isDarkMode true -> Dark, false -> Light); no old value -> Auto.
  static Future<ThemeModeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    var mode = _parse(prefs.getString(prefsKey));
    if (mode == null) {
      final legacy = prefs.getBool(_legacyKey);
      mode = legacy == null
          ? FolkThemeMode.auto
          : (legacy ? FolkThemeMode.dark : FolkThemeMode.light);
      await prefs.setString(prefsKey, mode.name);
    }
    return ThemeModeController._(prefs, mode);
  }

  static FolkThemeMode? _parse(String? value) {
    for (final m in FolkThemeMode.values) {
      if (m.name == value) return m;
    }
    return null;
  }

  FolkThemeMode get mode => _mode;

  ThemeMode get themeMode => switch (_mode) {
        FolkThemeMode.light => ThemeMode.light,
        FolkThemeMode.dark => ThemeMode.dark,
        FolkThemeMode.auto => ThemeMode.system,
      };

  bool get isDark => switch (_mode) {
        FolkThemeMode.light => false,
        FolkThemeMode.dark => true,
        FolkThemeMode.auto =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  Future<void> setMode(FolkThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs.setString(prefsKey, mode.name);
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == FolkThemeMode.auto) notifyListeners();
  }
}
