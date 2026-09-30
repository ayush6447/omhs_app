import 'dart:async';

import 'package:flutter/foundation.dart';

import '../device/device_service.dart';
import 'reading.dart';
import 'user_profile.dart';

/// Measurement history for every profile; [items] shows the active one's.
/// In-memory for now; swap in sqflite/Hive later.
class ReadingsStore extends ChangeNotifier {
  ReadingsStore(DeviceService device, this._profiles,
      {bool seedDemoData = false}) {
    _sub = device.results.listen(add);
    _activeId = _profiles.activeId;
    _profiles.addListener(_onProfilesChanged);
    if (seedDemoData) _all.addAll(_demoReadings(_activeId));
  }

  final ProfileStore _profiles;
  late final StreamSubscription<Reading> _sub;
  late String _activeId;

  /// All profiles, newest first.
  final List<Reading> _all = [];

  /// The active profile's readings, newest first.
  List<Reading> get items => List.unmodifiable(
      _all.where((r) => r.profileId == _profiles.activeId));

  void _onProfilesChanged() {
    if (_profiles.activeId == _activeId) return;
    _activeId = _profiles.activeId;
    notifyListeners();
  }

  Reading? get latest {
    for (final r in _all) {
      if (r.profileId == _profiles.activeId) return r;
    }
    return null;
  }

  Reading? byId(String id) {
    for (final r in _all) {
      if (r.id == id) return r;
    }
    return null;
  }

  int countSince(DateTime since) =>
      items.where((r) => r.time.isAfter(since)).length;

  /// Stores a new reading under the active profile.
  void add(Reading r) {
    _all.insert(0, r.copyWith(profileId: _profiles.activeId));
    notifyListeners();
  }

  void removeForProfile(String profileId) {
    _all.removeWhere((r) => r.profileId == profileId);
    notifyListeners();
  }

  void toggleFlag(String id) => _update(id, (r) => r.copyWith(flagged: !r.flagged));

  void setNote(String id, String note) => _update(id, (r) => r.copyWith(note: note));

  void _update(String id, Reading Function(Reading) change) {
    final i = _all.indexWhere((r) => r.id == id);
    if (i < 0) return;
    _all[i] = change(_all[i]);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    _profiles.removeListener(_onProfilesChanged);
    super.dispose();
  }

  static List<Reading> _demoReadings(String profileId) {
    final now = DateTime.now();
    const chol = [182.0, 176.0, 204.0, 191.0, 169.0, 243.0, 188.0, 199.0];
    const quality = [0.91, 0.88, 0.79, 0.93, 0.86, 0.72, 0.90, 0.84];
    const notes = <String?>[
      'Morning, fasting',
      null,
      'After lunch',
      null,
      'Clinic visit',
      'Cold hands, low signal',
      null,
      'Repeat of previous',
    ];
    return List.generate(chol.length, (i) {
      final t = now.subtract(Duration(hours: 5 + i * 34));
      return Reading(
        id: 'demo-$i',
        time: t,
        totalChol: chol[i],
        quality: quality[i],
        ch1mA: 50.1 - i * 0.1,
        ch2mA: 49.7 + i * 0.05,
        peakPressure: 178.0 + (i % 3) * 2,
        flagged: i == 5,
        note: notes[i],
        profileId: profileId,
      );
    });
  }
}
