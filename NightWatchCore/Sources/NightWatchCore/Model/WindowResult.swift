import Foundation

/// Everything the pipeline worked out for one 5-second window.
/// Step 5 adds the Kalman-filtered values and Step 6 the risk level.
public struct WindowResult: Equatable, Codable, Sendable {
    public var features: WindowFeatures
    /// Activity after the heart-rate lag filter, in g.
    public var laggedActivityG: Double?
    /// Heart rate expected for this much recent activity, from the baseline.
    public var expectedHeartRateBPM: Double?
    /// Measured minus expected heart rate (not yet smoothed). Nil if either is missing.
    public var excessHeartRateBPM: Double?
    /// False while the baseline is still the rough default.
    public var baselineIsCalibrated: Bool

    public init(features: WindowFeatures,
                laggedActivityG: Double?,
                expectedHeartRateBPM: Double?,
                excessHeartRateBPM: Double?,
                baselineIsCalibrated: Bool) {
        self.features = features
        self.laggedActivityG = laggedActivityG
        self.expectedHeartRateBPM = expectedHeartRateBPM
        self.excessHeartRateBPM = excessHeartRateBPM
        self.baselineIsCalibrated = baselineIsCalibrated
    }
}
