import Foundation

/// EVERY number you might want to tune lives in this file.
///
/// How to tune safely:
///   1. change one value at a time;
///   2. run the tests (`swift test`) to check nothing broke;
///   3. compare the CSV logs or simulator runs before and after.
///
/// Later steps add sections here for calibration, the Kalman filter and the
/// risk rules.
public struct MonitorConfig: Codable, Equatable, Sendable {
    public var features: FeatureConfig
    public var calibration: CalibrationConfig
    public var kalman: KalmanConfig
    public var risk: RiskConfig

    public init(features: FeatureConfig = FeatureConfig(),
                calibration: CalibrationConfig = CalibrationConfig(),
                kalman: KalmanConfig = KalmanConfig(),
                risk: RiskConfig = RiskConfig()) {
        self.features = features
        self.calibration = calibration
        self.kalman = kalman
        self.risk = risk
    }

    /// The values the app uses unless you change them.
    public static let standard = MonitorConfig()
}

/// Step 3: turning raw motion into one set of features every few seconds.
public struct FeatureConfig: Codable, Equatable, Sendable {

    // MARK: Windows

    /// Length of each analysis window, in seconds.
    /// 5 s at 50 Hz = 250 samples, which separates frequencies 0.2 Hz apart.
    /// Longer = steadier numbers but slower to react.
    public var windowSeconds: Double = 5

    /// Motion samples per second requested from the watch.
    /// Must be more than twice the highest frequency we study (12 Hz), so 50 is comfortable.
    public var motionSampleRateHz: Double = 50

    /// A window must contain at least this fraction of the expected samples to be
    /// trusted. 0.8 means 200 of 250. Windows with fewer are kept but marked poor quality.
    public var minimumSampleFraction: Double = 0.8

    // MARK: Frequency bands (Hz). Each band runs from "low" up to, but not including, "high".

    /// Gross movement: walking, dancing, gesturing (mostly 0.5–3 Hz).
    /// Below 0.3 Hz is ignored because it is mostly slow sensor drift.
    public var activityBandLowHz: Double = 0.3
    public var activityBandHighHz: Double = 4.0

    /// Tremor: small rhythmic shaking. Physiological tremor is strongest at 8–12 Hz;
    /// stimulants, caffeine, anxiety and cold make it bigger, not faster.
    public var tremorBandLowHz: Double = 4.0
    public var tremorBandHighHz: Double = 12.0

    /// When judging how rhythmic a tremor is, power within ± this many Hz of the
    /// strongest frequency counts as "the peak".
    public var rhythmicityHalfWidthHz: Double = 0.6

    // MARK: Stillness

    /// Activity (in g) below which the wearer counts as STILL.
    /// Rough guide: sitting ≈ 0.01, gesturing while talking ≈ 0.03–0.08,
    /// walking ≈ 0.15–0.3, dancing ≈ 0.3–1.
    /// Tremor is only trusted in still windows, because movement swamps it.
    /// TUNE THIS from your own CSV logs.
    public var stillnessThresholdG: Double = 0.05

    // MARK: Arm orientation

    /// Forearm angle above horizontal (degrees) at or above which it counts as
    /// "vertical", e.g. arm hanging by your side while standing, or raised.
    public var forearmVerticalFromDegrees: Double = 60
    /// Forearm angle at or below which it counts as "horizontal", e.g. resting
    /// on a table or lap, or lying down. The watch alone can't tell these apart.
    public var forearmHorizontalUpToDegrees: Double = 30

    public init() {}
}

/// Step 4: learning your personal baseline,
/// expected heart rate = resting heart rate + k × (recent activity).
public struct CalibrationConfig: Codable, Equatable, Sendable {

    // MARK: How much data is needed

    /// Minimum usable recording, in minutes, before a baseline can be calculated.
    /// Spread it over 2–4 sessions on normal days.
    public var minimumTotalMinutes: Double = 60
    /// Of which at least this many minutes sitting or standing quietly
    /// (pins down the resting heart rate)…
    public var minimumStillMinutes: Double = 20
    /// …and at least this many minutes active (pins down k).
    public var minimumActiveMinutes: Double = 10
    /// Activity (g) at or above which a window counts as "active": brisk walking or more.
    public var activeThresholdG: Double = 0.1
    /// Optional: minutes of still windows with reliable tremor readings needed
    /// to learn your personal normal tremor. Without it, the risk rules fall
    /// back to a fixed tremor threshold.
    public var minimumTremorMinutes: Double = 5

