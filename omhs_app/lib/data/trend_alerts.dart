import 'format.dart';
import 'reading.dart';

enum AlertKind {
  /// Signal too weak to trust the number.
  lowQuality,

  /// In the high band.
  high,

  /// Moved into a worse band than the previous reading.
  worseCategory,

  /// Well above the average of the readings before it.
  rising,
}

/// Something worth pointing out about the latest reading.
class TrendAlert {
  const TrendAlert(this.kind, {this.deltaMgdl, this.from, this.to});

  final AlertKind kind;

  /// [AlertKind.rising]: how far above the recent average, mg/dL.
  final double? deltaMgdl;

  /// [AlertKind.worseCategory]: previous and new band.
  final CholCategory? from;
  final CholCategory? to;

  /// The high-band and low-quality alerts are shown in red.
  bool get serious => kind == AlertKind.high || kind == AlertKind.lowQuality;

  String title(CholUnit unit) => switch (kind) {
        AlertKind.lowQuality => 'Weak signal',
        AlertKind.high => 'High reading',
        AlertKind.worseCategory =>
          '${categoryLabel(from!)} → ${categoryLabel(to!)}',
        AlertKind.rising =>
          'Up ${formatChol(deltaMgdl!, unit)} ${unitLabel(unit)}',
      };

  String message(CholUnit unit) => switch (kind) {
        AlertKind.lowQuality => 'This result may be off. Keep your hand '
            'still and warm, then measure again.',
        AlertKind.high => 'Measure again to confirm. If it stays high, '
            'talk to a doctor.',
        AlertKind.worseCategory => 'Higher band than your previous reading.',
        AlertKind.rising => 'Above the average of your previous '
            '$_baselineCount readings.',
      };
}

/// Below this, the result is flagged as unreliable.
const kMinQuality = 0.6;

/// Readings averaged for the rising check, and how old they may be.
const _baselineCount = 3;
const _baselineWindow = Duration(days: 90);

/// A rise counts when it's at least this much above the average.
const _riseMgdl = 20.0;
const _riseFraction = 0.10;

/// Alerts for the newest of [readings] (newest first, one profile), most
/// important first. [ageAt] gives the person's age on a date, for the bands.
/// A weak-signal reading only gets that alert: its number isn't trusted.
List<TrendAlert> trendAlerts(List<Reading> readings,
    {int? Function(DateTime)? ageAt}) {
  if (readings.isEmpty) return const [];
  final latest = readings.first;
  if (latest.quality < kMinQuality) {
    return const [TrendAlert(AlertKind.lowQuality)];
  }

  CholCategory band(Reading r) =>
      categorize(r.totalChol, age: ageAt?.call(r.time));
  final now = band(latest);
  final alerts = <TrendAlert>[
    if (now == CholCategory.high) const TrendAlert(AlertKind.high),
  ];

  // Earlier readings worth comparing with: trusted and recent.
  final earlier = [
    for (final r in readings.skip(1))
      if (r.quality >= kMinQuality &&
          latest.time.difference(r.time) <= _baselineWindow)
        r,
  ];
  if (earlier.isNotEmpty) {
    final before = band(earlier.first);
    if (now.index > before.index) {
      alerts.add(TrendAlert(AlertKind.worseCategory, from: before, to: now));
    }
  }
  if (earlier.length >= _baselineCount) {
    final base = earlier
            .take(_baselineCount)
            .fold<double>(0, (sum, r) => sum + r.totalChol) /
        _baselineCount;
    final delta = latest.totalChol - base;
    if (delta >= _riseMgdl && delta >= base * _riseFraction) {
      alerts.add(TrendAlert(AlertKind.rising, deltaMgdl: delta));
    }
  }
  return alerts;
}
