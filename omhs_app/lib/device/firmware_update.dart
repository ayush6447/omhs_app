import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/checksum.dart';
import 'device_service.dart';
import 'protocol.dart';

export '../data/checksum.dart' show crc32;

/// Which board an image is for.
enum FirmwareTarget {
  /// The Teensy: cuff and optics. Board 5 passes the image on to it.
  board1('B1', 'Board 1 · Teensy'),

  /// The ESP32-C3 BLE bridge. It restarts after the update, so the link
  /// drops and the app reconnects on its own.
  board5('B5', 'Board 5 · BLE');

  const FirmwareTarget(this.code, this.label);

  /// Name used in OTA,BEGIN.
  final String code;
  final String label;
}

enum UpdateStage { idle, starting, sending, verifying, done, failed }

/// Sends a firmware image over the line protocol (draft, see protocol.dart):
///
/// ```text
///   app OTA,BEGIN,<B1|B5>,<size>,<crc32>   device OTA,READY[,<max chunk>]
///   app OTA,DATA,<offset>,<base64>         device OTA,ACK,<next offset>
///   ... until every byte is acknowledged
///   app OTA,END                            device OTA,OK | OTA,FAIL,<msg>
/// ```
///
/// One chunk is in flight at a time and the ACK says where to continue, so
/// the device can ask for a chunk again. The firmware must check size and
/// CRC before switching to the new image, so an interrupted update leaves
/// the old firmware running.
class FirmwareUpdater extends ChangeNotifier {
  FirmwareUpdater(
    this._device, {
    this.readyTimeout = const Duration(seconds: 30),
    this.ackTimeout = const Duration(seconds: 5),
    this.verifyTimeout = const Duration(seconds: 60),
  });

  static const maxImageBytes = 4 * 1024 * 1024;

  /// Resends of one chunk before giving up.
  static const _maxRetries = 3;

  final DeviceService _device;

  /// Erasing flash before READY can take a while.
  final Duration readyTimeout;
  final Duration ackTimeout;
  final Duration verifyTimeout;

  UpdateStage _stage = UpdateStage.idle;
  FirmwareTarget? _target;
  int _sent = 0;
  int _total = 0;
  String? _error;

  final _inbox = <OtaEvent>[];
  Completer<void>? _wake;
  _Stop? _stop;
  StreamSubscription<OtaEvent>? _sub;
  Timer? _statusTimer;
  bool _disposed = false;

  UpdateStage get stage => _stage;
  FirmwareTarget? get target => _target;

  /// Bytes the device has acknowledged.
  int get sent => _sent;
  int get total => _total;
  double get progress => _total == 0 ? 0 : _sent / _total;
  String? get error => _error;

  bool get isRunning => switch (_stage) {
        UpdateStage.starting ||
        UpdateStage.sending ||
        UpdateStage.verifying =>
          true,
        _ => false,
      };

  /// Why [image] can't be sent to [target], or null when it can.
  static String? check(FirmwareTarget target, Uint8List image) {
    if (image.isEmpty) return 'The file is empty.';
    if (image.length > maxImageBytes) {
      return 'The file is too big to be a firmware image.';
    }
    // ESP32 app images start with the magic byte 0xE9.
    if (target == FirmwareTarget.board5 && image.first != 0xE9) {
      return 'This is not an ESP32 firmware image. Choose the .bin file '
          'built for Board 5.';
    }
    return null;
  }

