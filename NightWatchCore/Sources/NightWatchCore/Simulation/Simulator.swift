import Foundation

/// The outcome of playing one scenario through the pipeline.
public struct SimulationRun: Sendable {
    public let scenario: Scenario
    public let seed: UInt64
    public let startTime: Timestamp
    /// One result per 5-second window, exactly as the real app would produce.
    public let results: [WindowResult]

    /// The highest traffic-light level reached.
    public var highestLevel: RiskLevel {
        results.compactMap { $0.risk?.level }.max() ?? .green
    }

    /// Minutes from the start until the light first reached `level` (or higher).
    public func minutesUntil(_ level: RiskLevel) -> Double? {
        guard let first = results.first(where: { ($0.risk?.level ?? .green) >= level }) else { return nil }
        return (first.features.end - startTime) / 60
    }

    /// How many windows the Kalman filter ignored as spikes.
    public var spikesIgnored: Int {
        results.filter { $0.filtered?.decision == .rejectedAsSpike }.count
    }

    /// Did the light do what the scenario requires?
    public var passed: Bool {
        switch scenario.expectation {
        case .staysGreen:
            return highestLevel == .green
        case .amberThenRed:
            guard let amber = minutesUntil(.amber), let red = minutesUntil(.red) else { return false }
            return amber < red
        }
    }

    /// One line in plain English.
    public var summary: String {
        var parts = ["highest: \(highestLevel.label)"]
        if let amber = minutesUntil(.amber) { parts.append(String(format: "amber at %.1f min", amber)) }
        if let red = minutesUntil(.red) { parts.append(String(format: "red at %.1f min", red)) }
        parts.append("\(spikesIgnored) spikes ignored")
        parts.append(passed ? "PASS" : "FAIL")
        return parts.joined(separator: " · ")
    }
}

/// Plays scenarios through the SAME pipeline the real watch uses: windows,
/// features, baseline, Kalman filter and risk rules.
public enum Simulator {

    /// - seed: changes the random noise; the same seed always gives the same run.
    /// - startTime: timestamp of the first reading (use "now" for realistic CSV times).
    public static func run(_ kind: ScenarioKind,
                           seed: UInt64 = 1,
                           config: MonitorConfig = .standard,
                           startTime: Timestamp = 0) -> SimulationRun {
        let scenario = Scenario.make(kind)
        var generator = ScenarioGenerator(scenario: scenario, seed: seed,
                                          sampleRateHz: config.features.motionSampleRateHz,
                                          startTime: startTime)
        var pipeline = MonitoringPipeline(config: config, baseline: SimulatedPerson.baseline)

        var results: [WindowResult] = []
        while let reading = generator.next() {
            if let result = pipeline.process(reading) {
                results.append(result)
            }
        }
        if let last = pipeline.finish() {
            results.append(last)
        }
        return SimulationRun(scenario: scenario, seed: seed, startTime: startTime, results: results)
    }
}
