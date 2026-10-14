import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'device_service.dart';
import 'firmware_update.dart';
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

  /// Simulated firmware versions reported by CMD,STATUS; a firmware update
  /// bumps the minor number.
  int _b1 = 1, _b5 = 1;
  String get firmwareLine => 'VER,0.$_b1-sim,0.$_b5-sim';

  // Firmware update being received.
  String? _otaTarget;
  int _otaSize = 0;
  int _otaCrc = 0;
  final _otaBytes = BytesBuilder(copy: false);
  static const _otaDelay = Duration(milliseconds: 1);

  @override
  Future<void> connect() async {
    if (link != LinkStatus.disconnected) return;
    setLink(LinkStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (link != LinkStatus.connecting) return; // cancelled meanwhile
    setLink(LinkStatus.connected, name: name);
    await requestStatus();
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    setLink(LinkStatus.disconnected);
  }

  /// Drops the link as if the device went out of range, then comes back
  /// after [after], like the BLE service's automatic reconnect.
  Future<void> simulateDrop(
      {Duration after = const Duration(seconds: 3)}) async {
    if (!isConnected) return;
    _timer?.cancel();
    setLink(LinkStatus.reconnecting, issue: LinkIssue.lost, attempt: 1);
    await Future<void>.delayed(after);
    if (link != LinkStatus.reconnecting) return; // cancelled meanwhile
    setLink(LinkStatus.connected, name: name);
    await requestStatus();
  }

  @override
  Future<void> sendLine(String line) async {
    if (!isConnected) return;
    if (line == cmdStart) _runCycle();
    if (line == cmdStop) _abort();
    if (line == cmdStatus) {
      handleLine(firmwareLine);
      handleLine(isBusy ? 'STATE,DEFLATE' : 'STATE,IDLE');
    }
    if (line.startsWith('OTA,')) _receiveOta(line.split(','));
  }

  void _receiveOta(List<String> p) {
    void reply(String line) => Timer(_otaDelay, () {
          if (isConnected) handleLine(line);
        });
    switch (p[1]) {
      case 'BEGIN':
        _otaTarget = p[2];
        _otaSize = int.parse(p[3]);
        _otaCrc = int.parse(p[4], radix: 16);
        _otaBytes.clear();
        reply('OTA,READY,512');
      case 'DATA' when _otaTarget != null:
        // Out of order: ask for the right offset again.
        if (int.parse(p[2]) == _otaBytes.length) {
          _otaBytes.add(base64Decode(p[3]));
        }
        reply('OTA,ACK,${_otaBytes.length}');
      case 'END' when _otaTarget != null:
        final target = _otaTarget;
        final image = _otaBytes.takeBytes();
        _otaTarget = null;
        if (image.length != _otaSize || crc32(image) != _otaCrc) {
          reply('OTA,FAIL,checksum mismatch');
          return;
        }
        reply('OTA,OK');
        if (target == 'B5') {
          _b5++;
          // The BLE board restarts, so the link drops and comes back.
          Timer(const Duration(milliseconds: 200), simulateDrop);
        } else {
          _b1++;
        }
      case 'ABORT':
        _otaTarget = null;
        _otaBytes.clear();
      default:
        reply('OTA,FAIL,no update in progress');
    }
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
