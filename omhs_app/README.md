# OMHS v2 – Flutter app (Android + iOS)

Companion app for the OMHS cholesterol device. It connects to Board 5
(ESP32-C3) over BLE, starts/stops a measurement cycle, shows it live
(inflate → hold → measure → deflate → result), and keeps per-profile history
with trend chart, PDF/CSV export and backup/restore. Light and dark themes,
mg/dL or mmol/L, metric or imperial.

## Run
```bash
cd omhs_app
flutter pub get
flutter test
flutter run                                  # real device over BLE
flutter run --dart-define=OMHS_MOCK=true     # simulated device, no hardware
```
Requires Flutter 3.27+. iOS cloud builds: `codemagic.yaml` at the repo root.

## Features
- **Dashboard:** ring gauge with latest total cholesterol and category, trend
  chart, device status, signal quality, readings this week.
- **Measure:** live phase, cuff pressure, progress, LED currents, result.
- **History:** search, filters (Desirable/Borderline/High/Flagged), notes, flags,
  PDF report and CSV export.
- **Profiles:** multiple people per phone, photo, age-based categories.
- **Settings:** theme, units, device connect/forget, firmware version, backup.
- **Firmware updates over BLE** (Settings → Update firmware) for Board 1 or
  Board 5, with CRC check, progress and cancel. Needs firmware support
  (draft protocol in ARCHITECTURE.md); works end to end with `OMHS_MOCK=true`.
- **Reminders & trend alerts:** daily or weekly measurement reminder; high,
  rising, worse-band and weak-signal readings are pointed out on screen (and
  as a notification if the app is in the background).
- **Auto-reconnect:** remembers the last device and reconnects with back-off
  (gives up after 2 min, resumes on foreground / Bluetooth on).

## Docs
- [ARCHITECTURE.md](../ARCHITECTURE.md) — layers, data flow, BLE lifecycle, device protocol
- [DESIGN.md](../DESIGN.md) — colours, type, components, categories
- [CLAUDE.md](../CLAUDE.md) — rules for contributors and coding agents

> The app's Stop is a request, not a safety cutoff. The Teensy firmware must
> enforce max cuff pressure and inflation time. flutter_blue_plus is used under
> its nonprofit license; commercial use needs a paid license.

## Future upgrades
Done: firmware updates over BLE (app side) and reminders/trend alerts.

**Device & data**
1. **Raw optical samples** – add a `RAW,…` line and store samples per reading
   for calibration and algorithm work.
2. **OTA firmware side + speed** – implement the `OTA,…` protocol on Board 5
   and the Teensy; then a sliding window (several chunks in flight) or a
   binary characteristic for faster updates.
3. **Device calibration flow** – guided cuff/LED self-test before measuring.
4. **SQLite storage** (drift/sqflite) once history grows; keep JSON for backup.
5. **Encrypted storage + app lock** (biometric/PIN), since this is health data.

**Clinical & sync**
6. **Cloud sync / clinic dashboard** – optional account, multi-device sync,
   clinician view of patients.
7. **Health platform export** – Apple Health / Health Connect, FHIR
   Observation export for EHRs.
8. **Fuller lipid panel** – HDL/LDL/triglycerides if the hardware supports it;
   sex-specific ranges.
9. **Smarter reminders** – skip the reminder when you've already measured
   that day; per-profile schedules.

**App quality**
10. **Localization** (Hindi and others) and accessibility pass (screen reader
    labels, dynamic type, contrast).
11. **Android CI** – add Android build + `flutter test` + `flutter analyze` to
    Codemagic or GitHub Actions; integration tests with the mock device.
12. **Crash reporting & analytics** (opt-in), and a commercial BLE license
    before any commercial release.
