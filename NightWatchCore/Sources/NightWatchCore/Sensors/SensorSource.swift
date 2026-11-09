import Foundation

/// The kinds of data a sensor can provide.
public enum SensorKind: String, CaseIterable, Codable, Sendable {
    case heartRate
    case motion
    case wristTemperature
}

/// Errors a sensor can report when it is asked to start.
public enum SensorError: Error, Equatable, CustomStringConvertible {
    /// The hardware or Apple's APIs don't offer this input.
    case unavailable(String)
    /// The user has not given permission (e.g. Health access was turned off).
    case permissionDenied(String)

    public var description: String {
        switch self {
        case .unavailable(let reason): return "Sensor unavailable: \(reason)"
        case .permissionDenied(let reason): return "Permission needed: \(reason)"
        }
    }
}

/// The common shape every input must have: real heart rate, real motion,
/// the simulator, and future inputs such as wrist temperature.
///
/// Because the rest of the app only talks to this protocol, a new input can be
/// added later without changing the feature extraction, filters or UI.
public protocol SensorSource: AnyObject {
    /// Short human-readable name, e.g. "Apple Watch heart rate".
    var name: String { get }

    /// Which kinds of reading this source produces.
    var provides: Set<SensorKind> { get }

    /// `false` if the hardware or Apple's APIs don't allow this input right now.
    var isAvailable: Bool { get }

    /// Start producing readings. Every new reading is passed to `deliver`.
    /// Throws a `SensorError` if the source can't start.
    func start(deliver: @escaping (SensorReading) -> Void) throws

    /// Stop producing readings. Safe to call more than once.
    func stop()
}
