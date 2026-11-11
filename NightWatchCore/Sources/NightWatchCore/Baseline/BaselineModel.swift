import Foundation

/// Your personal heart-rate baseline:
///
///     expected heart rate = resting heart rate + k × lagged activity
///
/// where "lagged activity" comes from `ActivityLagFilter` using this model's
/// rise and fall times. Saved on the watch after calibration.
public struct BaselineModel: Codable, Equatable, Sendable {
    /// Heart rate when completely still, in bpm.
    public var restingHeartRateBPM: Double
    /// k: extra bpm per 1 g of activity.
    public var bpmPerG: Double
    /// Heart-rate lag while activity rises and falls, in seconds.
    public var lagRiseSeconds: Double
    public var lagFallSeconds: Double
    /// Typical size of the model's error, in bpm (standard deviation of the
    /// difference between measured and expected heart rate during calibration).
    /// The Kalman filter in Step 5 uses this.
    public var residualSDBPM: Double
    /// 0 to 1: how much of the heart-rate variation the model explains. Nil if not calibrated.
    public var rSquared: Double?
    /// How many 5-second windows the fit used.
    public var windowsUsed: Int
    /// Apple's own resting heart rate at calibration time, for comparison.
    public var appleRestingHeartRateBPM: Double?
    public var calibratedAt: Date?
    /// False when these are rough defaults rather than your own calibration.
    public var isCalibrated: Bool
    /// Your normal tremor while still (median, degrees per second), if
    /// calibration had enough quiet data. Nil means "use the fixed threshold".
    /// (Baselines saved before this was added simply load with nil.)
    public var tremorBaselineDegPerSec: Double?

    public init(restingHeartRateBPM: Double,
                bpmPerG: Double,
                lagRiseSeconds: Double,
                lagFallSeconds: Double,
                residualSDBPM: Double,
                rSquared: Double?,
                windowsUsed: Int,
                appleRestingHeartRateBPM: Double?,
                calibratedAt: Date?,
                isCalibrated: Bool,
                tremorBaselineDegPerSec: Double? = nil) {
        self.restingHeartRateBPM = restingHeartRateBPM
        self.bpmPerG = bpmPerG
        self.lagRiseSeconds = lagRiseSeconds
        self.lagFallSeconds = lagFallSeconds
        self.residualSDBPM = residualSDBPM
        self.rSquared = rSquared
        self.windowsUsed = windowsUsed
        self.appleRestingHeartRateBPM = appleRestingHeartRateBPM
        self.calibratedAt = calibratedAt
        self.isCalibrated = isCalibrated
        self.tremorBaselineDegPerSec = tremorBaselineDegPerSec
    }

    /// Heart rate expected for this much (lagged) activity.
    public func expectedHeartRate(laggedActivityG: Double) -> Double {
        restingHeartRateBPM + bpmPerG * laggedActivityG
    }

    /// Rough defaults used until the user has calibrated.
    public static func uncalibrated(_ config: CalibrationConfig = CalibrationConfig()) -> BaselineModel {
        BaselineModel(restingHeartRateBPM: config.defaultRestingBPM,
                      bpmPerG: config.defaultBPMPerG,
                      lagRiseSeconds: config.defaultLagRiseSeconds,
                      lagFallSeconds: config.defaultLagFallSeconds,
                      residualSDBPM: 8,
                      rSquared: nil,
                      windowsUsed: 0,
                      appleRestingHeartRateBPM: nil,
                      calibratedAt: nil,
                      isCalibrated: false)
    }
}
