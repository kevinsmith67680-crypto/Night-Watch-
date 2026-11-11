import XCTest
@testable import NightWatchCore

// MARK: - Helpers

/// A finished window with the given activity and heart rate (other values don't matter here).
private func window(endingAt time: Double, activity: Double, heartRate: Double?,
                    qualityOK: Bool = true) -> WindowFeatures {
    let motion = MotionFeatures(sampleCount: 250, sampleRateHz: 50, qualityOK: qualityOK,
                                activityG: activity, isStill: activity < 0.05,
                                tremorAccelMilliG: 0, tremorGyroDegPerSec: 0, tremorPeakHz: 0,
                                tremorRhythmicity: 0, tremorReliable: activity < 0.05,
                                forearmElevationDegrees: 0, armOrientation: .forearmHorizontal)
    return WindowFeatures(start: time - 5, end: time, heartRateBPM: heartRate,
                          heartRateSampleCount: heartRate == nil ? 0 : 5,
                          motion: motion, wristTemperatureDeviation: nil)
}

/// A pretend person whose heart rate follows a KNOWN baseline exactly, plus noise.
/// Calibration should recover these numbers.
private struct TruePerson {
    var resting = 62.0
    var bpmPerG = 90.0
    var rise = 30.0
    var fall = 120.0
    var noiseSD = 2.0
}

/// About 71 minutes of normal life: sitting, walking, dancing, brisk walking.
private func calibrationDay(for person: TruePerson, seed: UInt64, spikeEvery: Int? = nil,
                            startTime: Double = 1_000) -> [WindowFeatures] {
    let routine: [(minutes: Double, activity: Double)] = [
        (6, 0.01), (3, 0.2), (5, 0.01), (2, 0.5), (4, 0.01), (2, 0.3),
        (6, 0.01), (3, 0.2), (5, 0.01), (2, 0.5), (4, 0.01), (2, 0.3),
        (6, 0.01), (3, 0.2), (5, 0.01), (2, 0.5), (4, 0.01), (2, 0.3),
        (5, 0.01),
    ]
    var random = SeededRandom(seed: seed)
    var lag = ActivityLagFilter(riseSeconds: person.rise, fallSeconds: person.fall)
    var windows: [WindowFeatures] = []
    var time = startTime
    for block in routine {
        for _ in 0..<Int(block.minutes * 12) {   // 12 windows per minute
            time += 5
            let activity = max(0.002, block.activity + random.gaussian(standardDeviation: block.activity * 0.1))
            let lagged = lag.update(activity: activity, at: time)
            var heartRate = person.resting + person.bpmPerG * lagged
                + random.gaussian(standardDeviation: person.noiseSD)
            if let every = spikeEvery, windows.count % every == every - 1 {
                heartRate += 60   // strap slip
            }
            windows.append(window(endingAt: time, activity: activity, heartRate: heartRate))
        }
    }
    return windows
}

// MARK: - Lag filter

final class ActivityLagFilterTests: XCTestCase {

    func testRisesAboutTwoThirdsInOneRiseTime() {
        var lag = ActivityLagFilter(riseSeconds: 30, fallSeconds: 120)
        _ = lag.update(activity: 0, at: 0)
        var value = 0.0
        for step in 1...6 { value = lag.update(activity: 0.5, at: Double(step) * 5) }   // 30 s
        XCTAssertEqual(value, 0.5 * (1 - exp(-1)), accuracy: 1e-9)   // ≈ 0.316
    }

    func testFallsMoreSlowlyThanItRises() {
        var lag = ActivityLagFilter(riseSeconds: 30, fallSeconds: 120)
        _ = lag.update(activity: 0.5, at: 0)
        var value = 0.0
        for step in 1...6 { value = lag.update(activity: 0, at: Double(step) * 5) }     // 30 s
        XCTAssertEqual(value, 0.5 * exp(-0.25), accuracy: 1e-9)    // still ≈ 0.39
    }

    func testResetForgetsHistory() {
        var lag = ActivityLagFilter(riseSeconds: 30, fallSeconds: 120)
        _ = lag.update(activity: 0.5, at: 0)
        lag.reset()
        XCTAssertNil(lag.value)
        let first = lag.update(activity: 0.1, at: 100)
        XCTAssertEqual(first, 0.1)
    }
}

// MARK: - Calibration

final class BaselineCalibratorTests: XCTestCase {

