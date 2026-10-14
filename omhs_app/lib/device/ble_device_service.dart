import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'device_service.dart';

/// Talks to Board 5 (ESP32-C3) over the Nordic UART Service. Board 5 forwards
/// the Teensy's UART lines unchanged, so received bytes are split on '\n' and
/// fed to [handleLine]; commands are written to RX with a trailing '\n'.
///
/// The last connected device is remembered. If the link drops, or the app
/// starts with a remembered device, it reconnects on its own following
/// [ReconnectPolicy], until the user taps Disconnect.
class BleDeviceService extends DeviceService with WidgetsBindingObserver {
  BleDeviceService(this._prefs,
      {ReconnectPolicy policy = const ReconnectPolicy()})
      : _policy = policy,
        _savedId = _prefs.getString(_kDeviceId) {
    WidgetsBinding.instance.addObserver(this);
  }

  // Nordic UART Service. Change here and in the ESP32 firmware together.
  static final nusService = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final nusRx =
      Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // app -> device
  static final nusTx =
      Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // device -> app

  /// Advertised name must contain this (matched as well as the service UUID,
  /// since the ESP32 may not fit the 128-bit UUID in its advertisement).
  static const nameKeyword = 'OMHS';

  /// flutter_blue_plus is free for personal, nonprofit and educational use;
  /// commercial use needs a paid license (see the package's LICENSE).
  static const _license = License.nonprofit;

  static const _kDeviceId = 'bleDeviceId';
  static const _scanTimeout = Duration(seconds: 10);
  static const _connectTimeout = Duration(seconds: 15);

  /// Connecting straight to a remembered ID fails fast when it's out of range.
  static const _directTimeout = Duration(seconds: 8);
  static const _maxPending = 1024;

  final SharedPreferences _prefs;
  final ReconnectPolicy _policy;
  String? _savedId;

  /// The user wants a link: set by connect/resume, cleared by disconnect.
  /// While set, a dropped link is retried.
  bool _wantLink = false;

  /// Bumped to cancel whatever connect attempt or retry loop is running.
  int _session = 0;
  bool _inBackground = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  String _pending = '';

  @override
  bool get hasRememberedDevice => _savedId != null;

  @override
  Future<void> connect() async {
    if (isConnected || isLinking) return;
    _wantLink = true;
    final session = ++_session;
    setLink(LinkStatus.connecting);
    _watchAdapter();
    final saved = _savedId;
    try {
      if (saved != null) {
        try {
          await _tryConnect(session, id: saved);
          return;
        } on _BleFailure catch (f) {
          // Out of range or address changed: fall back to a scan, unless
          // Bluetooth itself is the problem.
          if (f.issue != LinkIssue.notFound && f.issue != LinkIssue.failed) {
            rethrow;
          }
        }
      }
      await _tryConnect(session);
    } on _Cancelled {
      return;
    } on _BleFailure catch (f) {
      if (session != _session) return;
      // With Bluetooth off, stay wanting the link so turning it on connects.
      _wantLink = f.issue == LinkIssue.bluetoothOff;
      setLink(LinkStatus.disconnected, issue: f.issue, error: f.message);
    }
  }

  @override
  Future<void> resume() async {
    if (_savedId == null || isConnected || isLinking) return;
    _wantLink = true;
    unawaited(_reconnectLoop(fromLaunch: true));
    _watchAdapter();
  }

  @override
  Future<void> disconnect() async {
    _wantLink = false;
    _session++;
    // Set state first so an in-flight connect sees it was cancelled.
    setLink(LinkStatus.disconnected);
    await _teardown();
  }

  @override
  Future<void> forgetDevice() async {
    _savedId = null;
    await _prefs.remove(_kDeviceId);
    await disconnect();
  }

