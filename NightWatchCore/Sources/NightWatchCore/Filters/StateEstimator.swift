import Foundation

/// What happened to a window's measurement inside the filter.
public enum MeasurementDecision: String, Codable, Sendable {
    /// Used normally.
    case accepted
    /// Too far from what was expected, so ignored as a one-off spike.
    case rejectedAsSpike
    /// No heart rate in this window; the filter only moved forward in time.
    case missing
    /// The filter started afresh: first reading, after a long gap, or after
    /// several "spikes" in a row (which means a real change).
    case restarted
}

/// The smoothed view of excess heart rate after filtering.
public struct ExcessHeartRateEstimate: Equatable, Codable, Sendable {
    public var time: Timestamp
    /// Smoothed excess heart rate, in bpm.
    public var excessBPM: Double
    /// How fast it is changing, in bpm per minute. Positive = climbing.
    public var trendBPMPerMinute: Double
    /// Uncertainty (1 standard deviation) of each.
    public var excessSDBPM: Double
    public var trendSDBPMPerMinute: Double
    public var decision: MeasurementDecision

    public init(time: Timestamp, excessBPM: Double, trendBPMPerMinute: Double,
                excessSDBPM: Double, trendSDBPMPerMinute: Double, decision: MeasurementDecision) {
        self.time = time
        self.excessBPM = excessBPM
        self.trendBPMPerMinute = trendBPMPerMinute
        self.excessSDBPM = excessSDBPM
        self.trendSDBPMPerMinute = trendSDBPMPerMinute
        self.decision = decision
    }
}

/// Anything that turns noisy excess-heart-rate measurements into a smoothed estimate.
///
/// `ExcessHeartRateFilter` (a Kalman filter) is the first. The IMM filter
/// ("chilling / dancing / in trouble") will be another, and can replace it in
/// the pipeline without changing anything else.
public protocol StateEstimator: Sendable {
    /// - measurement: measured minus expected heart rate for this window, or nil if there was none.
    /// - activityG: current activity, used to judge how trustworthy the measurement is.
    /// Returns nil until the first measurement has arrived.
    mutating func update(measurement: Double?, activityG: Double?, at time: Timestamp) -> ExcessHeartRateEstimate?

    /// Forget everything and wait for a new first measurement.
    mutating func reset()
}
