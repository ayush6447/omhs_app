# OMHS v2 – Flutter app (Android + iOS)

Companion app for the OMHS device. It shows the live measurement cycle, the result, and a history of readings, and it can start and stop a cycle. It talks to the Teensy (Board 1) through Board 5 (ESP32-C3, BLE).

The UI is dual-toned: royal blue with soft lavender/pink, and a cyan accent. It has light and dark themes; switch with the sun/moon button on any screen or under **Settings → Appearance** (System / Light / Dark). The choice is saved on the phone.

The app connects to Board 5 over BLE (Nordic UART Service, `lib/device/ble_device_service.dart`). It scans for a device advertising the NUS UUID or with `OMHS` in its name. To use the simulated device instead (full cycle: inflate → hold → measure → deflate → result, no hardware needed), run with `--dart-define=OMHS_MOCK=true`.

## Run it
The repo contains `lib/`, `test/`, `assets/` and `pubspec.yaml`. Generate the Android and iOS platform folders once, then run:

```bash
cd omhs_app
flutter create . --platforms=android,ios --org com.ayuda.omhs --project-name omhs_app
flutter pub get
flutter test          # protocol + formatting tests
flutter run
```

`flutter create .` only adds the missing platform files; it does not overwrite `lib/` or `pubspec.yaml`.

Requires Flutter 3.27 or newer (uses `Color.withValues`).

## Screens
| Screen | What it shows |
|---|---|
| Welcome | Blue hero screen with the cross logo. "Connect device" or "Explore first". |
| Dashboard | Ring gauge with the latest total cholesterol (0–300 mg/dL scale) and category, device status, signal quality, peak cuff pressure, readings this week. |
| Measure | Live card: phase, cuff pressure, cycle progress, Inflate/Hold/Measure/Deflate steps. LED currents for both channels. Start / Stop. Result when done. |
| History | Search (notes, dates, values), filters (All, Desirable, Borderline, High, Flagged), reading cards. Tap a card for LED currents, peak pressure, flag and note. |
| Settings | Theme (System/Light/Dark), units (mg/dL or mmol/L), device connect/disconnect, about. |

Categories use the standard adult total-cholesterol bands: < 200 desirable, 200–239 borderline, ≥ 240 high.

## Code layout
```
lib/
  main.dart                  providers + MaterialApp (light/dark themes)
  theme/
    app_colors.dart          OmhsColors palette (light + dark), context.omhs
    app_theme.dart           ThemeData, mono() text style
    app_settings.dart        theme mode + units, saved with shared_preferences
  device/
    protocol.dart            text line protocol + parser
    device_service.dart      device state built from protocol lines
    mock_device_service.dart simulated Teensy
  data/
    reading.dart, readings_store.dart, format.dart
  widgets/                   ring gauge, cross logo, pill nav bar, tiles, buttons
  screens/                   welcome, home shell, dashboard, measure, history, settings
assets/fonts/                Poppins + Space Mono, bundled (works offline)
```

Every colour comes from `OmhsColors` via `context.omhs`, so a new screen gets dark mode for free as long as it doesn't hard-code colours.

## Device protocol (draft)
Board 5 forwards the Teensy's UART text lines over BLE unchanged, so the app parses exactly what the Teensy prints. One message per line, comma separated. Unknown lines (`HELLO,n`, `BTN,START`, …) are ignored.

| Direction | Line | Meaning |
|---|---|---|
| Device → app | `STATE,IDLE\|INFLATE\|HOLD\|MEASURE\|DEFLATE\|DONE` | Cycle phase |
| Device → app | `P,<mmHg>` | Cuff pressure |
| Device → app | `I,<ch1 mA>,<ch2 mA>` | LED currents from ISENSE1 / ISENSE2 |
| Device → app | `PROG,<0..1>` | Overall cycle progress |
| Device → app | `RESULT,<mg/dL>,<quality 0..1>` | Final estimate + signal quality |
| Device → app | `ERR,<message>` | Fault (app shows it and stops) |
| App → device | `CMD,START` / `CMD,STOP` | Start or stop a cycle |

The app's Stop is a request, not a safety cutoff. The Teensy firmware must enforce the maximum cuff pressure and inflation time on its own.

## Next steps
1. **BLE firmware.** Board 5 must expose the Nordic UART Service (`6E400001-…`): notify on TX `6E400003-…` with the Teensy's lines ending in `
`, accept commands on RX `6E400002-…`, and advertise a name containing `OMHS`. flutter_blue_plus is used under its nonprofit license (`License.nonprofit` in `ble_device_service.dart`); commercial use needs a paid license.
2. **Persistence.** `ReadingsStore` is in memory; move it to sqflite or Hive, and add CSV export for the clinic data.
3. **Remove demo data.** `ReadingsStore(device, seedDemoData: true)` in `main.dart` seeds 8 sample readings. Set it to `false` for real use.
4. **Raw data.** For calibration you will want the raw optical samples, not just the result. Add a `RAW,...` line and store it per reading.