    func testRecoversAKnownBaseline() throws {
        let person = TruePerson()
        var calibrator = BaselineCalibrator()
        calibrationDay(for: person, seed: 1).forEach { calibrator.add($0) }

        XCTAssertTrue(calibrator.progress.isReady)
        let result = try calibrator.fit()
        let model = result.model

        XCTAssertTrue(model.isCalibrated)
        XCTAssertEqual(model.restingHeartRateBPM, person.resting, accuracy: 2)
        XCTAssertEqual(model.bpmPerG, person.bpmPerG, accuracy: 9)        // within 10%
        XCTAssertEqual(model.lagRiseSeconds, person.rise)
        XCTAssertEqual(model.lagFallSeconds, person.fall)
        XCTAssertEqual(model.residualSDBPM, person.noiseSD, accuracy: 0.6)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testStrapSpikesDoNotSpoilTheFit() throws {
        let person = TruePerson()
        var calibrator = BaselineCalibrator()
        calibrationDay(for: person, seed: 2, spikeEvery: 50).forEach { calibrator.add($0) }   // 2% spikes

        let model = try calibrator.fit().model
        XCTAssertEqual(model.restingHeartRateBPM, person.resting, accuracy: 2)
        XCTAssertEqual(model.bpmPerG, person.bpmPerG, accuracy: 9)
        XCTAssertLessThan(model.residualSDBPM, 3)
    }

    func testRefusesWithTooLittleData() {
        var calibrator = BaselineCalibrator()
        for i in 1...120 {   // 10 minutes of sitting only
            calibrator.add(window(endingAt: Double(i) * 5, activity: 0.01, heartRate: 65))
        }
        let progress = calibrator.progress
        XCTAssertFalse(progress.isReady)
        XCTAssertEqual(progress.totalMinutes, 10, accuracy: 1e-9)
        XCTAssertEqual(progress.stillMinutes, 10, accuracy: 1e-9)
        XCTAssertEqual(progress.activeMinutes, 0)
        XCTAssertEqual(progress.missing.count, 3)   // total, still and active all short

        XCTAssertThrowsError(try calibrator.fit()) { error in
            XCTAssertEqual(error as? CalibrationError, .notEnoughData(progress.missing))
        }
    }

    func testIgnoresUnusableWindows() {
        var calibrator = BaselineCalibrator()
        XCTAssertFalse(calibrator.add(window(endingAt: 5, activity: 0.01, heartRate: nil)))
        XCTAssertFalse(calibrator.add(window(endingAt: 10, activity: 0.01, heartRate: 60, qualityOK: false)))
        XCTAssertTrue(calibrator.add(window(endingAt: 15, activity: 0.01, heartRate: 60)))
        XCTAssertEqual(calibrator.points.count, 1)
    }

    func testWarnsWhenAppleRestingHeartRateDisagrees() throws {
        var calibrator = BaselineCalibrator()
        calibrationDay(for: TruePerson(), seed: 3).forEach { calibrator.add($0) }

        let result = try calibrator.fit(appleRestingHeartRateBPM: 85)
        XCTAssertEqual(result.model.appleRestingHeartRateBPM, 85)
        XCTAssertTrue(result.warnings.contains { $0.contains("Apple") })
    }

    func testSessionsOnDifferentDaysCombine() throws {
        let person = TruePerson()
        var calibrator = BaselineCalibrator()
        // The same routine recorded as two separate sessions a day apart.
        let day = calibrationDay(for: person, seed: 4)
        let half = day.count / 2
        day[..<half].forEach { calibrator.add($0) }
        calibrationDay(for: person, seed: 5, startTime: 100_000)[half...].forEach { calibrator.add($0) }

        let model = try calibrator.fit().model
        XCTAssertEqual(model.restingHeartRateBPM, person.resting, accuracy: 2)
        XCTAssertEqual(model.bpmPerG, person.bpmPerG, accuracy: 9)
    }

    func testLearnsYourNormalTremor() throws {
        var calibrator = BaselineCalibrator()
        for var window in calibrationDay(for: TruePerson(), seed: 6) {
            window.motion?.tremorGyroDegPerSec = 0.7   // this person's normal tremor
            calibrator.add(window)
        }
        XCTAssertTrue(calibrator.progress.hasEnoughTremorData)
        let result = try calibrator.fit()
        XCTAssertEqual(try XCTUnwrap(result.model.tremorBaselineDegPerSec), 0.7, accuracy: 1e-9)
        XCTAssertFalse(result.warnings.contains { $0.contains("tremor") })
    }

    func testWithoutQuietTremorDataTheFixedThresholdIsUsed() throws {
        var calibrator = BaselineCalibrator()
        for var window in calibrationDay(for: TruePerson(), seed: 7) {
            window.motion?.tremorReliable = false
            calibrator.add(window)
        }
        XCTAssertTrue(calibrator.progress.isReady)               // tremor data is optional
        XCTAssertFalse(calibrator.progress.hasEnoughTremorData)
        let result = try calibrator.fit()
        XCTAssertNil(result.model.tremorBaselineDegPerSec)
        XCTAssertTrue(result.warnings.contains { $0.contains("tremor") })
    }

    func testDataSavedBeforeTheTremorUpdateStillLoads() throws {
        // A baseline and calibration points saved by the earlier version have no tremor fields.
        let oldBaseline = #"{"restingHeartRateBPM":62,"bpmPerG":90,"lagRiseSeconds":30,"lagFallSeconds":120,"residualSDBPM":3,"windowsUsed":700,"isCalibrated":true}"#
        let model = try JSONDecoder().decode(BaselineModel.self, from: Data(oldBaseline.utf8))
        XCTAssertEqual(model.restingHeartRateBPM, 62)
        XCTAssertNil(model.tremorBaselineDegPerSec)

        let oldPoints = #"[{"time":5,"activityG":0.01,"heartRateBPM":60}]"#
        let points = try JSONDecoder().decode([CalibrationPoint].self, from: Data(oldPoints.utf8))
        XCTAssertEqual(points.count, 1)
        XCTAssertNil(points[0].tremorDegPerSec)
    }

    func testBaselineSurvivesSavingAndLoading() throws {
        let model = BaselineModel(restingHeartRateBPM: 61.5, bpmPerG: 95, lagRiseSeconds: 30,
                                  lagFallSeconds: 120, residualSDBPM: 2.1, rSquared: 0.9,
                                  windowsUsed: 800, appleRestingHeartRateBPM: 60,
                                  calibratedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                  isCalibrated: true)
        let data = try JSONEncoder().encode(model)
        XCTAssertEqual(try JSONDecoder().decode(BaselineModel.self, from: data), model)
    }
}

// MARK: - Expected and excess heart rate in the pipeline

final class ExpectedHeartRateTests: XCTestCase {