    // MARK: Fitting

    /// The first seconds of each recording are left out of the fit, while the
    /// heart-rate lag settles.
    public var warmUpSeconds: Double = 60
    /// A pause longer than this (seconds) between usable windows starts a new segment.
    public var maxGapSeconds: Double = 30
    /// Heart rate follows movement with a delay: it rises over roughly 15–60 s
    /// and falls back more slowly, over 1–4 minutes. Calibration tries every pair
    /// below and keeps whichever fits your data best.
    public var lagRiseCandidatesSeconds: [Double] = [15, 30, 60]
    public var lagFallCandidatesSeconds: [Double] = [60, 120, 240]
    /// Readings further than this many standard deviations from the fitted line
    /// are treated as glitches (e.g. strap slips) and left out.
    public var outlierCutoffSD: Double = 3
    /// Warn if the calibrated resting heart rate differs from Apple's own daily
    /// resting heart rate by more than this many bpm.
    public var appleDisagreementWarningBPM: Double = 15

    // MARK: Used until you have calibrated

    /// Rough population defaults. Monitoring uses them until calibration is done,
    /// so expected heart rate will be less accurate until then.
    public var defaultRestingBPM: Double = 70
    /// bpm added per 1 g of activity: about +24 bpm walking (0.2 g), +60 dancing (0.5 g).
    public var defaultBPMPerG: Double = 120
    public var defaultLagRiseSeconds: Double = 30
    public var defaultLagFallSeconds: Double = 120

    public init() {}
}

/// Step 5: the Kalman filter that smooths excess heart rate.
///
/// It tracks two things: the excess heart rate itself and its TREND (how fast it
/// is changing, in bpm per minute). Each 5-second measurement nudges both.
public struct KalmanConfig: Codable, Equatable, Sendable {

    // MARK: How much to trust each measurement ("measurement noise")

    /// Typical error of one measurement at rest (bpm, 1 standard deviation),
    /// used before calibration. Bigger = smoother but slower to respond.
    public var measurementSDBPM: Double = 5
    /// After calibration, use your own typical error (from the baseline) instead.
    public var useCalibratedMeasurementSD: Bool = true
    /// Never trust a measurement more than this (bpm), even if calibration says so.
    public var minimumMeasurementSDBPM: Double = 2
    /// Wrist heart rate is less reliable while moving, so the measurement error
    /// grows by this many bpm per 1 g of activity. At 0.5 g (dancing) that is +10 bpm.
    public var extraMeasurementSDPerG: Double = 20

    // MARK: How quickly the trend may change ("process noise")

    /// How much the trend (bpm per minute) is allowed to change in one minute
    /// (1 standard deviation). Tested in simulation:
    ///   0.2 → very steady at rest; a 2 bpm/min climb is noticed after about 3 min.
    ///   0.3 → trend stays within about ±0.8 bpm/min at rest; climb noticed after about 2.5 min.
    ///   0.5 → trend jitters about ±1.1 bpm/min at rest; climb noticed after about 2 min.
    /// Bigger = reacts faster but jumpier.
    public var trendChangePerMinute: Double = 0.3
    /// How unsure the trend is at the very start (bpm per minute).
    public var initialTrendSDBPMPerMinute: Double = 2

    // MARK: Spike rejection

    /// A measurement further than this many standard deviations from what the
    /// filter expected is treated as a spike (e.g. strap slip) and ignored.
    public var spikeGateSD: Double = 4
    /// …unless this many in a row are "spikes": then it is a real change, and the
    /// filter restarts from the new level (3 windows = 15 seconds).
    public var acceptAfterConsecutiveRejections: Int = 3
    /// After a gap with no heart rate longer than this (seconds), start afresh.
    public var restartAfterGapSeconds: Double = 120

