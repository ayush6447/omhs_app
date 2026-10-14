import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/format.dart';
import '../data/reminders.dart';

/// User preferences, persisted on the device.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this._themeMode, this._unit, this._bodyUnits,
      this._setupDone, this._reminder);

  static const _kTheme = 'themeMode';
  static const _kUnit = 'cholUnit';
  static const _kBody = 'bodyUnits';
  static const _kSetupDone = 'setupDone';
  static const _kReminder = 'reminder';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  CholUnit _unit;
  BodyUnits _bodyUnits;
  bool _setupDone;
  ReminderSchedule _reminder;

  ThemeMode get themeMode => _themeMode;
  CholUnit get unit => _unit;
  BodyUnits get bodyUnits => _bodyUnits;

  /// Whether the first-run profile setup has been shown.
  bool get setupDone => _setupDone;

  ReminderSchedule get reminder => _reminder;

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
      prefs.getBool(_kSetupDone) ?? false,
      _loadReminder(prefs.getString(_kReminder)),
    );
  }

  static ReminderSchedule _loadReminder(String? json) {
    if (json == null) return const ReminderSchedule();
    try {
      return ReminderSchedule.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return const ReminderSchedule();
    }
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

  /// Saves the schedule only; NotificationService does the scheduling.
  Future<void> setReminder(ReminderSchedule r) async {
    if (r == _reminder) return;
    _reminder = r;
    notifyListeners();
    await _prefs.setString(_kReminder, jsonEncode(r.toJson()));
  }

  Future<void> markSetupDone() async {
    if (_setupDone) return;
    _setupDone = true;
    await _prefs.setBool(_kSetupDone, true);
  }
}
