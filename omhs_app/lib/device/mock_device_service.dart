import 'dart:async';
import 'dart:math';

import 'device_service.dart';
import 'protocol.dart';

/// Simulates the Teensy by emitting the same protocol lines it will print.
/// Lets the UI be built and tested before Board 5's BLE firmware exists.
class MockDeviceService extends DeviceService {
  MockDeviceService({this.name = 'OMHS-v2 (demo)'});

  final String name;
  final _rng = Random();
  Timer? _timer;

  // Cycle timing in 100 ms ticks.
  static const _tick = Duration(milliseconds: 100);
  static const _inflateEnd = 40; // 4 s
  static const _holdEnd = 60; // 2 s
  static const _measureEnd = 110; // 5 s
  static const _deflateEnd = 130; // 2 s
  static const _target = 180.0; // mmHg

  @override
  Future<void> connect() async {
    if (link != LinkStatus.disconnected) return;
    setLink(LinkStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (link != LinkStatus.connecting) return; // cancelled meanwhile
    setLink(LinkStatus.connected, name: name);
    handleLine('STATE,IDLE');
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    setLink(LinkStatus.disconnected);
  }

  @override
  Future<void> sendLine(String line) async {
    if (!isConnected) return;
    if (line == cmdStart) _runCycle();
    if (line == cmdStop) _abort();
  }

  double _jitter(double amp) => (_rng.nextDouble() * 2 - 1) * amp;
  String _f(double v) => v.toStringAsFixed(1);

  void _runCycle() {
    if (isBusy) return;
    _timer?.cancel();
    var t = 0;
    handleLine('STATE,INFLATE');
    _timer = Timer.periodic(_tick, (timer) {
      t++;
      handleLine('PROG,${(t / _deflateEnd).toStringAsFixed(3)}');

      if (t <= _inflateEnd) {
        handleLine('P,${_f(_target * t / _inflateEnd)}');
      } else if (t <= _holdEnd) {
        if (t == _inflateEnd + 1) handleLine('STATE,HOLD');
        handleLine('P,${_f(_target + _jitter(2))}');
      } else if (t <= _measureEnd) {
        if (t == _holdEnd + 1) handleLine('STATE,MEASURE');
        handleLine('P,${_f(_target + _jitter(2))}');
        handleLine('I,${_f(50 + _jitter(0.4))},${_f(49.6 + _jitter(0.4))}');
      } else if (t <= _deflateEnd) {
        if (t == _measureEnd + 1) {
          handleLine('I,0.0,0.0');
          handleLine('STATE,DEFLATE');
        }
        final left = (_deflateEnd - t) / (_deflateEnd - _measureEnd);
        handleLine('P,${_f(_target * left)}');
      } else {
        timer.cancel();
        final chol = 165 + _rng.nextDouble() * 70;
        final quality = 0.78 + _rng.nextDouble() * 0.2;
        handleLine('RESULT,${_f(chol)},${quality.toStringAsFixed(2)}');
        handleLine('STATE,DONE');
      }
    });
  }

  void _abort() {
    if (!isBusy) return;
    _timer?.cancel();
    handleLine('I,0.0,0.0');
    handleLine('STATE,DEFLATE');
    var p = pressure;
    _timer = Timer.periodic(_tick, (timer) {
      p *= 0.7;
      if (p < 2) {
        timer.cancel();
        handleLine('P,0.0');
        handleLine('PROG,0');
        handleLine('STATE,IDLE');
      } else {
        handleLine('P,${_f(p)}');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
