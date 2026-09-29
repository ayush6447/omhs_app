import 'dart:async';

import 'package:flutter/foundation.dart';

import '../device/device_service.dart';
import 'reading.dart';

/// Measurement history. In-memory for now; swap in sqflite/Hive later.
class ReadingsStore extends ChangeNotifier {
  ReadingsStore(DeviceService device, {bool seedDemoData = false}) {
    _sub = device.results.listen(add);
    if (seedDemoData) _items.addAll(_demoReadings());
  }

  late final StreamSubscription<Reading> _sub;
  final List<Reading> _items = [];

  /// Newest first.
  List<Reading> get items => List.unmodifiable(_items);

  Reading? get latest => _items.isEmpty ? null : _items.first;

  Reading? byId(String id) {
    for (final r in _items) {
      if (r.id == id) return r;
    }
    return null;
  }

  int countSince(DateTime since) =>
      _items.where((r) => r.time.isAfter(since)).length;

  void add(Reading r) {
    _items.insert(0, r);
    notifyListeners();
  }

  void toggleFlag(String id) => _update(id, (r) => r.copyWith(flagged: !r.flagged));

  void setNote(String id, String note) => _update(id, (r) => r.copyWith(note: note));

  void _update(String id, Reading Function(Reading) change) {
    final i = _items.indexWhere((r) => r.id == id);
    if (i < 0) return;
    _items[i] = change(_items[i]);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  static List<Reading> _demoReadings() {
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
      );
    });
  }
}
