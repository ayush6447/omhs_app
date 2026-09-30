import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/format.dart';

/// User preferences, persisted on the device.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this._themeMode, this._unit, this._bodyUnits,
      this._language, this._setupDone);

  static const _kTheme = 'themeMode';
  static const _kUnit = 'cholUnit';
  static const _kBody = 'bodyUnits';
  static const _kLanguage = 'language';
  static const _kSetupDone = 'setupDone';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  CholUnit _unit;
  BodyUnits _bodyUnits;
  String? _language;
  bool _setupDone;

  ThemeMode get themeMode => _themeMode;
  CholUnit get unit => _unit;
  BodyUnits get bodyUnits => _bodyUnits;

  /// Language code ('en', 'hi'), or null to follow the phone.
  String? get language => _language;
  Locale? get locale => _language == null ? null : Locale(_language!);

  /// Whether the first-run profile setup has been shown.
  bool get setupDone => _setupDone;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.firstWhere((v) => v.name == prefs.getString(key),
            orElse: () => fallback);
    return AppSettings._(
      prefs,
      pick(ThemeMode.values, _kTheme, ThemeMode.system),
      pick(CholUnit.values, _kUnit, CholUnit.mgdl),
      pick(BodyUnits.values, _kBody, BodyUnits.metric),
      prefs.getString(_kLanguage),
      prefs.getBool(_kSetupDone) ?? false,
    );
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

  Future<void> setBodyUnits(BodyUnits units) async {
    if (units == _bodyUnits) return;
    _bodyUnits = units;
    notifyListeners();
    await _prefs.setString(_kBody, units.name);
  }

  Future<void> setLanguage(String? code) async {
    if (code == _language) return;
    _language = code;
    notifyListeners();
    if (code == null) {
      await _prefs.remove(_kLanguage);
    } else {
      await _prefs.setString(_kLanguage, code);
    }
  }

  Future<void> markSetupDone() async {
    if (_setupDone) return;
    _setupDone = true;
    await _prefs.setBool(_kSetupDone, true);
  }
}
