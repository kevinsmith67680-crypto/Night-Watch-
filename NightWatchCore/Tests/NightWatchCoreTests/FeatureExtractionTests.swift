import XCTest
@testable import NightWatchCore

// MARK: - Helpers for making fake sensor data

/// Builds `seconds` of motion samples at `rate` Hz. Each closure receives the
/// time in seconds and returns that signal's value.
private func makeMotion(seconds: Double,
                        rate: Double = 50,
                        start: Double = 0,
                        accel: (Double) -> Vector3 = { _ in .zero },
                        gravity: (Double) -> Vector3 = { _ in Vector3(x: 0, y: 0, z: -1) },
                        gyro: (Double) -> Vector3 = { _ in .zero }) -> [MotionSample] {
    let count = Int((seconds * rate).rounded())
    return (0..<count).map { i in
        let t = start + Double(i) / rate
        return MotionSample(time: t, userAcceleration: accel(t), gravity: gravity(t), rotationRate: gyro(t))
    }
}

/// A sine wave of the given amplitude and frequency, at time t.
private func sine(_ amplitude: Double, _ hz: Double, _ t: Double) -> Double {
    amplitude * sin(2 * Double.pi * hz * t)
}

// MARK: - Spectrum

final class SpectrumTests: XCTestCase {

    func testSineWaveHasPowerAmplitudeSquaredOverTwo() {
        let signal = (0..<250).map { sine(2.0, 10, Double($0) / 50) }
        let spectrum = Spectrum(axes: [signal], sampleRateHz: 50)

        XCTAssertEqual(spectrum.bandPower(from: 4, to: 12), 2.0, accuracy: 0.02)   // 2²/2
        XCTAssertLessThan(spectrum.bandPower(from: 0, to: 4), 0.001)
        XCTAssertEqual(spectrum.peakFrequency(from: 4, to: 12) ?? 0, 10, accuracy: 0.01)
    }

    func testFrequencyBetweenBinsIsStillMeasuredAccurately() {
        let signal = (0..<250).map { sine(1.0, 9.1, Double($0) / 50) }
        let spectrum = Spectrum(axes: [signal], sampleRateHz: 50)

        XCTAssertEqual(spectrum.bandPower(from: 4, to: 12), 0.5, accuracy: 0.025)  // within 5%
        XCTAssertEqual(spectrum.peakFrequency(from: 4, to: 12) ?? 0, 9.1, accuracy: 0.15)
    }

    func testConstantOffsetIsIgnored() {
        let spectrum = Spectrum(axes: [[Double](repeating: 3.0, count: 250)], sampleRateHz: 50)
        XCTAssertEqual(spectrum.bandPower(from: 0, to: 25), 0, accuracy: 1e-12)
    }
}

// MARK: - Motion features

final class MotionFeatureTests: XCTestCase {

    let extractor = FeatureExtractor()

    func testSampleRateIsMeasured() throws {
        let features = try XCTUnwrap(extractor.motionFeatures(for: makeMotion(seconds: 5)))
        XCTAssertEqual(features.sampleRateHz, 50, accuracy: 0.01)
        XCTAssertEqual(features.sampleCount, 250)
        XCTAssertTrue(features.qualityOK)
    }

    func testWalkingPaceMovementCountsAsActivityNotTremor() throws {
        // 2 Hz swing, 0.3 g: like arm swing while walking.
        let samples = makeMotion(seconds: 5, accel: { Vector3(x: sine(0.3, 2, $0), y: 0, z: 0) })
        let features = try XCTUnwrap(extractor.motionFeatures(for: samples))

        XCTAssertEqual(features.activityG, 0.3 / 2.0.squareRoot(), accuracy: 0.01)
        XCTAssertLessThan(features.tremorAccelMilliG, 1)
        XCTAssertFalse(features.isStill)
    }

    func testTremorIsSeparatedFromDancing() throws {
        // Big 1.6 Hz dance movement plus a small 9 Hz tremor riding on top.
        let samples = makeMotion(
            seconds: 5,
            accel: { Vector3(x: sine(0.4, 1.6, $0), y: sine(0.01, 9, $0), z: 0) },
            gyro: { Vector3(x: sine(1.0, 1.6, $0), y: sine(0.05, 9, $0), z: 0) })
        let features = try XCTUnwrap(extractor.motionFeatures(for: samples))

        XCTAssertEqual(features.activityG, 0.4 / 2.0.squareRoot(), accuracy: 0.015)
        XCTAssertEqual(features.tremorAccelMilliG, 10 / 2.0.squareRoot(), accuracy: 0.7)
        XCTAssertEqual(features.tremorPeakHz, 9, accuracy: 0.25)
        // Moving a lot, so the tremor reading must NOT be trusted.
        XCTAssertFalse(features.isStill)
        XCTAssertFalse(features.tremorReliable)
    }

