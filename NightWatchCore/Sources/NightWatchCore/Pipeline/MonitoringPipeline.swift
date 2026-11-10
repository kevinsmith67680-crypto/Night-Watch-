import Foundation

/// The whole processing chain in one place:
///
///   sensor readings → 5-second windows → features → (Step 5) Kalman filter → (Step 6) risk
///
/// Real sensors and the simulator both feed readings through exactly this code,
/// so whatever the simulator proves also holds for the real app.
public struct MonitoringPipeline: Sendable {
    public let config: MonitorConfig
    private var accumulator: WindowAccumulator
    private let extractor: FeatureExtractor

    public init(config: MonitorConfig = .standard) {
        self.config = config
        self.accumulator = WindowAccumulator(windowSeconds: config.features.windowSeconds)
        self.extractor = FeatureExtractor(config: config.features)
    }

    /// Feed every reading here, in the order they arrive.
    /// Returns a window's features each time a window finishes, otherwise nil.
    public mutating func process(_ reading: SensorReading) -> WindowFeatures? {
        guard let window = accumulator.add(reading) else { return nil }
        return extractor.features(for: window)
    }

    /// Call when monitoring stops, to get the last, partly filled window.
    public mutating func finish() -> WindowFeatures? {
        guard let window = accumulator.flush() else { return nil }
        return extractor.features(for: window)
    }
}
