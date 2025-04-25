// --- File: lib/services/theme_service.dart ---

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart'; // Import constants

// Service to manage theme preferences
class ThemeService with ChangeNotifier {
  // Singleton pattern
  static final ThemeService instance = ThemeService._internal();
  ThemeService._internal();

  ThemeMode _themeMode = ThemeMode.dark;
  Color _selectedSeedColor = Colors.blueGrey;
  bool _useAmoledDark = false;
  SharedPreferences? _prefs;

  // Getters
  ThemeMode get themeMode => _themeMode;
  Color get selectedSeedColor => _selectedSeedColor;
  bool get useAmoledDark => _useAmoledDark;

  // Load theme preferences from SharedPreferences
  Future<void> loadTheme() async {
    _prefs = await SharedPreferences.getInstance();

    // Load Theme Mode
    String? savedThemeMode = _prefs?.getString(themeModePrefKey);
    print("Loaded theme mode preference: $savedThemeMode");
    if (savedThemeMode == 'light') {
      _themeMode = ThemeMode.light;
    } else { // Default to dark if null or 'dark' or invalid
      _themeMode = ThemeMode.dark;
    }

    // Load Seed Color
    int? savedColorValue = _prefs?.getInt(themeSeedColorPrefKey);
    print("Loaded theme color preference: $savedColorValue");
    if (savedColorValue != null) {
        _selectedSeedColor = Color(savedColorValue);
    } else {
        _selectedSeedColor = Colors.blueGrey; // Default color
    }

    // Load AMOLED Preference
    _useAmoledDark = _prefs?.getBool(useAmoledDarkPrefKey) ?? false; // Default to false
    print("Loaded AMOLED preference: $_useAmoledDark");

    // No need to notify listeners here as it's called before runApp
  }

  // Toggle theme mode and save preference
  Future<void> toggleTheme() async {
    _themeMode = (_themeMode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    print("Theme mode toggled to: $_themeMode");
    final String themeString = (_themeMode == ThemeMode.light) ? 'light' : 'dark';
    await _prefs?.setString(themeModePrefKey, themeString);
    print("Saved theme mode preference: $themeString");
    notifyListeners(); // Notify listeners to rebuild UI
  }

  // Change seed color and save preference
  Future<void> changeSeedColor(Color newColor) async {
     if (_selectedSeedColor == newColor) return; // No change needed

     _selectedSeedColor = newColor;
     print("Theme seed color changed to: $_selectedSeedColor");
     await _prefs?.setInt(themeSeedColorPrefKey, newColor.value);
     print("Saved theme color preference: ${newColor.value}");
     notifyListeners(); // Notify listeners to rebuild UI
  }

  // Toggle and save AMOLED preference
  Future<void> setAmoledDark(bool value) async {
     if (_useAmoledDark == value) return; // No change
     _useAmoledDark = value;
     print("AMOLED dark theme preference set to: $_useAmoledDark");
     await _prefs?.setBool(useAmoledDarkPrefKey, value);
     print("Saved AMOLED preference: $value");
     notifyListeners();
  }
}