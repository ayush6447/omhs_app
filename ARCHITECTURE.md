# OMHS Architecture

## System
```
 Teensy (Board 1)  ──UART text lines──▶  ESP32-C3 (Board 5)  ──BLE NUS──▶  Flutter app
   cuff, LEDs,                              forwards lines                 (Android / iOS)
   optical sensing                          unchanged
 ◀───────────────── CMD,START / CMD,STOP / CMD,STATUS ─────────────────────
```
Board 5 is a transparent bridge, so the app parses exactly what the Teensy
prints. The firmware owns safety (max cuff pressure, max inflation time).

## App layers
```
lib/
  main.dart            wiring: load settings/profiles, pick transport, MultiProvider
  device/              transport + device state
    protocol.dart        line format, DeviceEvent types, parseLine()
    device_service.dart  abstract DeviceService: state machine, status wording,
                         ReconnectPolicy
    ble_device_service.dart   flutter_blue_plus over Nordic UART Service
    mock_device_service.dart  simulated Teensy (OMHS_MOCK=true)
  data/                models + persistence
    reading.dart         immutable Reading (JSON)
    readings_store.dart  history per profile, readings.json in app docs dir
    user_profile.dart    UserProfile + ProfileStore (shared_preferences, photos)
    backup.dart          one-file backup/restore (profiles, photos, readings)
    export.dart          per-profile PDF report + CSV, share sheet
    format.dart          units, age-based cholesterol categories, dates
  theme/               OmhsColors (ThemeExtension), ThemeData, AppSettings
  widgets/             ring gauge, trend chart, nav bar, cards, form fields
  screens/             welcome, setup, home shell, dashboard, measure,
                       history, profile, settings
```

### State (provider + ChangeNotifier)
| Provider | Owns | Persisted in |
|---|---|---|
| `AppSettings` | theme mode, chol unit, body units, setup done | shared_preferences |
| `ProfileStore` | profiles, active profile, photos | shared_preferences + app docs |
| `DeviceService` | link status, phase, pressure, currents, progress, result, firmware | last device ID (BLE) |
| `ReadingsStore` | all readings, filtered to active profile | `readings.json` |

### Data flow for one measurement
1. User taps Start → `DeviceService.start()` → `sendLine("CMD,START")`.
2. BLE notifications are split on `\n` → `handleLine()` → `parseLine()` →
   `DeviceEvent` → state fields updated → `notifyListeners()` → Measure screen
   rebuilds.
3. `RESULT,…` creates a `Reading` (stamped with peak pressure, LED currents,
   firmware) and emits it on `DeviceService.results`.
4. `ReadingsStore` (subscribed to `results`) tags it with the active profile
   and saves (chained writes, temp file + rename).
5. Dashboard / History / TrendChart rebuild from `ReadingsStore`.

## Connection lifecycle (BLE)
- `connect()`: try the remembered device ID directly (8 s), fall back to a
  10 s scan for the NUS UUID or a name containing `OMHS`; remember the ID.
- `resume()` on launch and on returning to the foreground: quiet reconnect to
  the remembered device only.
- On a drop: `ReconnectPolicy` retries after 1, 2, 4, 8, 15, 30 s (then every
  30 s), scans every 3rd attempt, gives up after 2 min. Paused in background,
  restarted when Bluetooth turns back on. Only the same device is accepted.
- After every (re)connect the app sends `CMD,STATUS` so it learns the current
  phase and firmware.
- A drop mid-cycle sets `interruptedCycle`; that cycle's result is discarded.
- A `_session` counter cancels stale connect attempts and retry loops.

## Device protocol (draft)
One message per line, comma separated. Unknown lines are ignored.

| Direction | Line | Meaning |
|---|---|---|
| Device → app | `STATE,IDLE\|INFLATE\|HOLD\|MEASURE\|DEFLATE\|DONE` | Cycle phase |
| Device → app | `P,<mmHg>` | Cuff pressure |
| Device → app | `I,<ch1 mA>,<ch2 mA>` | LED currents (ISENSE1/2) |
| Device → app | `PROG,<0..1>` | Cycle progress |
| Device → app | `RESULT,<mg/dL>,<quality 0..1>` | Estimate + signal quality |
| Device → app | `ERR,<message>` | Fault; app shows it and stops |
| Device → app | `VER,<b1 fw>,<b5 fw>` | Firmware versions |
| App → device | `CMD,START` / `CMD,STOP` | Start / stop a cycle (Stop is a request) |
| App → device | `CMD,STATUS` | Firmware should reply with `STATE` and `VER` |

BLE: service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, RX (write)
`6E400002-…`, TX (notify) `6E400003-…`.

## Storage formats
- `readings.json`: array of `Reading.toJson()`. Unreadable file is renamed
  `readings.json.corrupt-<ts>` and kept.
- Backup: JSON `{format: "omhs-backup", version: 1, createdAt, activeProfileId,
  profiles (photo inlined as base64), readings}`; newer versions are rejected;
  restore replaces everything on the device.
- CSV: one row per reading, both units, firmware column.

## Build & CI
- Android/iOS platform folders are committed. IDs: Android `com.ayuda.omhs.omhs_app`,
  iOS `com.ayuda.omhs.omhsApp`.
- `codemagic.yaml`: `ios-build-check` (unsigned build + IPA for sideloading)
  and `ios-testflight` (signed, uploads to TestFlight). Both manual.

## Tests (`omhs_app/test/`)
- `widget_test.dart`: protocol parsing, formatting, profile model.
- `data_test.dart`: persistence, corruption handling, per-profile filtering,
  backup round trip, CSV/PDF export.
- `device_test.dart`: VER/firmware, status wording, interrupted cycles,
  reconnect policy, mock reconnect (uses `fake_async`).
