import Foundation

/// Everything the pipeline worked out for one 5-second window.
/// Step 6 adds the risk level.
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
    /// Excess heart rate and its trend after the Kalman filter. Nil until the
    /// first measurement has arrived.
    public var filtered: ExcessHeartRateEstimate?

    public init(features: WindowFeatures,
                laggedActivityG: Double?,
                expectedHeartRateBPM: Double?,
                excessHeartRateBPM: Double?,
                baselineIsCalibrated: Bool,
                filtered: ExcessHeartRateEstimate? = nil) {
        self.features = features
        self.laggedActivityG = laggedActivityG
        self.expectedHeartRateBPM = expectedHeartRateBPM
        self.excessHeartRateBPM = excessHeartRateBPM
        self.baselineIsCalibrated = baselineIsCalibrated
        self.filtered = filtered
    }
}
