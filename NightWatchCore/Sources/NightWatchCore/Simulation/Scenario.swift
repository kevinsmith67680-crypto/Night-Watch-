import Foundation

/// The situations the simulator can play.
public enum ScenarioKind: String, CaseIterable, Codable, Sendable {
    case resting
    case dancing
    case caffeine
    case stimulantToxicity
    case strapArtefacts
}

/// What the traffic light must do for a scenario to pass.
public enum ScenarioExpectation: Equatable, Sendable {
    /// Green the whole time.
    case staysGreen
    /// Amber first, then red later.
    case amberThenRed
}

public struct Scenario: Equatable, Sendable {
    public let kind: ScenarioKind
    public let title: String
    public let summary: String
    public let durationMinutes: Double
    public let expectation: ScenarioExpectation

    public var expectationText: String {
        switch expectation {
        case .staysGreen: return "stays green"
        case .amberThenRed: return "amber, then red"
        }
    }

    public static func make(_ kind: ScenarioKind) -> Scenario {
        switch kind {
        case .resting:
            return Scenario(kind: kind, title: "Resting",
                            summary: "30 min sitting quietly.",
                            durationMinutes: 30, expectation: .staysGreen)
        case .dancing:
            return Scenario(kind: kind, title: "Dancing",
                            summary: "5 min standing, 20 min dancing with breaks, then 15 min sitting while heart rate recovers.",
                            durationMinutes: 40, expectation: .staysGreen)
        case .caffeine:
            return Scenario(kind: kind, title: "Caffeine",
                            summary: "Sitting. Heart rate creeps up 10 bpm over 20 min; mild tremor.",
                            durationMinutes: 40, expectation: .staysGreen)
        case .stimulantToxicity:
            return Scenario(kind: kind, title: "Stimulant toxicity (simulated)",
                            summary: "Sitting still. From minute 5, heart rate climbs 2.5 bpm/min to +50; strong rhythmic tremor builds from minute 8.",
                            durationMinutes: 40, expectation: .amberThenRed)
        case .strapArtefacts:
            return Scenario(kind: kind, title: "Strap glitches",
                            summary: "Resting, with 9 heart-rate spikes of +45 to +70 bpm, 3 arm jolts and a 20-second dropout.",
                            durationMinutes: 30, expectation: .staysGreen)
        }
    }

    public static let all: [Scenario] = ScenarioKind.allCases.map { Scenario.make($0) }
}

/// The pretend person in every scenario.
///
/// Their TRUE heart-rate response is deliberately a little different from the
/// baseline the app is given (higher k, slower recovery), because no real
/// person matches their calibration exactly. The rules must cope with that.
public enum SimulatedPerson {
    public static let restingHeartRateBPM = 62.0
    public static let trueBPMPerG = 100.0
    public static let trueLagRiseSeconds = 30.0
    public static let trueLagFallSeconds = 180.0

    /// The calibration the app works from for this person.
    public static let baseline = BaselineModel(restingHeartRateBPM: 62,
                                               bpmPerG: 90,
                                               lagRiseSeconds: 30,
                                               lagFallSeconds: 120,
                                               residualSDBPM: 3,
                                               rSquared: 0.85,
                                               windowsUsed: 720,
                                               appleRestingHeartRateBPM: 61,
                                               calibratedAt: nil,
                                               isCalibrated: true,
                                               tremorBaselineDegPerSec: 0.6)
}
