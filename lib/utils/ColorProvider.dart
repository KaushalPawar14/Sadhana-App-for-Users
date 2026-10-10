import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/ThemeModeController.dart';

class ColorProvider with ChangeNotifier {
  Color _color = Colors.white;  // Main color (default white)
  Color _secondColor = Colors.black;  // Second color (default black)
  Color _thirdColor = Color(0xFF835DF1);
  Color _fourthColor = Colors.white70;

  Color get color => _color;
  Color get secondColor => _secondColor;
  Color get thirdColor => _thirdColor;
  Color get fourthColor => _fourthColor;

  ThemeModeController? _themeController;

  // Constructor to load saved color preferences when the app starts. The app
  // root passes loadLegacyPrefs: false and calls bindTo, so the Light/Dark/Auto
  // setting is the only thing that decides these colours.
  ColorProvider({bool loadLegacyPrefs = true}) {
    if (loadLegacyPrefs) _loadColorPreferences();
  }

  // Makes every screen that reads these colours follow the Light/Dark/Auto
  // setting. Sets the colours now (no notification, so it is safe during
  // build) and again whenever the setting or the system brightness changes.
  void bindTo(ThemeModeController controller) {
    _themeController?.removeListener(_followTheme);
    _themeController = controller;
    controller.addListener(_followTheme);
    _applyDark(controller.isDark);
  }

  void _followTheme() {
    _applyDark(_themeController!.isDark);
    notifyListeners();
  }

  void _applyDark(bool dark) {
    if (dark) {
      _color = Colors.black87;
      _secondColor = Colors.white;
      _thirdColor = Color(0xFF835DF1);
      _fourthColor = Colors.grey[850]!;
    } else {
      _color = Colors.white;
      _secondColor = Colors.black;
      _thirdColor = Color(0xFF835DF1);
      _fourthColor = Colors.white70;
    }
  }

  // Load color preferences from shared preferences
  Future<void> _loadColorPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isDarkMode = prefs.getBool('isDarkMode');

    if (isDarkMode == null || !isDarkMode) {
      // If no preference is saved, or it's false, set default light mode
      _color = Colors.white;
      _secondColor = Colors.black;
      _thirdColor = Color(0xFF835DF1);
      _fourthColor = Colors.white70;
    } else {
      // If dark mode is saved, set to dark mode
      _color = Colors.black87;
      _secondColor = Colors.white;
      _thirdColor = Color(0xFF835DF1);
      _fourthColor = Colors.grey[850]!;
    }
    notifyListeners();
  }

  // Toggle between white/black87 for the main color and between black/white for the second color
  Future<void> toggleColor() async {
    final controller = _themeController;
    if (controller != null) {
      await controller.setMode(
          controller.isDark ? FolkThemeMode.light : FolkThemeMode.dark);
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (_color == Colors.white) {
      _color = Colors.black87;  // Change main color to black87
      _secondColor = Colors.white;  // Change second color to white
      _thirdColor = Color(0xFF835DF1);
      _fourthColor = Colors.grey[850]!;

      // Save the dark mode preference to SharedPreferences
      prefs.setBool('isDarkMode', true);
    } else {
      _color = Colors.white;  // Change main color to white
      _secondColor = Colors.black;  // Change second color to black
      _thirdColor = Color(0xFF835DF1);
      _fourthColor = Colors.white70;

      // Save the light mode preference to SharedPreferences
      prefs.setBool('isDarkMode', false);
    }
    notifyListeners();  // Notify listeners to rebuild UI
  }
}
