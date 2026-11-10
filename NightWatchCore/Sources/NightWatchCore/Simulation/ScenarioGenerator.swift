import Foundation

/// Produces fake sensor readings for a scenario, in time order, exactly like
/// the real sensors would: motion 50 times a second, heart rate every 2 seconds.
///
/// It works as an iterator (call `next()` until it returns nil), so a
/// 40-minute scenario never has to sit in memory all at once.
///
/// How the fake signals are made:
///  • movement: a sine wave at the dance or sway frequency, sized so its RMS
///    equals the intended activity, plus a little sensor noise;
///  • tremor: random jitter on the gyroscope (normal physiological tremor,
///    about 0.6 °/s), plus a rhythmic 9.4 Hz wave when the scenario adds tremor;
///  • heart rate: resting + k × lagged activity + excess + noise, using the
///    pretend person's TRUE response (see `SimulatedPerson`).
public struct ScenarioGenerator: IteratorProtocol, Sendable {
    public let scenario: Scenario
    public let startTime: Timestamp
    public let sampleRateHz: Double
    public let heartRateIntervalSeconds = 2.0

    private var random: SeededRandom
    private var trueLag = ActivityLagFilter(riseSeconds: SimulatedPerson.trueLagRiseSeconds,
                                            fallSeconds: SimulatedPerson.trueLagFallSeconds)
    private var sampleIndex = 0
    private var nextHeartRateTime = 1.0   // seconds since the start
    private let durationSeconds: Double

    // Strap-glitch scenario: when things go wrong (minutes since start).
    private static let spikes: [(minute: Double, readings: Int, bpm: Double)] = [
        (3, 1, 60), (6.5, 2, 45), (9, 3, 70), (12.2, 1, 60), (15, 2, 45),
        (18.7, 3, 70), (21, 1, 60), (24.4, 2, 45), (27, 3, 70),
    ]
    private static let joltMinutes: [Double] = [7, 16, 23]
    private static let joltSeconds = 2.0
    private static let dropoutMinute = 11.0
    private static let dropoutSeconds = 20.0

    private static let sittingGravity = Vector3(x: 0.2, y: 0, z: -0.98).normalised
    private static let standingGravity = Vector3(x: 0.97, y: 0, z: -0.24).normalised
    private static let tremorHz = 9.4

    public init(scenario: Scenario, seed: UInt64 = 1, sampleRateHz: Double = 50, startTime: Timestamp = 0) {
        self.scenario = scenario
        self.startTime = startTime
        self.sampleRateHz = sampleRateHz
        self.random = SeededRandom(seed: seed)
        self.durationSeconds = scenario.durationMinutes * 60
    }

    public mutating func next() -> SensorReading? {
        while true {
            let motionTime = Double(sampleIndex) / sampleRateHz
            if nextHeartRateTime <= motionTime && nextHeartRateTime < durationSeconds {
                let time = nextHeartRateTime
                nextHeartRateTime += heartRateIntervalSeconds
                if let reading = heartRateReading(at: time) { return reading }
                continue   // dropout: this reading never arrives
            }
            guard motionTime < durationSeconds else { return nil }
            sampleIndex += 1
            return motionReading(at: motionTime)
        }
    }

    // MARK: - The "truth" at each moment

    private struct Truth {
        var activityG = 0.0          // intended RMS movement
        var movementHz = 1.0
        var gravity = ScenarioGenerator.sittingGravity
        var excessBPM = 0.0          // heart rate not explained by movement
        var tremorDegPerSec = 0.0    // extra rhythmic tremor
    }

    private func profile(at seconds: Double) -> Truth {
        let minute = seconds / 60
        var truth = Truth()
        switch scenario.kind {
        case .resting, .strapArtefacts:
            break

        case .dancing:
            if minute < 5 {
                truth.gravity = Self.standingGravity
            } else if minute < 25 {
                truth.gravity = Self.standingGravity
                if (minute - 5).truncatingRemainder(dividingBy: 4) < 3 {
                    truth.activityG = 0.5     // dancing
                    truth.movementHz = 2.1
                } else {
                    truth.activityG = 0.15    // swaying during a break
                    truth.movementHz = 0.8
                }
            }   // from minute 25: sitting down, recovering

        case .caffeine:
            let progress = Self.clamp01((minute - 5) / 20)
            truth.excessBPM = 10 * progress
            truth.tremorDegPerSec = 1.2 * progress

        case .stimulantToxicity:
            if minute >= 25 {
                truth.excessBPM = 50 + 0.25 * (minute - 25)
            } else if minute >= 5 {
                truth.excessBPM = 2.5 * (minute - 5)
            }
            truth.tremorDegPerSec = 3.0 * Self.clamp01((minute - 8) / 12)
        }
        return truth
    }

    // MARK: - Readings

    private mutating func heartRateReading(at seconds: Double) -> SensorReading? {
        let truth = profile(at: seconds)
        let lagged = trueLag.update(activity: truth.activityG, at: seconds)
        var bpm = SimulatedPerson.restingHeartRateBPM
            + SimulatedPerson.trueBPMPerG * lagged
            + truth.excessBPM
            + random.gaussian(standardDeviation: 2 + 6 * truth.activityG)   // noisier while moving

        if scenario.kind == .strapArtefacts {
            for spike in Self.spikes {
                let start = spike.minute * 60
                if seconds >= start && seconds < start + Double(spike.readings) * heartRateIntervalSeconds {
                    bpm += spike.bpm
                }
            }
            let dropoutStart = Self.dropoutMinute * 60
            if seconds >= dropoutStart && seconds < dropoutStart + Self.dropoutSeconds {
                return nil
            }
        }
        return .heartRate(HeartRateSample(time: startTime + seconds, bpm: bpm))
    }

    private mutating func motionReading(at seconds: Double) -> SensorReading {
        let truth = profile(at: seconds)
        let twoPi = 2 * Double.pi
        let rmsToAmplitude = 2.0.squareRoot()

        var jolt = 0.0
        if scenario.kind == .strapArtefacts,
           Self.joltMinutes.contains(where: { seconds >= $0 * 60 && seconds < $0 * 60 + Self.joltSeconds }) {
            jolt = 0.8 * sin(twoPi * 3 * seconds)
        }

        let movement = rmsToAmplitude * truth.activityG * sin(twoPi * truth.movementHz * seconds)
        let tremorWave = sin(twoPi * Self.tremorHz * seconds)
        let tremorRadPerSec = truth.tremorDegPerSec * Double.pi / 180

        let acceleration = Vector3(
            x: movement + jolt + random.gaussian(standardDeviation: 0.003),
            y: rmsToAmplitude * 0.0035 * truth.tremorDegPerSec * tremorWave + random.gaussian(standardDeviation: 0.003),
            z: random.gaussian(standardDeviation: 0.003))
        let rotation = Vector3(
            x: rmsToAmplitude * tremorRadPerSec * tremorWave + random.gaussian(standardDeviation: 0.0105),
            y: random.gaussian(standardDeviation: 0.0105),
            z: random.gaussian(standardDeviation: 0.0105))

        return .motion(MotionSample(time: startTime + seconds,
                                    userAcceleration: acceleration,
                                    gravity: truth.gravity,
                                    rotationRate: rotation))
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

extension Vector3 {
    /// The same direction with length 1.
    var normalised: Vector3 {
        let length = magnitude
        guard length > 0 else { return self }
        return Vector3(x: x / length, y: y / length, z: z / length)
    }
}