  @override
  Future<void> enableBluetooth() async {
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn(); // system prompt
      } catch (_) {}
    } else {
      await openSystemSettings(); // iOS has no API to turn Bluetooth on
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (Platform.isIOS) {
      await launchUrl(Uri.parse('app-settings:'));
    } else {
      // Android asks for the permission again on the next attempt.
      await connect();
    }
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

  /// One attempt: connect to [id] directly, or scan when it's null. Throws
  /// [_BleFailure] or [_Cancelled]; cleans up after itself either way.
  /// [attempt] > 0 means it's part of the retry loop, so the status keeps
  /// saying "Reconnecting".
  Future<void> _tryConnect(int session, {String? id, int attempt = 0}) async {
    void status(LinkStatus s) {
      if (session != _session) throw const _Cancelled();
      if (attempt > 0) {
        setLink(LinkStatus.reconnecting,
            issue: LinkIssue.lost, attempt: attempt);
      } else {
        setLink(s);
      }
    }

    try {
      await _ensureAdapterOn(prompt: attempt == 0);
      final BluetoothDevice device;
      if (id != null) {
        status(LinkStatus.connecting);
        device = BluetoothDevice.fromId(id);
        _device = device;
        await device.connect(license: _license, timeout: _directTimeout);
      } else {
        status(LinkStatus.searching);
        // While reconnecting, only take back the same device; another OMHS
        // nearby (e.g. in a clinic) must not be picked up silently.
        device = await _scan(onlyId: attempt > 0 ? _savedId : null);
        status(LinkStatus.connecting);
        _device = device;
        await device.connect(license: _license, timeout: _connectTimeout);
      }
      if (session != _session) throw const _Cancelled();
      await _open(device, session);
    } catch (e) {
      await _teardown();
      if (e is _Cancelled || session != _session) throw const _Cancelled();
      debugPrint('BLE connect failed: $e');
      throw _classify(e);
    }
  }

  /// Finds the UART service and goes live.
  Future<void> _open(BluetoothDevice device, int session) async {
    final services = await device.discoverServices();
    final nus = services.where((s) => s.uuid == nusService).firstOrNull;
    final tx = nus?.characteristics.where((c) => c.uuid == nusTx).firstOrNull;
    final rx = nus?.characteristics.where((c) => c.uuid == nusRx).firstOrNull;
    if (tx == null || rx == null) {
      throw const _BleFailure(LinkIssue.failed,
          'Device has no UART service. Check Board 5 firmware.');
    }
    _rx = rx;
    _pending = '';
    _notifySub = tx.onValueReceived.listen(_onData);
    device.cancelWhenDisconnected(_notifySub!);
    await tx.setNotifyValue(true);

    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) _onLinkLost(session);
    });
    if (session != _session) throw const _Cancelled();

    final id = device.remoteId.str;
    if (_savedId != id) {
      _savedId = id;
      await _prefs.setString(_kDeviceId, id);
    }
    final name =
        device.platformName.isNotEmpty ? device.platformName : device.advName;
    setLink(LinkStatus.connected, name: name.isEmpty ? 'OMHS' : name);
    await requestStatus();
  }

  /// Retries until connected, cancelled, or [ReconnectPolicy.giveUpAfter].
  /// [fromLaunch] reconnects to the remembered device at app start, which
  /// reads as "Connecting" rather than "Reconnecting" and starts at once.
  Future<void> _reconnectLoop({bool fromLaunch = false}) async {
    final session = ++_session;
    final started = DateTime.now();
    for (var attempt = 1;; attempt++) {
      if (fromLaunch && attempt == 1) {
        setLink(LinkStatus.connecting);
      } else {
        setLink(LinkStatus.reconnecting,
            issue: LinkIssue.lost, attempt: attempt);
        // Paused in the background; restarted by didChangeAppLifecycleState.
        if (_inBackground) return;
        await Future<void>.delayed(_policy.delayBefore(attempt));
      }
      if (session != _session) return;

      final id = _savedId;
      try {
        await _tryConnect(
          session,
          id: id == null || _policy.scanOnAttempt(attempt) ? null : id,
          attempt: fromLaunch && attempt == 1 ? 0 : attempt,
        );
        return;
      } on _Cancelled {
        return;
      } on _BleFailure catch (f) {
        if (session != _session) return;
        switch (f.issue) {
          case LinkIssue.bluetoothOff:
            // _watchAdapter restarts the loop when it's turned back on.
            setLink(LinkStatus.reconnecting, issue: LinkIssue.bluetoothOff);
            return;
          case LinkIssue.noPermission:
            _wantLink = false;
            setLink(LinkStatus.disconnected, issue: f.issue, error: f.message);
            return;
          default:
            break;
        }
      }
      if (_policy.shouldGiveUp(DateTime.now().difference(started))) {
        // _wantLink stays set, so coming back to the app tries again.
        setLink(LinkStatus.disconnected,
            issue: LinkIssue.lost,
            error: 'Could not reach the device. Is it switched on and nearby?');
        return;
      }
    }
  }

  /// Follows Bluetooth being switched off and on. Started on the first
  /// connect, not at launch, so iOS doesn't ask for Bluetooth permission
  /// before the user has chosen to connect.
  void _watchAdapter() {
    _adapterSub ??= FlutterBluePlus.adapterState.listen((s) {
      if (s == BluetoothAdapterState.off && (isConnected || isLinking)) {
        _session++;
        _teardown();
        if (_wantLink) {
          setLink(LinkStatus.reconnecting, issue: LinkIssue.bluetoothOff);
        } else {
          setLink(LinkStatus.disconnected,
              issue: LinkIssue.bluetoothOff,
              error: 'Turn on Bluetooth and try again.');
        }
      } else if (s == BluetoothAdapterState.on && _waitingForAdapter) {
        _reconnectLoop();
      }
    });
  }

  bool get _waitingForAdapter =>
      _wantLink &&
      linkIssue == LinkIssue.bluetoothOff &&
      (link == LinkStatus.reconnecting || link == LinkStatus.disconnected);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _inBackground = true;
        // Stop retrying while nobody is looking; an open link is kept.
        if (link == LinkStatus.reconnecting) _session++;
      case AppLifecycleState.resumed:
        final wasAway = _inBackground;
        _inBackground = false;
        final idle = link == LinkStatus.disconnected ||
            (link == LinkStatus.reconnecting &&
                linkIssue != LinkIssue.bluetoothOff);
        if (wasAway && _wantLink && idle) _reconnectLoop();
      default:
        break;
    }
  }

  Future<void> _ensureAdapterOn({required bool prompt}) async {
    if (!await FlutterBluePlus.isSupported) {
      throw const _BleFailure(
          LinkIssue.failed, 'This phone does not support Bluetooth LE.');
    }
    var state = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown);
    if (state != BluetoothAdapterState.on && prompt && Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn(); // system prompt
        state = BluetoothAdapterState.on;
      } catch (_) {}
    }
    if (state == BluetoothAdapterState.unauthorized) {
      throw const _BleFailure(LinkIssue.noPermission,
          'Allow Bluetooth for OMHS in system settings.');
    }
    if (state != BluetoothAdapterState.on) {
      throw const _BleFailure(
          LinkIssue.bluetoothOff, 'Turn on Bluetooth and try again.');
    }
  }

  /// First OMHS device seen, or only the one with [onlyId] when given.
  Future<BluetoothDevice> _scan({String? onlyId}) async {
    bool match(ScanResult r) =>
        onlyId == null ? _isOmhs(r) : r.device.remoteId.str == onlyId;
    // Subscribe before starting so the first result can't be missed.
    final found = FlutterBluePlus.onScanResults
        .expand((results) => results)
        .where(match)
        .map((result) => result.device)
        .first
        .timeout(_scanTimeout);
    try {
      // Unfiltered scan, matched here: Android rejects withKeywords combined
      // with withServices, and we want either one to match.
      await FlutterBluePlus.startScan(timeout: _scanTimeout);
      return await found;
    } on TimeoutException {
      throw const _BleFailure(LinkIssue.notFound,
          'Make sure the device is switched on and within a few metres.');
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

  void _onLinkLost(int session) {
    if (session != _session) return; // we asked for it, or already handled
    _teardown();
    if (_wantLink) {
      _reconnectLoop();
    } else {
      setLink(LinkStatus.disconnected,
          issue: LinkIssue.lost, error: 'Connection to device lost');
    }
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

  static _BleFailure _classify(Object e) => switch (e) {
        _BleFailure() => e,
        FlutterBluePlusException(:final description) => _BleFailure(
            // Android reports a missing permission as an exception.
            (description ?? '').toLowerCase().contains('permission')
                ? LinkIssue.noPermission
                : LinkIssue.failed,
            'Bluetooth error: ${description ?? 'unknown'}'),
        TimeoutException() =>
          const _BleFailure(LinkIssue.notFound, 'Device did not respond.'),
        _ =>
          const _BleFailure(LinkIssue.failed, 'Could not connect to device.'),
      };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session++;
    _adapterSub?.cancel();
    _teardown();
    super.dispose();
  }
}

class _BleFailure implements Exception {
  const _BleFailure(this.issue, this.message);
  final LinkIssue issue;
  final String message;
}

/// The attempt was superseded by disconnect, a newer attempt, or the app
/// going to the background.
class _Cancelled implements Exception {
  const _Cancelled();
}
