# OMHS Design

The visual language of the OMHS app. Source of truth in code:
`omhs_app/lib/theme/` (`app_colors.dart`, `app_theme.dart`) and
`omhs_app/lib/widgets/`.

## Principles
1. **Calm, clinical, friendly.** Readings can be worrying; the UI stays soft
   (rounded shapes, pastel tints) and states plainly what to do next.
2. **One glance.** The latest number, its category and the device status are
   visible without scrolling on the Dashboard.
3. **Always say what's wrong and offer the fix.** Every link problem maps to a
   title, a detail and one action (Connect, Retry, Turn on, Settings, Cancel)
   via `DeviceStatusInfo`, so every screen words it the same way.
4. **Works offline.** Fonts are bundled; nothing is fetched at runtime.

## Colour
Dual-tone: royal blue + soft lavender/pink, with a cyan accent. Every colour
is a role in `OmhsColors`, read with `context.omhs`. Never hard-code a hex in a
widget; add a role instead (and give it light and dark values).

| Role | Light | Dark | Used for |
|---|---|---|---|
| `bg` | `#FBFBFF` | `#0A0E2E` | Page background |
| `surface` | `#FFFFFF` | `#1A2157` | Sheets, dialogs |
| `surfaceAlt` | `#F1F2FB` | `#151B4E` | Tinted cards, tiles |
| `hero` | `#1F32C4` | `#1A2690` | Welcome screen, live measurement card |
| `primary` | `#1F32C4` | `#5566FF` | Buttons, nav bar, links |
| `pink` | `#FFD3E3` | `#FFB8D1` | Secondary accents, ring wedges |
| `cyan` | `#1FE3F0` | `#3BEAF4` | Highlights on blue |
| `text` / `muted` | `#101A73` / `#7A7FA6` | `#EEF0FF` / `#98A0D8` | Body / secondary text |
| `ok` / `danger` | `#16A34A` / `#E5484D` | `#4ADE80` / `#FF6B7A` | Status, high readings, errors |

Ring gauge has its own roles (`ringTrack`, `ringSegA/B`, `ringStart → ringEnd`
gradient). Theme switches animate (350 ms) because `OmhsColors.lerp` blends
every role.

## Type
- **Poppins** (400/500/600/700): body and UI text.
- **Space Mono** (400/700) via `mono(size)`: numbers, headlines, badges.
  Readings, pressures and currents are always mono so digits line up.
- Common sizes: 12–13 labels, 15 nav, 20 tile values, large mono for the ring.

## Shape & components
| Component | Notes |
|---|---|
| `PillNavBar` | Floating blue pill, 64 px tall, radius 32, soft shadow; 4 tabs. |
| `PillButton` | Filled or outline pill; primary actions. |
| `SoftCard` | Tinted (`surfaceAlt`) card, radius 22. |
| `MetricTile` | Label + dot above a radius‑16 tile, `value / max` in mono. |
| `RingGauge` | Dashboard ring: latest total cholesterol on a 0–300 mg/dL scale. |
| `HeroRing` | Simpler ring on the blue live card (cycle progress). |
| `TrendChart` | Line over desirable/borderline/high bands; tap/drag to inspect. |
| `CategoryBadge` / `PillBadge` | Radius‑8 mono badges. |
| `SegmentedPill` | Radius‑30 segmented control (units, theme, filters). |
| Bottom sheets | `surface`, radius‑28 top corners, drag handle. |
| Snackbars | Floating, inverted (`text` background). |

## Categories
Total cholesterol bands (mg/dL), age-aware (`CholRanges` in `format.dart`):
- Adults 20+ (NCEP ATP III): < 200 Desirable, 200–239 Borderline, ≥ 240 High.
- Under 20 (NHLBI 2011): lower cut-offs.
- Unknown age: adult bands.

Units: mg/dL or mmol/L; height cm or ft/in; weight kg or lb. Stored metric.

## Screens
Welcome → (first run) Setup → Home shell with Dashboard · Measure · History ·
Settings, plus Profile (multi-profile, photo, risk factors). The theme toggle
(sun/moon) is reachable from every screen.

## Copy
Short, plain sentences. Tell the user what happens next ("The app reconnects
when Bluetooth is back on."). Never present the app's Stop as a safety control.