    func testRhythmicTremorWhileStillIsDetected() throws {
        // Separate generators, because Swift won't let two closures change one variable.
        var accelNoise = SeededRandom(seed: 42)
        var gyroNoise = SeededRandom(seed: 43)
        let samples = makeMotion(
            seconds: 5,
            accel: { _ in Vector3(x: accelNoise.gaussian(standardDeviation: 0.002),
                                  y: accelNoise.gaussian(standardDeviation: 0.002),
                                  z: accelNoise.gaussian(standardDeviation: 0.002)) },
            gyro: { t in Vector3(x: sine(0.04, 9.4, t) + gyroNoise.gaussian(standardDeviation: 0.005),
                                 y: gyroNoise.gaussian(standardDeviation: 0.005),
                                 z: gyroNoise.gaussian(standardDeviation: 0.005)) })
        let features = try XCTUnwrap(extractor.motionFeatures(for: samples))

        XCTAssertTrue(features.isStill)
        XCTAssertTrue(features.tremorReliable)
        XCTAssertEqual(features.tremorPeakHz, 9.4, accuracy: 0.25)
        XCTAssertGreaterThan(features.tremorRhythmicity, 0.7)
        // 0.04 rad/s amplitude → RMS 0.0283 rad/s ≈ 1.62 °/s
        XCTAssertEqual(features.tremorGyroDegPerSec, 1.62, accuracy: 0.25)
    }

    func testRandomJitterIsNotRhythmic() throws {
        var random = SeededRandom(seed: 7)
        let samples = makeMotion(
            seconds: 5,
            gyro: { _ in Vector3(x: random.gaussian(standardDeviation: 0.02),
                                 y: random.gaussian(standardDeviation: 0.02),
                                 z: random.gaussian(standardDeviation: 0.02)) })
        let features = try XCTUnwrap(extractor.motionFeatures(for: samples))

        XCTAssertLessThan(features.tremorRhythmicity, 0.4)
    }

    func testArmOrientationFromGravity() throws {
        let hanging = try XCTUnwrap(extractor.motionFeatures(
            for: makeMotion(seconds: 5, gravity: { _ in Vector3(x: 1, y: 0, z: 0) })))
        XCTAssertEqual(hanging.armOrientation, .forearmVertical)
        XCTAssertEqual(hanging.forearmElevationDegrees, 90, accuracy: 0.5)

        let flat = try XCTUnwrap(extractor.motionFeatures(
            for: makeMotion(seconds: 5, gravity: { _ in Vector3(x: 0, y: 0, z: -1) })))
        XCTAssertEqual(flat.armOrientation, .forearmHorizontal)
        XCTAssertEqual(flat.forearmElevationDegrees, 0, accuracy: 0.5)

        let tilted = try XCTUnwrap(extractor.motionFeatures(
            for: makeMotion(seconds: 5, gravity: { _ in Vector3(x: 0.7071, y: 0, z: 0.7071) })))
        XCTAssertEqual(tilted.armOrientation, .inBetween)
        XCTAssertEqual(tilted.forearmElevationDegrees, 45, accuracy: 0.5)
    }

    func testMissingSamplesAreFlagged() throws {
        // Only 2 seconds of data in a 5-second window.
        let partial = try XCTUnwrap(extractor.motionFeatures(for: makeMotion(seconds: 2)))
        XCTAssertFalse(partial.qualityOK)
        XCTAssertFalse(partial.tremorReliable)

        // Far too few samples: no analysis at all.
        XCTAssertNil(extractor.motionFeatures(for: makeMotion(seconds: 0.2)))
    }

    func testMedianHeartRateIgnoresOneWildReading() {
        var window = SensorWindow(start: 0, end: 5)
        window.add(.heartRate(HeartRateSample(time: 1, bpm: 70)))
        window.add(.heartRate(HeartRateSample(time: 2, bpm: 72)))
        window.add(.heartRate(HeartRateSample(time: 3, bpm: 200)))   // strap slip
        let features = extractor.features(for: window)

        XCTAssertEqual(features.heartRateBPM, 72)
        XCTAssertEqual(features.heartRateSampleCount, 3)
        XCTAssertNil(features.motion)
    }
}

