import 'package:flutter/material.dart';
import '../services/app_sqlite_service.dart';

class ThemeProvider with ChangeNotifier {
  // ThemeMode _themeMode = ThemeMode.light;
  //
  // ThemeMode get themeMode => _themeMode;
  // bool get isDarkMode => _themeMode == ThemeMode.dark;
  //
  // ThemeProvider() {
  //   _loadThemeMode();
  // }
  // Gene - Nov, 23, 2026: Allow disabling SQLite load/save in widget tests to prevent sqflite FakeAsync pending timer failures
  ThemeMode _themeMode;
  final bool _persistSettings;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider({
    bool persistSettings = true,
    ThemeMode initialMode = ThemeMode.light,
  }) : _persistSettings = persistSettings,
       _themeMode = initialMode {
    if (_persistSettings) {
      _loadThemeMode();
    }
  }

  Future<void> _loadThemeMode() async {
    try {
      final savedMode = await AppSqliteService().getGlobalSetting(
        'app_theme_mode',
      );
      if (savedMode == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (savedMode == 'system') {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
      notifyListeners();
    } catch (_) {}
  }

  // Future<void> toggleTheme() async {
  //   if (_themeMode == ThemeMode.dark) {
  //     _themeMode = ThemeMode.light;
  //   } else {
  //     _themeMode = ThemeMode.dark;
  //   }
  //   notifyListeners();
  //   try {
  //     await AppSqliteService().setGlobalSetting(
  //       'app_theme_mode',
  //       _themeMode == ThemeMode.light ? 'light' : 'dark',
  //     );
  //   } catch (_) {}
  // }
  //
  // Future<void> setThemeMode(ThemeMode mode) async {
  //   _themeMode = mode;
  //   notifyListeners();
  //   String modeStr = 'dark';
  //   if (mode == ThemeMode.light) modeStr = 'light';
  //   if (mode == ThemeMode.system) modeStr = 'system';
  //   try {
  //     await AppSqliteService().setGlobalSetting('app_theme_mode', modeStr);
  //   } catch (_) {}
  // }
  // Gene - Nov, 23, 2026: Guard SQLite writes in toggleTheme/setThemeMode when _persistSettings is false
  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.dark) {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.dark;
    }
    notifyListeners();
    if (!_persistSettings) return;
    try {
      await AppSqliteService().setGlobalSetting(
        'app_theme_mode',
        _themeMode == ThemeMode.light ? 'light' : 'dark',
      );
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    if (!_persistSettings) return;
    String modeStr = 'dark';
    if (mode == ThemeMode.light) modeStr = 'light';
    if (mode == ThemeMode.system) modeStr = 'system';
    try {
      await AppSqliteService().setGlobalSetting('app_theme_mode', modeStr);
    } catch (_) {}
  }
}
