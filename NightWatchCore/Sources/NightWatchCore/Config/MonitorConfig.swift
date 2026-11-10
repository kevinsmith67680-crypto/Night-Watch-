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

    public init(features: FeatureConfig = FeatureConfig()) {
        self.features = features
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
