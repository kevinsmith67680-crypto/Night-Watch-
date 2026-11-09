import Foundation

/// Placeholder for live wrist temperature. Always unavailable.
///
/// Apple Watch Series 8 and later contain a temperature sensor, but Apple only
/// gives apps one "sleeping wrist temperature" value per night, after the user
/// wakes up. There is no live reading.
///
/// This source exists so the rest of the app is already wired for it: if Apple
/// ever offers live wrist temperature, only this file needs replacing.
///
/// Science note: falling wrist temperature can hint at vasoconstriction, but a
/// hot room warms the skin, and stimulants raise core temperature. If this input
/// ever becomes available it should carry low weight in the risk score.
public final class DisabledWristTemperatureSource: SensorSource {
    public let name = "Wrist temperature (not available on Apple Watch)"
    public let provides: Set<SensorKind> = [.wristTemperature]
    public let isAvailable = false

    public init() {}

    public func start(deliver: @escaping (SensorReading) -> Void) throws {
        throw SensorError.unavailable("Apple does not provide live wrist temperature to apps.")
    }

    public func stop() {}
}
