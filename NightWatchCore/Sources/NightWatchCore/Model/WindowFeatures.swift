import Foundation

/// How the forearm is angled, worked out from the direction of gravity.
///
/// Science note: this is the FOREARM, not the body. Your arm hangs vertically
/// when you stand, but an arm resting on a table looks exactly like lying down.
/// So it is logged for later study, but the risk rules give it no weight.
public enum ArmOrientation: String, Codable, Sendable {
    /// e.g. arm hanging by your side while standing, or raised above your head.
    case forearmVertical
    /// e.g. arm resting on a table or lap, or lying down.
    case forearmHorizontal
    case inBetween
    /// The watch turned so much during the window that no steady direction was found.
    case unknown
}

/// Everything learned from the motion sensors in one window.
public struct MotionFeatures: Equatable, Codable, Sendable {
    /// How many motion samples the window contained.
    public var sampleCount: Int
    /// Samples per second actually received.
    public var sampleRateHz: Double
    /// False if too many samples were missing to fully trust this window.
    public var qualityOK: Bool

    /// Gross movement: typical size of gravity-removed acceleration in the
    /// activity band (0.3–4 Hz), in g. About 0.01 sitting, 0.2 walking, 0.5 dancing.
    public var activityG: Double
    /// True if activity is below the stillness threshold in MonitorConfig.
    public var isStill: Bool

    /// Typical size of 4–12 Hz shaking measured by the accelerometer, in milli-g.
    public var tremorAccelMilliG: Double
    /// Typical size of 4–12 Hz shaking measured by the gyroscope (rotation), in degrees per second.
    /// Wrist tremor is mostly a rotation, so this is usually the more sensitive measure.
    public var tremorGyroDegPerSec: Double
    /// The strongest frequency in the tremor band (from the gyroscope), in Hz.
    public var tremorPeakHz: Double
    /// 0 to 1: how much of the tremor-band power sits in one narrow peak.
    /// Near 1 = rhythmic shaking (a real tremor). Around 0.15–0.3 = random jitter.
    public var tremorRhythmicity: Double
    /// True when the tremor numbers can be trusted: the arm was still and
    /// enough samples arrived.
    public var tremorReliable: Bool

    /// Angle of the forearm above horizontal: 0° flat, 90° pointing straight up or down.
    public var forearmElevationDegrees: Double
    public var armOrientation: ArmOrientation
}

/// One finished window: the summary that the filters and risk engine work from.
public struct WindowFeatures: Equatable, Codable, Sendable {
    public var start: Timestamp
    public var end: Timestamp
    /// Median of the heart-rate readings in this window. The median ignores a
    /// single wild reading. Nil if no reading arrived.
    public var heartRateBPM: Double?
    public var heartRateSampleCount: Int
    /// Nil if no motion samples arrived (e.g. in the watch simulator).
    public var motion: MotionFeatures?
    /// Average wrist-temperature change, in °C. Always nil on today's Apple Watch.
    public var wristTemperatureDeviation: Double?

    public init(start: Timestamp,
                end: Timestamp,
                heartRateBPM: Double?,
                heartRateSampleCount: Int,
                motion: MotionFeatures?,
                wristTemperatureDeviation: Double?) {
        self.start = start
        self.end = end
        self.heartRateBPM = heartRateBPM
        self.heartRateSampleCount = heartRateSampleCount
        self.motion = motion
        self.wristTemperatureDeviation = wristTemperatureDeviation
    }
}
