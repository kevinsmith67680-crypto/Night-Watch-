# Night Watch

> **Prototype — not a medical device.** It does not diagnose anything.
> If someone has chest pain, is overheating or having a seizure, **call 999**.

A proof-of-concept Apple Watch app that looks for physiological patterns
consistent with stimulant toxicity: heart rate that is higher than expected
for how much the wearer is moving, while they are still, together with
increased tremor.

All data stays on the user's own watch and iPhone. No accounts, no servers.

## How it works

```
Sensors ──► Feature extraction ──► Filters ──► Risk engine ──► UI
```

1. **Excess heart rate** = measured HR − expected HR, where expected HR comes
   from a personal baseline (resting HR + k × recent activity, with a lag for
   heart-rate recovery).
2. **Tremor**: rhythmic 4–12 Hz wrist motion, measured only when the arm is
   fairly still.
3. **Kalman filter** smooths excess HR, rejects one-off spikes and tracks its
   trend.
4. **Placeholder risk rules** (temporary) turn that into green / amber / red.
   An Interacting Multiple Model (IMM) filter will replace them later.

## Repository layout

| Folder | What it is |
|---|---|
| `NightWatchCore/` | Swift package with all the logic and its tests. Plain Swift, no Apple-only frameworks. **All tunable numbers are in `Sources/NightWatchCore/Config/MonitorConfig.swift`.** |
| `NightWatch Watch App/` | The watchOS app: sensors (HealthKit, CoreMotion) and screens. |
| `NightWatch/` | Minimal iPhone companion. It only receives CSV logs from the watch. |
| `Config/` | Watch app Info.plist additions and entitlements (HealthKit, workout background mode). |
| `NightWatch.xcodeproj` | The Xcode project. Needs **Xcode 16 or newer**. |

The project uses Xcode's *synchronized folders*: any file placed in
`NightWatch Watch App/` or `NightWatch/` is automatically part of that app.

## Getting started

1. Open `NightWatch.xcodeproj` in Xcode.
2. For **both** targets, open *Signing & Capabilities* and choose your Team.
3. Pick the **NightWatch Watch App** scheme and an Apple Watch (simulator or
   your own watch), then press ▶︎ Run.

Run the logic tests in Terminal:

```bash
cd NightWatchCore
swift test
```

## Build stages

- [x] 1. Project setup, HealthKit permissions
- [x] 2. Live heart rate (monitoring mode)
- [x] 3. Motion features (activity, tremor, arm orientation)
  - [x] 3a. Feature maths and tests (`NightWatchCore`)
  - [x] 3b. Real motion sensors on the watch
- [x] 4. Baseline calibration
- [x] 5. Kalman filter for excess heart rate
- [x] 6. Placeholder traffic-light display
- [ ] 7. CSV logging, export to iPhone, simulation scenarios, tests

## Requirements

- Apple Watch Series 10 (watchOS 11 or later)
- iPhone on iOS 18 or later
- Mac with Xcode 16 or later