  /// Sends [image] to [target]. Completes when the update is done or has
  /// failed; see [stage] and [error].
  Future<void> run(FirmwareTarget target, Uint8List image) async {
    if (isRunning) return;
    _target = target;
    _sent = 0;
    _total = image.length;
    final problem = check(target, image) ??
        (!_device.isConnected
            ? 'Connect the device first.'
            : _device.isBusy
                ? 'Wait for the measurement to finish.'
                : null);
    if (problem != null) {
      _finish(UpdateStage.failed, problem);
      return;
    }

    _inbox.clear();
    _stop = null;
    _error = null;
    _stage = UpdateStage.starting;
    _statusTimer?.cancel();
    _sub = _device.otaEvents.listen(_onEvent);
    _device.addListener(_watchLink);
    _device.setFirmwareUpdating(true);
    _notify();

    try {
      final crc = crc32(image).toRadixString(16).padLeft(8, '0');
      await _device.sendLine('OTA,BEGIN,${target.code},${image.length},$crc');
      final int? deviceMax;
      switch (await _reply(readyTimeout)) {
        case OtaReadyEvent(:final maxChunk):
          deviceMax = maxChunk;
        case OtaFailEvent(:final message):
          throw _Stop(_deviceSaid(message));
        default:
          throw const _Stop('The device did not start the update. Its '
              'firmware may not support updates over Bluetooth yet.');
      }
      final chunk = _chunkSize(deviceMax);

      _stage = UpdateStage.sending;
      _notify();
      var offset = 0;
      var retries = 0;
      while (offset < image.length) {
        final end = min(offset + chunk, image.length);
        await _device.sendLine(
            'OTA,DATA,$offset,${base64Encode(image.sublist(offset, end))}');
        final ack = await _reply(ackTimeout);
        switch (ack) {
          case OtaAckEvent(:final nextOffset) when nextOffset > offset:
            if (nextOffset > image.length) {
              throw const _Stop('The device reported a wrong position.',
                  abort: true);
            }
            offset = nextOffset;
            retries = 0;
            _sent = offset;
            _notify();
          case OtaFailEvent(:final message):
            throw _Stop(_deviceSaid(message));
          case OtaAckEvent(:final nextOffset):
            // Asked for an earlier chunk again.
            if (++retries > _maxRetries) {
              throw const _Stop('The device kept rejecting the data.',
                  abort: true);
            }
            offset = nextOffset;
          default:
            // No answer: send the same chunk again.
            if (++retries > _maxRetries) {
              throw const _Stop('The device stopped responding.',
                  abort: true);
            }
        }
      }

      _stage = UpdateStage.verifying;
      _notify();
      await _device.sendLine('OTA,END');
      switch (await _reply(verifyTimeout)) {
        case OtaOkEvent():
          _finish(UpdateStage.done, null);
          // Board 5 restarts and the reconnect asks for VER on its own;
          // after a Teensy restart the link stays up, so ask again.
          if (target == FirmwareTarget.board1) {
            _statusTimer = Timer(const Duration(seconds: 6), () {
              if (_device.isConnected) _device.sendLine(cmdStatus);
            });
          }
        case OtaFailEvent(:final message):
          throw _Stop(_deviceSaid(message));
        default:
          throw const _Stop('The device did not confirm the update.');
      }
    } on _Stop catch (s) {
      if (s.abort && _device.isConnected) await _device.sendLine('OTA,ABORT');
      _finish(UpdateStage.failed, s.message);
    }
  }

  /// Stops the update; the device keeps its current firmware.
  void cancel() => _halt(const _Stop(
      'Update cancelled. The device keeps its current firmware.',
      abort: true));

  void _onEvent(OtaEvent e) {
    _inbox.add(e);
    _signal();
  }

  void _watchLink() {
    if (isRunning && !_device.isConnected) {
      _halt(const _Stop('Connection lost during the update. The device '
          'keeps its current firmware; try again when it reconnects.'));
    }
  }

  void _halt(_Stop reason) {
    if (!isRunning) return;
    _stop ??= reason;
    _signal();
  }

  void _signal() {
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Next device reply, or null after [timeout]. Throws when cancelled or
  /// the link dropped.
  Future<OtaEvent?> _reply(Duration timeout) async {
    if (_stop == null && _inbox.isEmpty) {
      final wake = _wake = Completer<void>();
      final timer = Timer(timeout, _signal);
      await wake.future;
      timer.cancel();
      _wake = null;
    }
    if (_stop != null) throw _stop!;
    return _inbox.isEmpty ? null : _inbox.removeAt(0);
  }

  /// Bytes per chunk so that `OTA,DATA,<offset>,<base64>\n` fits in one
  /// write, capped by what the device said it accepts.
  int _chunkSize(int? deviceMax) {
    final header = 'OTA,DATA,$_total,'.length + 1;
    var bytes = (_device.maxLineLength - header) ~/ 4 * 3;
    if (deviceMax != null) bytes = min(bytes, deviceMax);
    return max(bytes, 48);
  }

  static String _deviceSaid(String message) => message.isEmpty
      ? 'The device rejected the update.'
      : 'The device rejected the update: $message';

  void _finish(UpdateStage stage, String? error) {
    _stage = stage;
    _error = error;
    _sub?.cancel();
    _sub = null;
    _device.removeListener(_watchLink);
    _device.setFirmwareUpdating(false);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    _statusTimer?.cancel();
    _sub?.cancel();
    _device.removeListener(_watchLink);
    super.dispose();
  }
}

class _Stop implements Exception {
  const _Stop(this.message, {this.abort = false});
  final String message;

  /// Tell the device to drop what it received.
  final bool abort;
}
