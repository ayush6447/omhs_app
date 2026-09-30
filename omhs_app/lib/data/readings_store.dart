import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../device/device_service.dart';
import 'reading.dart';
import 'user_profile.dart';

/// Measurement history for every profile; [items] shows the active one's.
/// Saved to a JSON file in app storage after every change.
class ReadingsStore extends ChangeNotifier {
  @visibleForTesting
  ReadingsStore(DeviceService device, this._profiles, this._file,
      [List<Reading> initial = const []]) {
    _all.addAll(initial);
    _sortNewestFirst();
    _sub = device.results.listen(add);
    _activeId = _profiles.activeId;
    _profiles.addListener(_onProfilesChanged);
  }

  /// Reads saved history. With [seedDemoData], an empty history is filled
  /// with sample readings for the active profile (for the simulated device).
  static Future<ReadingsStore> load(DeviceService device, ProfileStore profiles,
      {bool seedDemoData = false}) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/readings.json');
    var initial = await readFile(file);
    if (initial.isEmpty && seedDemoData) {
      initial = _demoReadings(profiles.activeId);
    }
    return ReadingsStore(device, profiles, file, initial);
  }

  @visibleForTesting
  static Future<List<Reading>> readFile(File file) async {
    if (!await file.exists()) return [];
    try {
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      return [for (final j in list) Reading.fromJson(j as Map<String, dynamic>)];
    } catch (e) {
      // Keep the unreadable file instead of overwriting it on the next save.
      debugPrint('readings.json unreadable ($e); moved aside');
      await file.rename('${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      return [];
    }
  }

  final ProfileStore _profiles;
  final File _file;
  late final StreamSubscription<Reading> _sub;
  late String _activeId;
  Future<void> _pendingSave = Future.value();

  /// All profiles, newest first.
  final List<Reading> _all = [];

  /// Every reading of every profile, newest first (for backups).
  List<Reading> get all => List.unmodifiable(_all);

  /// The active profile's readings, newest first.
  List<Reading> get items => forProfile(_profiles.activeId);

  List<Reading> forProfile(String profileId) =>
      List.unmodifiable(_all.where((r) => r.profileId == profileId));

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
    _changed();
  }

  void removeForProfile(String profileId) {
    _all.removeWhere((r) => r.profileId == profileId);
    _changed();
  }

  /// Replaces the whole history, e.g. when restoring a backup.
  void replaceAll(List<Reading> readings) {
    _all
      ..clear()
      ..addAll(readings);
    _sortNewestFirst();
    _activeId = _profiles.activeId;
    _changed();
  }

  void toggleFlag(String id) =>
      _update(id, (r) => r.copyWith(flagged: !r.flagged));

  void setNote(String id, String note) =>
      _update(id, (r) => r.copyWith(note: note));

  void _update(String id, Reading Function(Reading) change) {
    final i = _all.indexWhere((r) => r.id == id);
    if (i < 0) return;
    _all[i] = change(_all[i]);
    _changed();
  }

  void _sortNewestFirst() => _all.sort((a, b) => b.time.compareTo(a.time));

  void _changed() {
    notifyListeners();
    final json = jsonEncode([for (final r in _all) r.toJson()]);
    // Chained so writes never overlap; temp file + rename so a crash
    // mid-write can't leave a half-written history behind.
    _pendingSave = _pendingSave.then((_) async {
      try {
        final tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(_file.path);
      } on FileSystemException catch (e) {
        debugPrint('Saving readings failed: $e');
      }
    });
  }

  /// Completes when every change so far is on disk.
  @visibleForTesting
  Future<void> flush() => _pendingSave;

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
