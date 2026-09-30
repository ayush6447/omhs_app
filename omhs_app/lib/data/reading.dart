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
}
