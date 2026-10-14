import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/reading.dart';
import 'protocol.dart';

enum LinkStatus {
  /// Not linked and not trying (never paired, user disconnected, or gave up).
  disconnected,

  /// Looking for the device by scanning.
  searching,

  /// Opening the link to a known device.
  connecting,

  connected,

  /// The link dropped and the app is retrying on its own.
  reconnecting,
}

/// Why the link isn't up. Picks the wording and the action the UI offers.
enum LinkIssue { bluetoothOff, noPermission, notFound, lost, failed }

enum StatusTone { ok, busy, idle, problem }

/// What tapping the status action does.
enum StatusAction {
  none,
  connect,
  retry,
  enableBluetooth,
  openSettings,
  cancel
}

/// One description of the link, shared by every screen that shows it.
@immutable
class DeviceStatusInfo {
  const DeviceStatusInfo(this.tone, this.title,
      {this.detail, this.action = StatusAction.none});

  final StatusTone tone;
  final String title;
  final String? detail;
  final StatusAction action;

  String? get actionLabel => switch (action) {
        StatusAction.none => null,
        StatusAction.connect => 'Connect',
        StatusAction.retry => 'Retry',
        StatusAction.enableBluetooth => 'Turn on',
        StatusAction.openSettings => 'Settings',
        StatusAction.cancel => 'Cancel',
      };
}

