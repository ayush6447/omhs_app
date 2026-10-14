import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omhs_app/data/reading.dart';
import 'package:omhs_app/device/device_service.dart';
import 'package:omhs_app/device/mock_device_service.dart';
import 'package:omhs_app/device/protocol.dart';

/// Exposes the protected hooks so tests can drive the state directly.
class _TestDevice extends MockDeviceService {
  void setTo(LinkStatus s, {LinkIssue? issue, String? error, int attempt = 0}) =>
      setLink(s, issue: issue, error: error, attempt: attempt);
  void feed(String line) => handleLine(line);
}

void main() {
  group('protocol additions', () {
    test('VER line', () {
      final v = parseLine('VER,1.2.0,0.4\r') as VersionEvent;
      expect(v.board1, '1.2.0');
      expect(v.board5, '0.4');
      expect(parseLine('VER'), isNull);
      expect(parseLine('VER,,'), isNull);
      expect((parseLine('VER,1.0') as VersionEvent).board5, '');
    });

    test('firmware is formatted and stamped on readings', () async {
      final d = _TestDevice()..setTo(LinkStatus.connected);
      d.feed('VER,1.2,0.4');
      expect(d.firmware, 'b1 1.2 / b5 0.4');
      final next = d.results.first;
      d.feed('RESULT,190,0.9');
      final Reading r = await next;
      expect(r.firmware, 'b1 1.2 / b5 0.4');
      expect(Reading.fromJson(r.toJson()).firmware, 'b1 1.2 / b5 0.4');
    });
  });

  group('status', () {
    test('each link state has wording and an action', () {
      final d = _TestDevice();
      expect(d.status.title, 'Device not connected');
      expect(d.status.action, StatusAction.connect);

      d.setTo(LinkStatus.searching);
      expect(d.status.action, StatusAction.cancel);
      expect(d.isLinking, isTrue);

      d.setTo(LinkStatus.reconnecting, issue: LinkIssue.lost, attempt: 3);
      expect(d.status.title, 'Reconnecting… (attempt 3)');

      d.setTo(LinkStatus.reconnecting, issue: LinkIssue.bluetoothOff);
      expect(d.status.title, 'Bluetooth is off');
      expect(d.status.action, StatusAction.enableBluetooth);

      d.setTo(LinkStatus.disconnected,
          issue: LinkIssue.noPermission, error: 'Allow it');
      expect(d.status.action, StatusAction.openSettings);
      expect(d.status.detail, 'Allow it');
      expect(d.status.tone, StatusTone.problem);

      d.setTo(LinkStatus.disconnected, issue: LinkIssue.notFound);
      expect(d.status.action, StatusAction.retry);
    });

    test('a drop mid-cycle marks the cycle interrupted', () {
      final d = _TestDevice()..setTo(LinkStatus.connected);
      d.feed('STATE,MEASURE');
      d.setTo(LinkStatus.reconnecting, issue: LinkIssue.lost, attempt: 1);
      expect(d.interruptedCycle, isTrue);
      expect(d.phase, MeasurePhase.idle);

      // Cleared by the next cycle.
      d.setTo(LinkStatus.connected);
      d.feed('STATE,INFLATE');
      expect(d.interruptedCycle, isFalse);
    });

    test('a drop while idle is not an interrupted cycle', () {
      final d = _TestDevice()..setTo(LinkStatus.connected);
      d.feed('STATE,DONE');
      d.setTo(LinkStatus.reconnecting, issue: LinkIssue.lost, attempt: 1);
      expect(d.interruptedCycle, isFalse);
    });
  });

  group('reconnect policy', () {
    const p = ReconnectPolicy();

    test('backs off and caps', () {
      expect([for (var i = 1; i <= 8; i++) p.delayBefore(i).inSeconds],
          [1, 2, 4, 8, 15, 30, 30, 30]);
    });

    test('gives up after two minutes', () {
      expect(p.shouldGiveUp(const Duration(seconds: 119)), isFalse);
      expect(p.shouldGiveUp(const Duration(minutes: 2)), isTrue);
    });

    test('scans every third attempt', () {
      expect([for (var i = 1; i <= 6; i++) p.scanOnAttempt(i)],
          [false, false, true, false, false, true]);
    });
  });

  test('mock drop reconnects and asks for status', () {
    fakeAsync((async) {
      final d = MockDeviceService();
      d.connect();
      async.elapse(const Duration(seconds: 2));
      expect(d.isConnected, isTrue);
      expect(d.firmware, 'b1 0.1-sim / b5 0.1-sim');

      d.start();
      async.elapse(const Duration(seconds: 1));
      expect(d.isBusy, isTrue);

      d.simulateDrop();
      expect(d.link, LinkStatus.reconnecting);
      expect(d.interruptedCycle, isTrue);
      async.elapse(const Duration(seconds: 4));
      expect(d.isConnected, isTrue);
      expect(d.phase, MeasurePhase.idle);
      d.dispose();
    });
  });
}
