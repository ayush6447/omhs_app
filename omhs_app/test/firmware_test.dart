import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omhs_app/device/device_service.dart';
import 'package:omhs_app/device/firmware_update.dart';
import 'package:omhs_app/device/mock_device_service.dart';
import 'package:omhs_app/device/protocol.dart';

/// Answers BEGIN and then goes quiet, or rejects the data.
class _StubDevice extends MockDeviceService {
  _StubDevice({this.failData = false});

  final bool failData;
  final sentLines = <String>[];

  void goLive() => setLink(LinkStatus.connected, name: 'stub');
  void drop() => setLink(LinkStatus.reconnecting,
      issue: LinkIssue.lost, attempt: 1);

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
    if (line.startsWith('OTA,BEGIN')) {
      Future<void>.delayed(Duration.zero, () => handleLine('OTA,READY'));
    } else if (failData && line.startsWith('OTA,DATA')) {
      Future<void>.delayed(
          Duration.zero, () => handleLine('OTA,FAIL,flash write error'));
    }
  }
}

/// An ESP32-looking image of [n] bytes.
Uint8List _image(int n) =>
    Uint8List.fromList([0xE9, for (var i = 1; i < n; i++) i % 251]);

MockDeviceService _connectedMock(FakeAsync async) {
  final d = MockDeviceService();
  d.connect();
  async.elapse(const Duration(seconds: 2));
  expect(d.isConnected, isTrue);
  return d;
}

void main() {
  test('crc32 matches the standard check value', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    expect(crc32(const []), 0);
  });

  test('OTA replies parse', () {
    expect((parseLine('OTA,READY,256') as OtaReadyEvent).maxChunk, 256);
    expect((parseLine('OTA,READY') as OtaReadyEvent).maxChunk, isNull);
    expect((parseLine('OTA,ACK,1024\r') as OtaAckEvent).nextOffset, 1024);
    expect(parseLine('OTA,ACK,x'), isNull);
    expect(parseLine('OTA,OK'), isA<OtaOkEvent>());
    expect((parseLine('OTA,FAIL,bad crc, retry') as OtaFailEvent).message,
        'bad crc, retry');
    expect(parseLine('OTA,WHAT'), isNull);
  });

  test('images are checked before sending', () {
    expect(FirmwareUpdater.check(FirmwareTarget.board1, Uint8List(0)),
        isNotNull);
    expect(
        FirmwareUpdater.check(
            FirmwareTarget.board5, Uint8List.fromList([1, 2, 3])),
        contains('ESP32'));
    expect(FirmwareUpdater.check(FirmwareTarget.board5, _image(10)), isNull);
    // The Teensy image has no magic byte to check.
    expect(
        FirmwareUpdater.check(
            FirmwareTarget.board1, Uint8List.fromList([1, 2, 3])),
        isNull);
  });

  test('Board 1 update completes and the new version is read back', () {
    fakeAsync((async) {
      final d = _connectedMock(async);
      final u = FirmwareUpdater(d);
      final seen = <UpdateStage>{};
      u.addListener(() => seen.add(u.stage));

      u.run(FirmwareTarget.board1, _image(1000));
      async.elapse(const Duration(milliseconds: 1));
      expect(d.isUpdatingFirmware, isTrue);
      async.elapse(const Duration(seconds: 1));

      expect(u.stage, UpdateStage.done, reason: u.error);
      expect(u.sent, 1000);
      expect(seen, containsAll([UpdateStage.sending, UpdateStage.verifying]));
      expect(d.isUpdatingFirmware, isFalse);
      async.elapse(const Duration(seconds: 7));
      expect(d.firmware, 'b1 0.2-sim / b5 0.1-sim');
      u.dispose();
      d.dispose();
    });
  });

  test('Board 5 update restarts the link and reconnects', () {
    fakeAsync((async) {
      final d = _connectedMock(async);
      final u = FirmwareUpdater(d);
      u.run(FirmwareTarget.board5, _image(5000));
      async.elapse(const Duration(seconds: 1));
      expect(u.stage, UpdateStage.done, reason: u.error);

      async.elapse(const Duration(milliseconds: 300));
      expect(d.link, LinkStatus.reconnecting);
      async.elapse(const Duration(seconds: 4));
      expect(d.isConnected, isTrue);
      expect(d.firmware, 'b1 0.1-sim / b5 0.2-sim');
      u.dispose();
      d.dispose();
    });
  });

  test('measuring is blocked during an update', () {
    fakeAsync((async) {
      final d = _StubDevice()..goLive();
      final u = FirmwareUpdater(d);
      u.run(FirmwareTarget.board1, _image(500));
      async.elapse(const Duration(milliseconds: 1));
      d.start();
      expect(d.sentLines, isNot(contains(cmdStart)));
      u.cancel();
      async.flushMicrotasks();
      u.dispose();
    });
  });

  test('a silent device is retried, then the update is aborted', () {
    fakeAsync((async) {
      final d = _StubDevice()..goLive();
      final u = FirmwareUpdater(d);
      u.run(FirmwareTarget.board1, _image(500));
      async.elapse(const Duration(seconds: 30));

      expect(u.stage, UpdateStage.failed);
      expect(u.error, contains('stopped responding'));
      // First send plus three retries of the same chunk, then ABORT.
      expect(d.sentLines.where((l) => l.startsWith('OTA,DATA,0,')).length, 4);
      expect(d.sentLines.last, 'OTA,ABORT');
      expect(d.isUpdatingFirmware, isFalse);
      u.dispose();
    });
  });

  test('the device rejecting data fails with its message', () {
    fakeAsync((async) {
      final d = _StubDevice(failData: true)..goLive();
      final u = FirmwareUpdater(d);
      u.run(FirmwareTarget.board1, _image(500));
      async.elapse(const Duration(seconds: 1));
      expect(u.stage, UpdateStage.failed);
      expect(u.error, contains('flash write error'));
      u.dispose();
    });
  });

  test('a dropped link fails the update without ABORT', () {
    fakeAsync((async) {
      final d = _StubDevice()..goLive();
      final u = FirmwareUpdater(d);
      u.run(FirmwareTarget.board1, _image(500));
      async.elapse(const Duration(milliseconds: 1));
      d.drop();
      async.flushMicrotasks();
      expect(u.stage, UpdateStage.failed);
      expect(u.error, contains('Connection lost'));
      expect(d.sentLines, isNot(contains('OTA,ABORT')));
      u.dispose();
    });
  });

  test('cancel sends ABORT', () {
    fakeAsync((async) {
      final d = _StubDevice()..goLive();
      final u = FirmwareUpdater(d);
      u.run(FirmwareTarget.board1, _image(500));
      async.elapse(const Duration(milliseconds: 1));
      u.cancel();
      async.flushMicrotasks();
      expect(u.stage, UpdateStage.failed);
      expect(u.error, contains('cancelled'));
      expect(d.sentLines.last, 'OTA,ABORT');
      u.dispose();
    });
  });

  test('not connected: fails at once', () {
    final u = FirmwareUpdater(MockDeviceService());
    u.run(FirmwareTarget.board1, _image(10));
    expect(u.stage, UpdateStage.failed);
    expect(u.error, 'Connect the device first.');
  });
}