/// Device state built from protocol lines. A transport (mock or BLE) only has
/// to implement connect/disconnect/sendLine and feed every received line into
/// [handleLine].
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
  String? _linkError;
  LinkIssue? _issue;
  int _attempt = 0;
  bool _interrupted = false;
  String? _firmware;
  bool _updating = false;
  final _results = StreamController<Reading>.broadcast();
  final _ota = StreamController<OtaEvent>.broadcast();

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

  /// Why the last connect attempt failed or the link dropped; cleared on the
  /// next link change.
  String? get linkError => _linkError;

  /// Category of [linkError], for picking an action.
  LinkIssue? get linkIssue => _issue;

  /// Retry count while [LinkStatus.reconnecting].
  int get reconnectAttempt => _attempt;

  /// True when the link dropped in the middle of a cycle. The device still
  /// deflates on its own, but that cycle's result is lost. Cleared when the
  /// next cycle starts or with [clearInterrupted].
  bool get interruptedCycle => _interrupted;

  /// Firmware versions from the device's VER line, e.g. "b1 1.2 / b5 0.4".
  /// Kept after a disconnect so it still describes the last device used.
  String? get firmware => _firmware;

  /// Every completed measurement.
  Stream<Reading> get results => _results.stream;

  /// Device replies during a firmware update, for FirmwareUpdater.
  Stream<OtaEvent> get otaEvents => _ota.stream;

  /// True while a firmware update is being sent; measuring is blocked.
  bool get isUpdatingFirmware => _updating;

  /// Set by FirmwareUpdater around an update.
  void setFirmwareUpdating(bool value) {
    if (_updating == value) return;
    _updating = value;
    notifyListeners();
  }

  /// Longest line (with its newline) that fits in one write to the device.
  /// The BLE transport knows the negotiated MTU; this is a safe default.
  int get maxLineLength => 180;

  bool get isConnected => _link == LinkStatus.connected;

  /// Searching, connecting or reconnecting.
  bool get isLinking => switch (_link) {
        LinkStatus.searching ||
        LinkStatus.connecting ||
        LinkStatus.reconnecting =>
          true,
        _ => false,
      };

  bool get isBusy => switch (_phase) {
        MeasurePhase.inflating ||
        MeasurePhase.holding ||
        MeasurePhase.measuring ||
        MeasurePhase.deflating =>
          true,
        _ => false,
      };

  DeviceStatusInfo get status {
    final name = _name ?? 'OMHS';
    return switch (_link) {
      LinkStatus.connected =>
        DeviceStatusInfo(StatusTone.ok, '$name · Connected'),
      LinkStatus.searching => const DeviceStatusInfo(
          StatusTone.busy, 'Looking for your device…',
          detail: 'Make sure it is switched on and within a few metres.',
          action: StatusAction.cancel),
      LinkStatus.connecting => const DeviceStatusInfo(
          StatusTone.busy, 'Connecting…',
          action: StatusAction.cancel),
      LinkStatus.reconnecting => _issue == LinkIssue.bluetoothOff
          ? const DeviceStatusInfo(StatusTone.problem, 'Bluetooth is off',
              detail: 'The app reconnects when Bluetooth is back on.',
              action: StatusAction.enableBluetooth)
          : DeviceStatusInfo(
              StatusTone.busy,
              _attempt > 1
                  ? 'Reconnecting… (attempt $_attempt)'
                  : 'Reconnecting…',
              detail: 'Connection to $name was lost. Keep the phone nearby.',
              action: StatusAction.cancel),
      LinkStatus.disconnected => switch (_issue) {
          null => const DeviceStatusInfo(
              StatusTone.idle, 'Device not connected',
              action: StatusAction.connect),
          LinkIssue.bluetoothOff => DeviceStatusInfo(
              StatusTone.problem, 'Bluetooth is off',
              detail: _linkError, action: StatusAction.enableBluetooth),
          LinkIssue.noPermission => DeviceStatusInfo(
              StatusTone.problem, 'Bluetooth permission needed',
              detail: _linkError, action: StatusAction.openSettings),
          LinkIssue.notFound => DeviceStatusInfo(
              StatusTone.problem, 'Device not found',
              detail: _linkError, action: StatusAction.retry),
          LinkIssue.lost => DeviceStatusInfo(
              StatusTone.problem, 'Could not reconnect',
              detail: _linkError, action: StatusAction.retry),
          LinkIssue.failed => DeviceStatusInfo(
              StatusTone.problem, 'Could not connect',
              detail: _linkError, action: StatusAction.retry),
        },
    };
  }

  /// User-initiated connect. Remembers the device for [resume].
  Future<void> connect();

  /// User-initiated disconnect. Stops any automatic reconnecting.
  Future<void> disconnect();

  Future<void> sendLine(String line);

  /// Quietly reconnect to the remembered device, e.g. on app launch.
  /// Does nothing when no device is remembered.
  Future<void> resume() async {}

  /// Whether a device is remembered for [resume].
  bool get hasRememberedDevice => false;

  /// Disconnect and stop remembering the device.
  Future<void> forgetDevice() => disconnect();

  /// Ask the system to turn Bluetooth on (Android) or show settings (iOS).
  Future<void> enableBluetooth() async {}

  /// Open the app's page in system settings (for permissions).
  Future<void> openSystemSettings() async {}

  /// Run the action offered by [status].
  Future<void> runStatusAction() async {
    switch (status.action) {
      case StatusAction.connect || StatusAction.retry:
        await connect();
      case StatusAction.cancel:
        await disconnect();
      case StatusAction.enableBluetooth:
        await enableBluetooth();
      case StatusAction.openSettings:
        await openSystemSettings();
      case StatusAction.none:
        break;
    }
  }

  Future<void> start() async {
    if (_updating) return;
    await sendLine(cmdStart);
  }

  Future<void> stop() => sendLine(cmdStop);

  void clearInterrupted() {
    if (!_interrupted) return;
    _interrupted = false;
    notifyListeners();
  }

  /// [error] is the human-readable detail for [issue].
  @protected
  void setLink(LinkStatus status,
      {String? name, String? error, LinkIssue? issue, int attempt = 0}) {
    _link = status;
    _linkError = error;
    _issue = issue;
    _attempt = attempt;
    if (name != null) _name = name;
    if (status != LinkStatus.connected) {
      if (isBusy) _interrupted = true;
      _phase = MeasurePhase.idle;
      _pressure = 0;
      _ch1 = 0;
      _ch2 = 0;
      _progress = 0;
    }
    notifyListeners();
  }

  /// Ask for the phase and firmware version after (re)connecting, so the app
  /// doesn't show "Ready" while the cuff is still deflating. Firmware without
  /// CMD,STATUS ignores it.
  @protected
  Future<void> requestStatus() => sendLine(cmdStatus);

  @protected
  void handleLine(String line) {
    final event = parseLine(line);
    if (event == null) return;
    switch (event) {
      case OtaEvent():
        _ota.add(event);
        return;
      case PhaseEvent(:final phase):
        if (phase == MeasurePhase.inflating) {
          _peak = 0;
          _progress = 0;
          _error = null;
          _lastResult = null;
          _interrupted = false;
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
          firmware: _firmware,
        );
        _lastResult = r;
        _results.add(r);
      case VersionEvent(:final board1, :final board5):
        _firmware = formatFirmware(board1, board5);
      case ErrorEvent(:final message):
        _error = message.isEmpty ? 'Device error' : message;
        _phase = MeasurePhase.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _results.close();
    _ota.close();
    super.dispose();
  }
}

/// "b1 1.2 / b5 0.4"; either part may be missing.
String formatFirmware(String board1, String board5) => [
      if (board1.isNotEmpty) 'b1 $board1',
      if (board5.isNotEmpty) 'b5 $board5',
    ].join(' / ');

/// When to retry after the link drops: quickly at first, then backing off,
/// and giving up after [giveUpAfter] so a device that was switched off
/// doesn't keep the radio busy forever.
class ReconnectPolicy {
  const ReconnectPolicy({
    this.delays = const [1, 2, 4, 8, 15, 30],
    this.giveUpAfter = const Duration(minutes: 2),
  });

  /// Seconds to wait before each attempt; the last value repeats.
  final List<int> delays;
  final Duration giveUpAfter;

  /// Wait before attempt [attempt] (1-based).
  Duration delayBefore(int attempt) =>
      Duration(seconds: delays[(attempt - 1).clamp(0, delays.length - 1)]);

  bool shouldGiveUp(Duration elapsed) => elapsed >= giveUpAfter;

  /// Direct connects by ID are fast but fail if the device's address changed;
  /// every third attempt scans instead.
  bool scanOnAttempt(int attempt) => attempt % 3 == 0;
}
