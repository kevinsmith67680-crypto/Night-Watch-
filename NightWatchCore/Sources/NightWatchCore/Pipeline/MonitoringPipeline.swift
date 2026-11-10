import Foundation

/// The whole processing chain in one place:
///
///   sensor readings → 5-second windows → features → expected & excess heart rate
///   → (Step 5) Kalman filter → (Step 6) risk
///
/// Real sensors and the simulator both feed readings through exactly this code,
/// so whatever the simulator proves also holds for the real app.
public struct MonitoringPipeline: Sendable {
    public let config: MonitorConfig
    public let baseline: BaselineModel
    private var accumulator: WindowAccumulator
    private let extractor: FeatureExtractor
    private var activityLag: ActivityLagFilter

    /// - Parameter baseline: your calibrated baseline, or nil to use rough defaults.
    public init(config: MonitorConfig = .standard, baseline: BaselineModel? = nil) {
        let model = baseline ?? BaselineModel.uncalibrated(config.calibration)
        self.config = config
        self.baseline = model
        self.accumulator = WindowAccumulator(windowSeconds: config.features.windowSeconds)
        self.extractor = FeatureExtractor(config: config.features)
        self.activityLag = ActivityLagFilter(riseSeconds: model.lagRiseSeconds,
                                             fallSeconds: model.lagFallSeconds)
    }

    /// Feed every reading here, in the order they arrive.
    /// Returns a result each time a window finishes, otherwise nil.
    public mutating func process(_ reading: SensorReading) -> WindowResult? {
        guard let window = accumulator.add(reading) else { return nil }
        return evaluate(window)
    }

    /// Call when monitoring stops, to get the last, partly filled window.
    public mutating func finish() -> WindowResult? {
        guard let window = accumulator.flush() else { return nil }
        return evaluate(window)
    }

    private mutating func evaluate(_ window: SensorWindow) -> WindowResult {
        let features = extractor.features(for: window)

        // Lagged activity. If a window has no motion data, keep the last value.
        let lagged: Double?
        if let motion = features.motion {
            lagged = activityLag.update(activity: motion.activityG, at: features.end)
        } else {
            lagged = activityLag.value
        }

        let expected = lagged.map { baseline.expectedHeartRate(laggedActivityG: $0) }
        var excess: Double?
        if let measured = features.heartRateBPM, let expected {
            excess = measured - expected
        }

        return WindowResult(features: features,
                            laggedActivityG: lagged,
                            expectedHeartRateBPM: expected,
                            excessHeartRateBPM: excess,
                            baselineIsCalibrated: baseline.isCalibrated)
    }
}
