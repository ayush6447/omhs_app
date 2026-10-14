import 'package:flutter_test/flutter_test.dart';
import 'package:omhs_app/data/format.dart';
import 'package:omhs_app/data/reading.dart';
import 'package:omhs_app/data/reminders.dart';
import 'package:omhs_app/data/trend_alerts.dart';

final _now = DateTime(2026, 10, 14, 9);

/// [values] newest first, one day apart.
List<Reading> _readings(List<double> values, {double quality = 0.9}) => [
      for (var i = 0; i < values.length; i++)
        Reading(
          id: '$i',
          time: _now.subtract(Duration(days: i)),
          totalChol: values[i],
          quality: i == 0 ? quality : 0.9,
          ch1mA: 50,
          ch2mA: 50,
          peakPressure: 180,
        ),
    ];

List<AlertKind> _kinds(List<Reading> r, {int? age}) =>
    [for (final a in trendAlerts(r, ageAt: (_) => age)) a.kind];

void main() {
  group('trend alerts', () {
    test('nothing to say', () {
      expect(_kinds([]), isEmpty);
      expect(_kinds(_readings([180])), isEmpty);
      expect(_kinds(_readings([182, 180, 178, 181])), isEmpty);
    });

    test('weak signal replaces every other alert', () {
      expect(_kinds(_readings([260, 180, 180, 180], quality: 0.4)),
          [AlertKind.lowQuality]);
    });

    test('high, worse band and rising together', () {
      expect(_kinds(_readings([250, 190, 185, 195])), [
        AlertKind.high,
        AlertKind.worseCategory,
        AlertKind.rising,
      ]);
      final worse = trendAlerts(_readings([210, 190]))
          .firstWhere((a) => a.kind == AlertKind.worseCategory);
      expect(worse.title(CholUnit.mgdl), 'Desirable → Borderline');
    });

    test('rising needs three earlier readings and a real jump', () {
      expect(_kinds(_readings([195, 170, 172])), isEmpty);
      final rise = trendAlerts(_readings([195, 170, 172, 174])).single;
      expect(rise.kind, AlertKind.rising);
      expect(rise.deltaMgdl, closeTo(23, 0.01));
      expect(rise.title(CholUnit.mgdl), 'Up 23 mg/dL');
      // 15 mg/dL is under the threshold.
      expect(_kinds(_readings([187, 172, 172, 172])), isEmpty);
    });

    test('readings older than 90 days are not compared', () {
      final old = _readings([190, 150, 150, 150]);
      final shifted = [
        old.first,
        for (final r in old.skip(1))
          Reading(
            id: r.id,
            time: r.time.subtract(const Duration(days: 120)),
            totalChol: r.totalChol,
            quality: r.quality,
            ch1mA: r.ch1mA,
            ch2mA: r.ch2mA,
            peakPressure: r.peakPressure,
          ),
      ];
      expect(_kinds(shifted), isEmpty);
    });

    test('bands follow age', () {
      expect(_kinds(_readings([205]), age: 15), [AlertKind.high]);
      expect(_kinds(_readings([205]), age: 40), isEmpty);
    });
  });

  group('reminders', () {
    const daily = ReminderSchedule(enabled: true, hour: 9, minute: 30);
    final weekly = daily.copyWith(
        repeat: ReminderRepeat.weekly, weekday: DateTime.friday);

    test('next daily reminder', () {
      expect(nextReminder(DateTime(2026, 10, 14, 8), daily),
          DateTime(2026, 10, 14, 9, 30));
      // At or after the time today: tomorrow.
      expect(nextReminder(DateTime(2026, 10, 14, 9, 30), daily),
          DateTime(2026, 10, 15, 9, 30));
      expect(nextReminder(DateTime(2026, 12, 31, 22), daily),
          DateTime(2027, 1, 1, 9, 30));
    });

    test('next weekly reminder', () {
      // 14 Oct 2026 is a Wednesday.
      expect(nextReminder(DateTime(2026, 10, 14, 12), weekly),
          DateTime(2026, 10, 16, 9, 30));
      expect(nextReminder(DateTime(2026, 10, 16, 10), weekly),
          DateTime(2026, 10, 23, 9, 30));
    });

    test('describe and json', () {
      expect(daily.describe(), 'Every day at 09:30');
      expect(weekly.describe(), 'Every Friday at 09:30');
      expect(ReminderSchedule.fromJson(weekly.toJson()), weekly);
      final junk = ReminderSchedule.fromJson(
          const {'enabled': true, 'repeat': 'hourly', 'hour': 99, 'weekday': 0});
      expect(junk.repeat, ReminderRepeat.daily);
      expect(junk.hour, 9);
      expect(junk.weekday, DateTime.monday);
    });
  });
}
