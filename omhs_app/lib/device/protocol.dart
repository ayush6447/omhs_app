/// Text line protocol between the Teensy (Board 1) and the app.
///
/// The Teensy already talks to Board 5 over UART in text lines; Board 5
/// forwards those same lines over BLE unchanged, so the app parses exactly
/// what the Teensy prints. One message per line, comma separated.
///
/// ```text
/// Device -> app
///   STATE,<IDLE|INFLATE|HOLD|MEASURE|DEFLATE|DONE>
///   P,<cuff pressure mmHg>
///   I,<ch1 mA>,<ch2 mA>           (from ISENSE1 / ISENSE2)
///   PROG,<0..1>                   (overall cycle progress)
///   RESULT,<total chol mg/dL>,<quality 0..1>
///   ERR,<message>
///   VER,<board 1 firmware>,<board 5 firmware>
///   OTA,READY[,<max chunk bytes>] (ready for OTA,DATA)
///   OTA,ACK,<next offset>         (chunk written; send from this offset)
///   OTA,OK                        (image verified; device restarts)
///   OTA,FAIL,<message>
///
/// App -> device
///   CMD,START
///   CMD,STOP
///   CMD,STATUS                    (reply with STATE and VER; sent after
///                                  every connect and reconnect)
///   OTA,BEGIN,<B1|B5>,<size bytes>,<crc32 hex>
///   OTA,DATA,<offset>,<base64>    (one chunk; wait for ACK before the next)
///   OTA,END
///   OTA,ABORT
/// ```
///
/// This is a draft; change it here and in the Teensy firmware together.
library;

enum MeasurePhase {
  idle,
  inflating,
  holding,
  measuring,
  deflating,
  done,
  error
}

sealed class DeviceEvent {
  const DeviceEvent();
}

class PhaseEvent extends DeviceEvent {
  const PhaseEvent(this.phase);
  final MeasurePhase phase;
}

class PressureEvent extends DeviceEvent {
  const PressureEvent(this.mmHg);
  final double mmHg;
}

class CurrentEvent extends DeviceEvent {
  const CurrentEvent(this.ch1, this.ch2);
  final double ch1;
  final double ch2;
}

class ProgressEvent extends DeviceEvent {
  const ProgressEvent(this.value);
  final double value;
}

class ResultEvent extends DeviceEvent {
  const ResultEvent(this.mgdl, this.quality);
  final double mgdl;
  final double quality;
}

class VersionEvent extends DeviceEvent {
  const VersionEvent(this.board1, this.board5);
  final String board1;
  final String board5;
}

/// Replies during a firmware update; see firmware_update.dart.
sealed class OtaEvent extends DeviceEvent {
  const OtaEvent();
}

class OtaReadyEvent extends OtaEvent {
  const OtaReadyEvent(this.maxChunk);

  /// Largest chunk the device accepts, in bytes; null when it didn't say.
  final int? maxChunk;
}

class OtaAckEvent extends OtaEvent {
  const OtaAckEvent(this.nextOffset);
  final int nextOffset;
}

class OtaOkEvent extends OtaEvent {
  const OtaOkEvent();
}

class OtaFailEvent extends OtaEvent {
  const OtaFailEvent(this.message);
  final String message;
}

class ErrorEvent extends DeviceEvent {
  const ErrorEvent(this.message);
  final String message;
}

const cmdStart = 'CMD,START';
const cmdStop = 'CMD,STOP';
const cmdStatus = 'CMD,STATUS';

const _phases = {
  'IDLE': MeasurePhase.idle,
  'INFLATE': MeasurePhase.inflating,
  'HOLD': MeasurePhase.holding,
  'MEASURE': MeasurePhase.measuring,
  'DEFLATE': MeasurePhase.deflating,
  'DONE': MeasurePhase.done,
};

/// Returns null for lines the app doesn't understand (e.g. HELLO, BTN,...),
/// so unknown messages are ignored instead of crashing.
DeviceEvent? parseLine(String raw) {
  final line = raw.trim();
  if (line.isEmpty) return null;
  final parts = line.split(',');
  final tag = parts.first.toUpperCase();
  double? n(int i) =>
      i < parts.length ? double.tryParse(parts[i].trim()) : null;

  final a = n(1);
  final b = n(2);

  switch (tag) {
    case 'STATE':
      final p =
          parts.length > 1 ? _phases[parts[1].trim().toUpperCase()] : null;
      return p == null ? null : PhaseEvent(p);
    case 'P':
      return a == null ? null : PressureEvent(a);
    case 'I':
      return (a == null || b == null) ? null : CurrentEvent(a, b);
    case 'PROG':
      return a == null ? null : ProgressEvent(a);
    case 'RESULT':
      return (a == null || b == null) ? null : ResultEvent(a, b);
    case 'VER':
      String part(int i) => i < parts.length ? parts[i].trim() : '';
      final b1 = part(1), b5 = part(2);
      return b1.isEmpty && b5.isEmpty ? null : VersionEvent(b1, b5);
    case 'ERR':
      return ErrorEvent(parts.skip(1).join(',').trim());
    case 'OTA':
      return _parseOta(parts);
    default:
      return null;
  }
}

DeviceEvent? _parseOta(List<String> parts) {
  final kind = parts.length > 1 ? parts[1].trim().toUpperCase() : '';
  final arg = parts.length > 2 ? int.tryParse(parts[2].trim()) : null;
  return switch (kind) {
    'READY' => OtaReadyEvent(arg != null && arg > 0 ? arg : null),
    'ACK' => arg == null || arg < 0 ? null : OtaAckEvent(arg),
    'OK' => const OtaOkEvent(),
    'FAIL' => OtaFailEvent(parts.skip(2).join(',').trim()),
    _ => null,
  };
}
