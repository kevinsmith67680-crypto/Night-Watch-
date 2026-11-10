import Foundation

/// The whole processing chain in one place:
///
///   sensor readings → 5-second windows → features → expected & excess heart rate
///   → Kalman filter → risk engine (traffic light)
///
/// Real sensors and the simulator both feed readings through exactly this code,
/// so whatever the simulator proves also holds for the real app.
public struct MonitoringPipeline: Sendable {
    public let config: MonitorConfig
    public let baseline: BaselineModel
    private var accumulator: WindowAccumulator
    private let extractor: FeatureExtractor
    private var activityLag: ActivityLagFilter
    private var estimator: any StateEstimator
    private var riskEngine: any RiskEngine

    /// - baseline: your calibrated baseline, or nil to use rough defaults.
    /// - estimator: the filter for excess heart rate. Nil uses the Kalman filter;
    ///   the IMM filter can be passed in here later.
    /// - riskEngine: nil uses the temporary rules.
    public init(config: MonitorConfig = .standard,
                baseline: BaselineModel? = nil,
                estimator: (any StateEstimator)? = nil,
                riskEngine: (any RiskEngine)? = nil) {
        let model = baseline ?? BaselineModel.uncalibrated(config.calibration)
        self.config = config
        self.baseline = model
        self.accumulator = WindowAccumulator(windowSeconds: config.features.windowSeconds)
        self.extractor = FeatureExtractor(config: config.features)
        self.activityLag = ActivityLagFilter(riseSeconds: model.lagRiseSeconds,
                                             fallSeconds: model.lagFallSeconds)
        self.estimator = estimator ?? ExcessHeartRateFilter(config: config.kalman, baseline: model)
        self.riskEngine = riskEngine ?? PlaceholderRiskRules(config: config.risk,
                                                             windowSeconds: config.features.windowSeconds)
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

        // Smooth the excess and track its trend.
        let filtered = estimator.update(measurement: excess,
                                        activityG: features.motion?.activityG,
                                        at: features.end)

        var result = WindowResult(features: features,
                                  laggedActivityG: lagged,
                                  expectedHeartRateBPM: expected,
                                  excessHeartRateBPM: excess,
                                  baselineIsCalibrated: baseline.isCalibrated,
                                  filtered: filtered)

        // Traffic light.
        result.risk = riskEngine.assess(result)
        return result
    }
}
