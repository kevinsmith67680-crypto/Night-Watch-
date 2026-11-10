import Foundation

/// The risk engine's verdict for one window.
public struct RiskAssessment: Equatable, Codable, Sendable {
    public var time: Timestamp
    /// The traffic-light level to show (after step-down delay).
    public var level: RiskLevel
    /// Plain-English reasons, e.g. "Excess heart rate +23 bpm, rising…".
    public var reasons: [String]
    /// How long the wearer has been still, in minutes (brief movements allowed).
    public var stillMinutes: Double
    /// Median heart rate over the last minute, or nil if none arrived.
    public var recentHeartRateBPM: Double?
    public var tremorRaised: Bool
    /// Which engine produced this, e.g. "Temporary rules" (later "IMM").
    public var engineName: String

    public var hasRecentHeartRate: Bool {
        recentHeartRateBPM != nil
    }

    public init(time: Timestamp, level: RiskLevel, reasons: [String], stillMinutes: Double,
                recentHeartRateBPM: Double?, tremorRaised: Bool, engineName: String) {
        self.time = time
        self.level = level
        self.reasons = reasons
        self.stillMinutes = stillMinutes
        self.recentHeartRateBPM = recentHeartRateBPM
        self.tremorRaised = tremorRaised
        self.engineName = engineName
    }
}
