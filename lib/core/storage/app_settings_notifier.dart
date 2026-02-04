import 'package:flutter/material.dart';

import 'settings_service.dart';

/// Notifier for app-wide settings that affect UI (theme, font scale).
/// Listen to rebuild MaterialApp when these change.
class AppSettingsNotifier extends ChangeNotifier {
  AppSettingsNotifier() {
    _themeMode = _themeModeFromString(settingsService.themeMode);
    _fontScale = settingsService.fontSize;
  }

  late ThemeMode _themeMode;
  late double _fontScale;

  ThemeMode get themeMode => _themeMode;
  double get fontScale => _fontScale;

  static ThemeMode _themeModeFromString(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await settingsService.setThemeMode(_themeModeToString(mode));
    notifyListeners();
  }

  Future<void> setThemeModeFromString(String mode) async {
    await setThemeMode(_themeModeFromString(mode));
  }

  Future<void> setFontScale(double scale) async {
    if ((_fontScale - scale).abs() < 0.01) return;
    _fontScale = scale.clamp(0.8, 1.4);
    await settingsService.setFontSize(_fontScale);
    notifyListeners();
  }

  void loadFromStorage() {
    _themeMode = _themeModeFromString(settingsService.themeMode);
    _fontScale = settingsService.fontSize;
    notifyListeners();
  }
}

final appSettingsNotifier = AppSettingsNotifier();
