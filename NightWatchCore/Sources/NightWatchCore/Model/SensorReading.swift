import Foundation

/// Time in seconds.
///
/// On the watch this is seconds since 1 January 1970 (`Date().timeIntervalSince1970`).
/// In the simulator it is "seconds since the scenario started". The pipeline only
/// ever looks at differences between timestamps, so both work the same way.
public typealias Timestamp = Double

/// One heart-rate reading, in beats per minute.
public struct HeartRateSample: Equatable, Codable, Sendable {
    public let time: Timestamp
    public let bpm: Double

    public init(time: Timestamp, bpm: Double) {
        self.time = time
        self.bpm = bpm
    }
}

/// One motion reading from the accelerometer + gyroscope (about 50 per second).
public struct MotionSample: Equatable, Codable, Sendable {
    public let time: Timestamp
    /// Acceleration caused by the user's movement, with gravity removed. Units: g (1 g = 9.81 m/s²).
    public let userAcceleration: Vector3
    /// Direction of gravity relative to the watch. Units: g. Length is about 1 when the watch is not moving.
    public let gravity: Vector3
    /// How fast the watch is rotating around each axis. Units: radians per second.
    public let rotationRate: Vector3

    public init(time: Timestamp, userAcceleration: Vector3, gravity: Vector3, rotationRate: Vector3) {
        self.time = time
        self.userAcceleration = userAcceleration
        self.gravity = gravity
        self.rotationRate = rotationRate
    }
}

/// Change in wrist skin temperature from the user's normal, in °C.
/// Not available live on Apple Watch today; see `DisabledWristTemperatureSource`.
public struct WristTemperatureSample: Equatable, Codable, Sendable {
    public let time: Timestamp
    public let deviationCelsius: Double

    public init(time: Timestamp, deviationCelsius: Double) {
        self.time = time
        self.deviationCelsius = deviationCelsius
    }
}

/// Every kind of input the pipeline understands.
///
/// All sensors, real or simulated, produce values of this one type. To add a new
/// sensor later, add a case here and a matching `SensorSource`.
public enum SensorReading: Equatable, Sendable {
    case heartRate(HeartRateSample)
    case motion(MotionSample)
    case wristTemperature(WristTemperatureSample)

    public var time: Timestamp {
        switch self {
        case .heartRate(let sample): return sample.time
        case .motion(let sample): return sample.time
        case .wristTemperature(let sample): return sample.time
        }
    }

    public var kind: SensorKind {
        switch self {
        case .heartRate: return .heartRate
        case .motion: return .motion
        case .wristTemperature: return .wristTemperature
        }
    }
}