    public init() {}
}

/// Step 6: TEMPORARY traffic-light rules, used until the IMM filter replaces them.
///
/// ⚠️ These numbers are educated guesses for a prototype, NOT clinical
/// thresholds. Tune them with your CSV logs and the simulator (Step 7).
///
/// "Still" means activity below `FeatureConfig.stillnessThresholdG`, allowing
/// brief movements (see `maxMovingWindowsInStillPeriod`).
/// "Excess" and "trend" are the Kalman-filtered values from Step 5.
public struct RiskConfig: Codable, Equatable, Sendable {

    // MARK: Stillness

    /// Up to this many moving windows in a row (2 × 5 s = 10 s, e.g. scratching
    /// your nose) don't end a still period.
    public var maxMovingWindowsInStillPeriod: Int = 2

    // MARK: Amber

    /// Amber if still for `amberStillMinutes` AND excess ≥ this AND rising…
    public var amberExcessRisingBPM: Double = 20
    /// …where "rising" means a trend of at least this many bpm per minute.
    public var amberRisingTrendBPMPerMinute: Double = 0.5
    /// Amber if still for `amberStillMinutes` AND excess ≥ this AND not falling.
    public var amberExcessSteadyBPM: Double = 25
    public var amberStillMinutes: Double = 5
    /// Backstop that works even without calibration:
    /// amber if heart rate ≥ this while still for `amberAbsoluteStillMinutes`.
    public var amberAbsoluteHeartRateBPM: Double = 110
    public var amberAbsoluteStillMinutes: Double = 10

    // MARK: Red

    /// Red if still for `redStillMinutes` AND excess ≥ this AND
    /// (rising at least `redRisingTrendBPMPerMinute` OR tremor raised).
    public var redExcessBPM: Double = 35
    public var redRisingTrendBPMPerMinute: Double = 1.0
    /// Red if still AND excess ≥ this AND not falling, whatever the trend or tremor.
    public var redExcessAloneBPM: Double = 45
    public var redStillMinutes: Double = 5
    /// Backstop: red if heart rate ≥ this while still for `redAbsoluteStillMinutes`.
    public var redAbsoluteHeartRateBPM: Double = 140
    public var redAbsoluteStillMinutes: Double = 5

    // MARK: Shared

    /// "Not falling" means a trend above this (bpm per minute). A clearly falling
    /// excess, e.g. recovering after exercise, never raises the level.
    public var notFallingTrendBPMPerMinute: Double = -0.5
    /// Tremor counts as raised when, over the last `tremorLookbackMinutes`, at
    /// least half the windows had reliable tremor readings, their median
    /// rhythmicity is at least `tremorMinimumRhythmicity`, and their median size
    /// is at or above the tremor threshold:
    ///  • with a personal tremor baseline (from calibration):
    ///    `tremorRaisedMultiplier` × your normal, but never below `tremorRaisedMinimumDegPerSec`;
    ///  • without one: the fixed `tremorRaisedDegPerSec` (a PLACEHOLDER guess).
    public var tremorRaisedMultiplier: Double = 2.0
    public var tremorRaisedMinimumDegPerSec: Double = 1.0
    public var tremorRaisedDegPerSec: Double = 2.0
    public var tremorMinimumRhythmicity: Double = 0.5
    public var tremorLookbackMinutes: Double = 2

    // MARK: Behaviour

    /// Once raised, the light only steps down after the warning signs have been
    /// clear for this long, so it doesn't flicker.
    public var stepDownAfterMinutes: Double = 3
    /// Heart rate older than this (seconds) counts as "no recent heart rate".
    public var staleHeartRateSeconds: Double = 60
    /// Before calibration the excess is unreliable, so only the absolute
    /// heart-rate backstops are used.
    public var requireCalibrationForExcessRules: Bool = true

    // MARK: Alerts (on the wearer's own watch only; nothing is sent anywhere)

    /// Tap the wrist when the light turns amber or red.
    public var hapticAlertsEnabled: Bool = true
    /// While red, tap again this often (minutes).
    public var redHapticRepeatMinutes: Double = 2

    public init() {}
}
