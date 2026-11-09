# Vigil (working name)

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
| `VigilCore/` | Swift package with all the logic and tests. Plain Swift, no Apple-only frameworks, so tests run on a Mac in seconds. |
| `Vigil Watch App/` | The watchOS app: sensors (HealthKit, CoreMotion) and screens. |
| `Vigil (iPhone)/` | A minimal companion app that only receives CSV logs from the watch. |

## Build stages

- [ ] 1. Project setup, HealthKit permissions
- [ ] 2. Live heart rate (monitoring mode)
- [ ] 3. Motion features (activity, tremor, arm orientation)
- [ ] 4. Baseline calibration
- [ ] 5. Kalman filter for excess heart rate
- [ ] 6. Placeholder traffic-light display
- [ ] 7. CSV logging, export to iPhone, simulation scenarios, tests

## Requirements

- Apple Watch Series 10 (watchOS 11 or later)
- Paired iPhone
- Mac with Xcode