// MARK: - Windows

final class WindowAccumulatorTests: XCTestCase {

    func testReadingsAreSplitIntoFiveSecondWindows() {
        var accumulator = WindowAccumulator(windowSeconds: 5)
        var finished: [SensorWindow] = []
        for sample in makeMotion(seconds: 12, start: 100) {
            if let window = accumulator.add(.motion(sample)) { finished.append(window) }
        }

        XCTAssertEqual(finished.count, 2)
        XCTAssertEqual(finished[0].start, 100)
        XCTAssertEqual(finished[0].end, 105)
        XCTAssertEqual(finished[0].motion.count, 250)
        XCTAssertEqual(finished[1].motion.count, 250)

        let last = accumulator.flush()
        XCTAssertEqual(last?.start, 110)
        XCTAssertEqual(last?.motion.count, 100)
        XCTAssertNil(accumulator.flush())
    }

    func testLateHeartRateGoesIntoTheOpenWindow() {
        var accumulator = WindowAccumulator(windowSeconds: 5)
        var finished: [SensorWindow] = []
        let add = { (reading: SensorReading) in
            if let window = accumulator.add(reading) { finished.append(window) }
        }

        makeMotion(seconds: 6).forEach { add(.motion($0)) }              // 0–6 s
        add(.heartRate(HeartRateSample(time: 4.0, bpm: 80)))           // arrives late
        makeMotion(seconds: 5, start: 6).forEach { add(.motion($0)) }  // 6–11 s

        XCTAssertEqual(finished.count, 2)
        XCTAssertEqual(finished[0].heartRates.count, 0)
        XCTAssertEqual(finished[1].heartRates.count, 1)
        XCTAssertEqual(finished[1].heartRates.first?.time, 4.0)   // true time is kept
    }

    func testGapsSkipEmptyWindows() {
        var accumulator = WindowAccumulator(windowSeconds: 5)
        makeMotion(seconds: 2).forEach { _ = accumulator.add(.motion($0)) }
        let afterGap = MotionSample(time: 23, userAcceleration: .zero,
                                    gravity: Vector3(x: 0, y: 0, z: -1), rotationRate: .zero)

        let finished = accumulator.add(.motion(afterGap))
        XCTAssertEqual(finished?.start, 0)
        XCTAssertEqual(finished?.motion.count, 100)

        let current = accumulator.flush()
        XCTAssertEqual(current?.start, 20)   // stays on the 5-second grid
        XCTAssertEqual(current?.end, 25)
    }
}

// MARK: - Whole pipeline

final class MonitoringPipelineTests: XCTestCase {

    func testPipelineTurnsReadingsIntoWindowFeatures() throws {
        let motion = makeMotion(seconds: 11).map { SensorReading.motion($0) }
        let heart = (0..<11).map { SensorReading.heartRate(HeartRateSample(time: Double($0), bpm: 70)) }
        let readings = (motion + heart).sorted { $0.time < $1.time }

        var pipeline = MonitoringPipeline()
        let windows = readings.compactMap { pipeline.process($0) }

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].features.heartRateBPM, 70)
        XCTAssertEqual(windows[0].features.heartRateSampleCount, 5)
        let motionFeatures = try XCTUnwrap(windows[0].features.motion)
        XCTAssertTrue(motionFeatures.isStill)
        XCTAssertTrue(motionFeatures.qualityOK)

        XCTAssertNotNil(pipeline.finish())   // the last, partial window
    }
}

// MARK: - Repeatable randomness

final class SeededRandomTests: XCTestCase {

    func testSameSeedGivesSameNumbers() {
        var a = SeededRandom(seed: 123)
        var b = SeededRandom(seed: 123)
        for _ in 0..<10 { XCTAssertEqual(a.next(), b.next()) }
    }

    func testGaussianHasRequestedMeanAndSpread() {
        var random = SeededRandom(seed: 99)
        let values = (0..<20_000).map { _ in random.gaussian(mean: 5, standardDeviation: 2) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)

        XCTAssertEqual(mean, 5, accuracy: 0.05)
        XCTAssertEqual(variance.squareRoot(), 2, accuracy: 0.05)
    }
}
