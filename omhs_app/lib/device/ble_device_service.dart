import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_service.dart';

/// Talks to Board 5 (ESP32-C3) over the Nordic UART Service. Board 5 forwards
/// the Teensy's UART lines unchanged, so received bytes are split on '\n' and
/// fed to [handleLine]; commands are written to RX with a trailing '\n'.
class BleDeviceService extends DeviceService {
  // Nordic UART Service. Change here and in the ESP32 firmware together.
  static final nusService = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final nusRx = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // app -> device
  static final nusTx = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // device -> app

  /// Advertised name must contain this (matched as well as the service UUID,
  /// since the ESP32 may not fit the 128-bit UUID in its advertisement).
  static const nameKeyword = 'OMHS';

  /// flutter_blue_plus is free for personal, nonprofit and educational use;
  /// commercial use needs a paid license (see the package's LICENSE).
  static const _license = License.nonprofit;

  static const _scanTimeout = Duration(seconds: 10);
  static const _connectTimeout = Duration(seconds: 15);
  static const _maxPending = 1024;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  String _pending = '';

  @override
  Future<void> connect() async {
    if (link != LinkStatus.disconnected) return;
    setLink(LinkStatus.connecting);
    try {
      await _ensureAdapterOn();
      final device = await _scan();
      if (link != LinkStatus.connecting) return; // cancelled meanwhile
      _device = device;
      await device.connect(license: _license, timeout: _connectTimeout);
      if (link != LinkStatus.connecting) return await _teardown();

      final services = await device.discoverServices();
      final nus = services.where((s) => s.uuid == nusService).firstOrNull;
      final tx = nus?.characteristics.where((c) => c.uuid == nusTx).firstOrNull;
      final rx = nus?.characteristics.where((c) => c.uuid == nusRx).firstOrNull;
      if (tx == null || rx == null) {
        throw const _BleFailure('Device has no UART service. Check Board 5 firmware.');
      }
      _rx = rx;
      _pending = '';
      _notifySub = tx.onValueReceived.listen(_onData);
      device.cancelWhenDisconnected(_notifySub!);
      await tx.setNotifyValue(true);

      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _onLinkLost();
      });
      if (link != LinkStatus.connecting) return await _teardown();

      final name =
          device.platformName.isNotEmpty ? device.platformName : device.advName;
      setLink(LinkStatus.connected, name: name.isEmpty ? 'OMHS' : name);
    } catch (e) {
      debugPrint('BLE connect failed: $e');
      await _teardown();
      if (link == LinkStatus.connecting) {
        setLink(LinkStatus.disconnected, error: _describe(e));
      }
    }
  }

  @override
  Future<void> disconnect() async {
    // Set state first so an in-flight connect() sees it was cancelled.
    setLink(LinkStatus.disconnected);
    await _teardown();
  }

  @override
  Future<void> sendLine(String line) async {
    final rx = _rx;
    if (!isConnected || rx == null) return;
    try {
      await rx.write(
        utf8.encode('$line\n'),
        withoutResponse: rx.properties.writeWithoutResponse,
      );
    } catch (e) {
      debugPrint('BLE write failed: $e');
      setLink(link, error: 'Could not send command to device');
    }
  }

  Future<void> _ensureAdapterOn() async {
    if (!await FlutterBluePlus.isSupported) {
      throw const _BleFailure('This phone does not support Bluetooth LE.');
    }
    var state = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown);
    if (state != BluetoothAdapterState.on && Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn(); // system prompt
        state = BluetoothAdapterState.on;
      } catch (_) {}
    }
    if (state == BluetoothAdapterState.unauthorized) {
      throw const _BleFailure('Bluetooth permission denied. Allow it in system settings.');
    }
    if (state != BluetoothAdapterState.on) {
      throw const _BleFailure('Turn on Bluetooth and try again.');
    }
  }

  Future<BluetoothDevice> _scan() async {
    // Subscribe before starting so the first result can't be missed.
    final found = FlutterBluePlus.onScanResults
        .expand((results) => results)
        .where(_isOmhs)
        .map((result) => result.device)
        .first
        .timeout(_scanTimeout);
    try {
      // Unfiltered scan, matched here: Android rejects withKeywords combined
      // with withServices, and we want either one to match.
      await FlutterBluePlus.startScan(timeout: _scanTimeout);
      return await found;
    } on TimeoutException {
      throw const _BleFailure('No OMHS device found. Is it powered on and nearby?');
    } catch (_) {
      found.ignore(); // scan never started; don't leak its timeout
      rethrow;
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  static bool _isOmhs(ScanResult result) {
    final ad = result.advertisementData;
    return ad.serviceUuids.contains(nusService) ||
        ad.advName.contains(nameKeyword) ||
        result.device.platformName.contains(nameKeyword);
  }

  void _onData(List<int> bytes) {
    _pending += utf8.decode(bytes, allowMalformed: true);
    final lines = _pending.split('\n');
    _pending = lines.removeLast();
    if (_pending.length > _maxPending) _pending = ''; // no newline ever came
    for (final line in lines) {
      handleLine(line);
    }
  }

  void _onLinkLost() {
    if (link == LinkStatus.disconnected) return; // we asked for it
    _teardown();
    setLink(LinkStatus.disconnected, error: 'Connection to device lost');
  }

  Future<void> _teardown() async {
    final device = _device;
    _device = null;
    _rx = null;
    await _connSub?.cancel();
    _connSub = null;
    await _notifySub?.cancel();
    _notifySub = null;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    try {
      await device?.disconnect();
    } catch (_) {}
  }

  String _describe(Object e) => switch (e) {
        _BleFailure(:final message) => message,
        FlutterBluePlusException(:final description) =>
          'Bluetooth error: ${description ?? 'unknown'}',
        TimeoutException() => 'Device did not respond. Try again.',
        _ => 'Could not connect to device',
      };

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}

class _BleFailure implements Exception {
  const _BleFailure(this.message);
  final String message;
}
