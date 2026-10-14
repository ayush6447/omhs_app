import 'package:flutter/foundation.dart';

enum ReminderRepeat { daily, weekly }

/// When to remind the user to measure. Saved in AppSettings.
@immutable
class ReminderSchedule {
  const ReminderSchedule({
    this.enabled = false,
    this.repeat = ReminderRepeat.daily,
    this.weekday = DateTime.monday,
    this.hour = 9,
    this.minute = 0,
  });

  final bool enabled;
  final ReminderRepeat repeat;

  /// [DateTime.monday]..[DateTime.sunday]; used when weekly.
  final int weekday;
  final int hour;
  final int minute;

  ReminderSchedule copyWith({
    bool? enabled,
    ReminderRepeat? repeat,
    int? weekday,
    int? hour,
    int? minute,
  }) =>
      ReminderSchedule(
        enabled: enabled ?? this.enabled,
        repeat: repeat ?? this.repeat,
        weekday: weekday ?? this.weekday,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  /// e.g. "Every day at 09:00" or "Every Monday at 18:30"
  String describe() {
    final time = '${_two(hour)}:${_two(minute)}';
    return repeat == ReminderRepeat.daily
        ? 'Every day at $time'
        : 'Every ${weekdayName(weekday)} at $time';
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'repeat': repeat.name,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
      };

  factory ReminderSchedule.fromJson(Map<String, dynamic> j) {
    int pick(String key, int min, int max, int fallback) {
      final v = j[key];
      return v is int && v >= min && v <= max ? v : fallback;
    }

    return ReminderSchedule(
      enabled: j['enabled'] as bool? ?? false,
      repeat: ReminderRepeat.values.firstWhere((r) => r.name == j['repeat'],
          orElse: () => ReminderRepeat.daily),
      weekday: pick('weekday', DateTime.monday, DateTime.sunday, 1),
      hour: pick('hour', 0, 23, 9),
      minute: pick('minute', 0, 59, 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSchedule &&
      other.enabled == enabled &&
      other.repeat == repeat &&
      other.weekday == weekday &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, repeat, weekday, hour, minute);
}

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

String weekdayName(int weekday) => _weekdayNames[weekday - 1];

String _two(int n) => n.toString().padLeft(2, '0');

/// First time [s] fires strictly after [now]. [make] builds a date in the
/// right time zone (a TZDateTime for scheduling); plain local DateTime by
/// default. Days are stepped by calendar date, so DST changes keep the
/// wall-clock time.
DateTime nextReminder(DateTime now, ReminderSchedule s,
    [DateTime Function(int year, int month, int day, int hour, int minute)
        make = DateTime.new]) {
  for (var day = 0; day <= 7; day++) {
    final t = make(now.year, now.month, now.day + day, s.hour, s.minute);
    final dayOk =
        s.repeat == ReminderRepeat.daily || t.weekday == s.weekday;
    if (dayOk && t.isAfter(now)) return t;
  }
  throw StateError('unreachable');
}
