import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/reading.dart';
import 'protocol.dart';

enum LinkStatus { disconnected, connecting, connected }

/// Device state built from protocol lines. A transport (mock now, BLE later)
/// only has to implement connect/disconnect/sendLine and feed every received
/// line into [handleLine].
abstract class DeviceService extends ChangeNotifier {
  LinkStatus _link = LinkStatus.disconnected;
  String? _name;
  MeasurePhase _phase = MeasurePhase.idle;
  double _pressure = 0;
  double _peak = 0;
  double _ch1 = 0;
  double _ch2 = 0;
  double _progress = 0;
  Reading? _lastResult;
  String? _error;
  final _results = StreamController<Reading>.broadcast();

  LinkStatus get link => _link;
  String? get deviceName => _name;
  MeasurePhase get phase => _phase;
  double get pressure => _pressure;
  double get peakPressure => _peak;
  double get ch1mA => _ch1;
  double get ch2mA => _ch2;
  double get progress => _progress;
  Reading? get lastResult => _lastResult;
  String? get error => _error;

  /// Every completed measurement.
  Stream<Reading> get results => _results.stream;

  bool get isConnected => _link == LinkStatus.connected;

  bool get isBusy => switch (_phase) {
        MeasurePhase.inflating ||
        MeasurePhase.holding ||
        MeasurePhase.measuring ||
        MeasurePhase.deflating =>
          true,
        _ => false,
      };

  Future<void> connect();
  Future<void> disconnect();
  Future<void> sendLine(String line);

  Future<void> start() => sendLine(cmdStart);
  Future<void> stop() => sendLine(cmdStop);

  @protected
  void setLink(LinkStatus status, {String? name}) {
    _link = status;
    if (name != null) _name = name;
    if (status == LinkStatus.disconnected) {
      _phase = MeasurePhase.idle;
      _pressure = 0;
      _ch1 = 0;
      _ch2 = 0;
      _progress = 0;
    }
    notifyListeners();
  }

  @protected
  void handleLine(String line) {
    final event = parseLine(line);
    if (event == null) return;
    switch (event) {
      case PhaseEvent(:final phase):
        if (phase == MeasurePhase.inflating) {
          _peak = 0;
          _progress = 0;
          _error = null;
          _lastResult = null;
        }
        _phase = phase;
      case PressureEvent(:final mmHg):
        _pressure = mmHg;
        if (mmHg > _peak) _peak = mmHg;
      case CurrentEvent(:final ch1, :final ch2):
        _ch1 = ch1;
        _ch2 = ch2;
      case ProgressEvent(:final value):
        _progress = value.clamp(0.0, 1.0).toDouble();
      case ResultEvent(:final mgdl, :final quality):
        final now = DateTime.now();
        final r = Reading(
          id: now.microsecondsSinceEpoch.toString(),
          time: now,
          totalChol: mgdl,
          quality: quality.clamp(0.0, 1.0).toDouble(),
          ch1mA: _ch1,
          ch2mA: _ch2,
          peakPressure: _peak,
        );
        _lastResult = r;
        _results.add(r);
      case ErrorEvent(:final message):
        _error = message.isEmpty ? 'Device error' : message;
        _phase = MeasurePhase.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _results.close();
    super.dispose();
  }
}
