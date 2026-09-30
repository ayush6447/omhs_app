import 'package:flutter/foundation.dart';

/// One completed measurement.
@immutable
class Reading {
  const Reading({
    required this.id,
    required this.time,
    required this.totalChol,
    required this.quality,
    required this.ch1mA,
    required this.ch2mA,
    required this.peakPressure,
    this.flagged = false,
    this.note,
    this.profileId,
  });

  final String id;
  final DateTime time;

  /// Estimated total cholesterol, mg/dL.
  final double totalChol;

  /// Signal quality reported by the device, 0..1.
  final double quality;

  /// LED currents from ISENSE1 / ISENSE2 at the time of the result, mA.
  final double ch1mA;
  final double ch2mA;

  /// Peak cuff pressure during the cycle, mmHg.
  final double peakPressure;

  final bool flagged;
  final String? note;

  /// Whose reading this is (see ProfileStore). Null until the store tags it.
  final String? profileId;

  Reading copyWith({bool? flagged, String? note, String? profileId}) =>
      Reading(
        id: id,
        time: time,
        totalChol: totalChol,
        quality: quality,
        ch1mA: ch1mA,
        ch2mA: ch2mA,
        peakPressure: peakPressure,
        flagged: flagged ?? this.flagged,
        note: note ?? this.note,
        profileId: profileId ?? this.profileId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'totalChol': totalChol,
        'quality': quality,
        'ch1mA': ch1mA,
        'ch2mA': ch2mA,
        'peakPressure': peakPressure,
        'flagged': flagged,
        'note': note,
        'profileId': profileId,
      };

  factory Reading.fromJson(Map<String, dynamic> j) => Reading(
        id: j['id'] as String,
        time: DateTime.parse(j['time'] as String),
        totalChol: (j['totalChol'] as num).toDouble(),
        quality: (j['quality'] as num).toDouble(),
        ch1mA: (j['ch1mA'] as num).toDouble(),
        ch2mA: (j['ch2mA'] as num).toDouble(),
        peakPressure: (j['peakPressure'] as num).toDouble(),
        flagged: j['flagged'] as bool? ?? false,
        note: j['note'] as String?,
        profileId: j['profileId'] as String?,
      );
}
