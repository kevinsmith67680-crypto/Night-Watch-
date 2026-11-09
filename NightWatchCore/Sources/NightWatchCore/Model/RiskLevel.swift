import Foundation

/// The traffic-light level shown on the watch.
///
/// For now the level comes from temporary rules (Step 6). Later the IMM
/// filter's "in trouble" probability will set it instead.
public enum RiskLevel: Int, CaseIterable, Codable, Comparable, Sendable {
    case green = 0
    case amber = 1
    case red = 2

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// One-word label, used in the CSV log.
    public var label: String {
        switch self {
        case .green: return "green"
        case .amber: return "amber"
        case .red: return "red"
        }
    }

    /// The message shown on screen for this level.
    public var message: String {
        SafetyText.message(for: self)
    }
}
