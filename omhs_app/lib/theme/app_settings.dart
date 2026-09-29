import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/format.dart';

/// User preferences, persisted on the device.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this._themeMode, this._unit);

  static const _kTheme = 'themeMode';
  static const _kUnit = 'cholUnit';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  CholUnit _unit;

  ThemeMode get themeMode => _themeMode;
  CholUnit get unit => _unit;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString(_kTheme),
      orElse: () => ThemeMode.system,
    );
    final unit = CholUnit.values.firstWhere(
      (u) => u.name == prefs.getString(_kUnit),
      orElse: () => CholUnit.mgdl,
    );
    return AppSettings._(prefs, mode, unit);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kTheme, mode.name);
  }

  /// Flip between light and dark based on what is currently on screen.
  Future<void> toggleDark(Brightness current) => setThemeMode(
        current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
      );

  Future<void> setUnit(CholUnit unit) async {
    if (unit == _unit) return;
    _unit = unit;
    notifyListeners();
    await _prefs.setString(_kUnit, unit.name);
  }
}
