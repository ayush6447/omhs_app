# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repo.

## What this is
OMHS v2 companion app: a Flutter app (Android + iOS) that drives an OMHS
cuff-based optical cholesterol device over BLE, shows the live cycle, and
keeps per-profile history with PDF/CSV export and backup/restore.

- Flutter project lives in `omhs_app/`. Run every Flutter command from there.
- `codemagic.yaml` at the repo root builds iOS in the cloud (`working_directory: omhs_app`).
- See `ARCHITECTURE.md` for structure and data flow, `DESIGN.md` for UI rules.

## Commands
```bash
cd omhs_app
flutter pub get
flutter test                                   # unit + store + device tests
flutter analyze                                # no errors/warnings (a few infos exist)
flutter run                                    # real device over BLE
flutter run --dart-define=OMHS_MOCK=true       # simulated device + demo history
firebase deploy --only firestore:rules         # after editing firestore.rules
flutterfire configure --project=omhs-1ec50     # regenerate Firebase config
dart run flutter_launcher_icons                # after changing the logo
```
Requires Flutter 3.27+ (Dart ^3.6; uses `Color.withValues`).

## Rules that matter
- **Protocol changes are two-sided.** `lib/device/protocol.dart` mirrors the
  Teensy firmware's text lines. Change both together and update the table in
  `ARCHITECTURE.md`. Unknown lines must parse to `null`, never throw.
- **Transports stay thin.** `BleDeviceService` / `MockDeviceService` only
  connect, disconnect, `sendLine` and feed lines to `handleLine`. All state
  derivation lives in `DeviceService` so both transports behave the same.
- **No hard-coded colours.** Use `context.omhs` (`OmhsColors`) so light and
  dark themes both work. Numbers/headlines use `mono()`, body text Poppins.
- **Units:** store cholesterol in mg/dL, height in cm, weight in kg. Convert
  only for display (`lib/data/format.dart`).
- **Persistence is crash-safe.** `ReadingsStore` writes temp file + rename,
  chained so writes never overlap; an unreadable file is moved aside, never
  overwritten. Keep it that way.
- **New `Reading` fields** must be optional in `fromJson` (old files and
  backups lack them) and carried through `copyWith`.
- **Firmware updates** go through `FirmwareUpdater` only; keep `OTA,…` in
  `protocol.dart`, the mock and `ARCHITECTURE.md` in step. Never allow an
  update while measuring, or measuring while updating.
- **Notifications:** reminders and alerts are local, asked for only when the
  user turns reminders on. Push (FCM) only via `PushService`.
- **Cloud is optional.** The app must work signed out and when Firebase fails
  to start. Merge logic lives in `cloud/sync_plan.dart` (pure, tested); keep
  Firestore paths, `firestore.rules` and `ARCHITECTURE.md` in step. New
  synced fields need nothing extra (documents are the model's `toJson`), but
  never sync device-local paths (see `photoPath`).
- **Stop is not a safety cutoff.** Firmware enforces max pressure/time; never
  imply otherwise in UI copy.
- **Demo data** is seeded only with `OMHS_MOCK=true`; never mix it into real history.
- flutter_blue_plus is used under `License.nonprofit`; commercial use needs a paid license.

## Style
- Match surrounding code: short doc comments (`///`) explaining *why*,
  `prefer_final_locals`, const constructors, Dart 3 patterns/switch expressions.
- State management is `provider` + `ChangeNotifier`; don't add another library.
- Tests: plain `test()` with `fake_async` for timers; add one for every
  protocol or store change.
