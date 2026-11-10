import Foundation

/// Turns one window of raw readings into a handful of meaningful numbers.
public struct FeatureExtractor: Sendable {
    public let config: FeatureConfig

    /// Fewer motion samples than this and we don't attempt any analysis.
    static let minimumSamplesToAnalyse = 16

    public init(config: FeatureConfig = FeatureConfig()) {
        self.config = config
    }

    public func features(for window: SensorWindow) -> WindowFeatures {
        let bpms = window.heartRates.map { $0.bpm }
        let temperatures = window.wristTemperatures.map { $0.deviationCelsius }
        return WindowFeatures(
            start: window.start,
            end: window.end,
            heartRateBPM: Statistics.median(bpms),
            heartRateSampleCount: bpms.count,
            motion: motionFeatures(for: window.motion),
            wristTemperatureDeviation: Statistics.mean(temperatures)
        )
    }

    /// Activity, tremor and arm orientation from one window of motion samples.
    /// Returns nil if there are too few samples to analyse.
    public func motionFeatures(for unsortedSamples: [MotionSample]) -> MotionFeatures? {
        let samples = unsortedSamples.sorted { $0.time < $1.time }
        guard samples.count >= Self.minimumSamplesToAnalyse,
              let first = samples.first, let last = samples.last,
              last.time > first.time
        else { return nil }

        // Sample rate actually achieved.
        let sampleRate = Double(samples.count - 1) / (last.time - first.time)
        let expectedSamples = config.windowSeconds * config.motionSampleRateHz
        let qualityOK = Double(samples.count) >= config.minimumSampleFraction * expectedSamples

        // Spectra of gravity-removed acceleration (in g) and rotation rate (in rad/s),
        // only up to the highest frequency any feature uses.
        let highestNeeded = max(config.activityBandHighHz, config.tremorBandHighHz)
        let acceleration = Spectrum(axes: [samples.map { $0.userAcceleration.x },
                                           samples.map { $0.userAcceleration.y },
                                           samples.map { $0.userAcceleration.z }],
                                    sampleRateHz: sampleRate,
                                    maxFrequencyHz: highestNeeded)
        let rotation = Spectrum(axes: [samples.map { $0.rotationRate.x },
                                       samples.map { $0.rotationRate.y },
                                       samples.map { $0.rotationRate.z }],
                                sampleRateHz: sampleRate,
                                maxFrequencyHz: highestNeeded)

        // a) Activity: movement in the low-frequency band.
        let activity = acceleration.bandPower(from: config.activityBandLowHz,
                                              to: config.activityBandHighHz).squareRoot()
        let isStill = activity < config.stillnessThresholdG

        // b) Tremor: small shaking in the 4–12 Hz band.
        let low = config.tremorBandLowHz
        let high = config.tremorBandHighHz
        let tremorAccel = acceleration.bandPower(from: low, to: high).squareRoot()
        let gyroBandPower = rotation.bandPower(from: low, to: high)
        let tremorGyro = gyroBandPower.squareRoot()

        // How rhythmic: share of the band's power that sits near its strongest frequency.
        let peak = rotation.peakFrequency(from: low, to: high) ?? 0
        var rhythmicity = 0.0
        if gyroBandPower > 0 {
            let peakPower = rotation.bandPower(from: max(low, peak - config.rhythmicityHalfWidthHz),
                                               to: min(high, peak + config.rhythmicityHalfWidthHz))
            rhythmicity = min(1, peakPower / gyroBandPower)
        }

        // c) Arm orientation from the average direction of gravity.
        let (elevation, orientation) = armOrientation(for: samples)

        return MotionFeatures(
            sampleCount: samples.count,
            sampleRateHz: sampleRate,
            qualityOK: qualityOK,
            activityG: activity,
            isStill: isStill,
            tremorAccelMilliG: tremorAccel * 1000,
            tremorGyroDegPerSec: tremorGyro * 180 / Double.pi,
            tremorPeakHz: peak,
            tremorRhythmicity: rhythmicity,
            tremorReliable: isStill && qualityOK,
            forearmElevationDegrees: elevation,
            armOrientation: orientation
        )
    }

    /// On Apple Watch the forearm runs along the watch's x-axis (the crown side),
    /// so the share of gravity along x tells us how steeply the forearm points.
    private func armOrientation(for samples: [MotionSample]) -> (Double, ArmOrientation) {
        let count = Double(samples.count)
        let averageGravity = Vector3(x: samples.reduce(0.0) { $0 + $1.gravity.x } / count,
                                     y: samples.reduce(0.0) { $0 + $1.gravity.y } / count,
                                     z: samples.reduce(0.0) { $0 + $1.gravity.z } / count)
        let strength = averageGravity.magnitude
        // Gravity is about 1 g. A much smaller average means the watch kept turning.
        guard strength > 0.5 else { return (0, .unknown) }

        let elevation = asin(min(1, abs(averageGravity.x) / strength)) * 180 / Double.pi
        let orientation: ArmOrientation
        if elevation >= config.forearmVerticalFromDegrees {
            orientation = .forearmVertical
        } else if elevation <= config.forearmHorizontalUpToDegrees {
            orientation = .forearmHorizontal
        } else {
            orientation = .inBetween
        }
        return (elevation, orientation)
    }
}

/// Small statistics helpers.
enum Statistics {
    /// The middle value. Unlike the average, one wild value barely moves it.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }
}