    /// Five minutes of steady walking (activity 0.2 g) with heart rate fixed at `bpm`.
    private func steadyWalk(bpm: Double) -> [SensorReading] {
        let amplitude = 0.2 * 2.0.squareRoot()   // a 2 Hz swing with RMS 0.2 g
        let motion = (0..<15_000).map { i -> SensorReading in
            let t = Double(i) / 50
            return .motion(MotionSample(time: t,
                                        userAcceleration: Vector3(x: amplitude * sin(2 * Double.pi * 2 * t), y: 0, z: 0),
                                        gravity: Vector3(x: 0, y: 0, z: -1),
                                        rotationRate: .zero))
        }
        let heart = (0..<300).map { SensorReading.heartRate(HeartRateSample(time: Double($0), bpm: bpm)) }
        return (motion + heart).sorted { $0.time < $1.time }
    }

    func testExcessIsMeasuredMinusExpected() throws {
        let baseline = BaselineModel(restingHeartRateBPM: 60, bpmPerG: 100, lagRiseSeconds: 30,
                                     lagFallSeconds: 120, residualSDBPM: 2, rSquared: 0.9,
                                     windowsUsed: 800, appleRestingHeartRateBPM: nil,
                                     calibratedAt: nil, isCalibrated: true)
        var pipeline = MonitoringPipeline(baseline: baseline)
        let results = steadyWalk(bpm: 100).compactMap { pipeline.process($0) }
        let last = try XCTUnwrap(results.last)

        // Expected = 60 + 100 × 0.2 = 80 bpm, so excess = 100 − 80 = 20 bpm.
        XCTAssertEqual(try XCTUnwrap(last.laggedActivityG), 0.2, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(last.expectedHeartRateBPM), 80, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(last.excessHeartRateBPM), 20, accuracy: 1)
        XCTAssertTrue(last.baselineIsCalibrated)
    }

    func testUncalibratedPipelineSaysSo() {
        var pipeline = MonitoringPipeline()
        let results = steadyWalk(bpm: 90).compactMap { pipeline.process($0) }
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { !$0.baselineIsCalibrated })
    }
}
