import Foundation
import CoreMotion
import NightWatchCore

/// Accelerometer + gyroscope input, about 50 readings a second.
///
/// Uses CoreMotion's "device motion", which combines both sensors to split the
/// watch's acceleration into:
///   • gravity: which way is down (used for arm orientation);
///   • user acceleration: your own movement (used for activity and tremor);
/// plus the rotation rate from the gyroscope (used for tremor).
///
/// It keeps running with the screen off only while monitoring mode's workout
/// session is active. Readings arrive on the main thread.
final class MotionSource: SensorSource {

    let name = "Apple Watch motion (accelerometer + gyroscope)"
    let provides: Set<SensorKind> = [.motion]
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    private let manager = CMMotionManager()
    private let sampleRateHz: Double
    private var isRunning = false

    init(sampleRateHz: Double) {
        self.sampleRateHz = sampleRateHz
    }

    func start(deliver: @escaping (SensorReading) -> Void) throws {
        guard isAvailable else {
            throw SensorError.unavailable("Motion sensors aren't available here. The watch simulator has none.")
        }
        guard !isRunning else { return }
        isRunning = true

        // CoreMotion counts time in seconds since the watch started up.
        // Convert to the same clock as heart rate (seconds since 1970).
        let clockOffset = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime

        manager.deviceMotionUpdateInterval = 1.0 / sampleRateHz
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else { return }
            let sample = MotionSample(
                time: motion.timestamp + clockOffset,
                userAcceleration: Vector3(x: motion.userAcceleration.x,
                                          y: motion.userAcceleration.y,
                                          z: motion.userAcceleration.z),
                gravity: Vector3(x: motion.gravity.x,
                                 y: motion.gravity.y,
                                 z: motion.gravity.z),
                rotationRate: Vector3(x: motion.rotationRate.x,
                                      y: motion.rotationRate.y,
                                      z: motion.rotationRate.z))
            deliver(.motion(sample))
        }
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }
}
