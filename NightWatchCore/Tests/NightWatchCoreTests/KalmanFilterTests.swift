import XCTest
@testable import NightWatchCore

// MARK: - Matrix maths

final class MatrixTests: XCTestCase {

    func testMultiplyAndTranspose() {
        let a = Matrix([[1, 2], [3, 4]])
        let b = Matrix([[5], [6]])
        XCTAssertEqual(a * b, Matrix([[17], [39]]))
        XCTAssertEqual(a.transposed, Matrix([[1, 3], [2, 4]]))
        XCTAssertEqual(2 * a, Matrix([[2, 4], [6, 8]]))
    }

    func testInverseUndoesTheMatrix() throws {
        let a = Matrix([[4, 7], [2, 6]])
        let inverse = try XCTUnwrap(a.inverted())
        let product = a * inverse
        for r in 0..<2 {
            for c in 0..<2 {
                XCTAssertEqual(product[r, c], r == c ? 1 : 0, accuracy: 1e-12)
            }
        }
        XCTAssertEqual(try XCTUnwrap(a.determinant), 10, accuracy: 1e-12)
    }

    func testSingularMatrixHasNoInverse() {
        XCTAssertNil(Matrix([[1, 2], [2, 4]]).inverted())
        XCTAssertEqual(Matrix([[1, 2], [2, 4]]).determinant, 0)
    }
}

// MARK: - General Kalman filter

final class KalmanFilterTests: XCTestCase {

    func testEstimatesAConstantFromNoisyMeasurements() {
        // Measuring a constant 10 with noise of SD 2: the estimate should settle near 10
        // and its uncertainty should shrink.
        var random = SeededRandom(seed: 11)
        var filter = KalmanFilter(state: Matrix.column([0]), covariance: Matrix([[100]]))
        for _ in 0..<400 {
            filter.predict(transition: Matrix([[1]]), processNoise: Matrix([[0]]))
            filter.update(measurement: Matrix([[10 + random.gaussian(standardDeviation: 2)]]),
                          observation: Matrix([[1]]),
                          measurementNoise: Matrix([[4]]))
        }
        XCTAssertEqual(filter.state[0, 0], 10, accuracy: 0.5)
        XCTAssertLessThan(filter.covariance[0, 0], 0.05)
    }

    func testLikelihoodIsHighestForUnsurprisingMeasurements() throws {
        let filter = KalmanFilter(state: Matrix.column([0]), covariance: Matrix([[1]]))
        let near = try XCTUnwrap(filter.innovation(measurement: Matrix([[0.5]]), observation: Matrix([[1]]),
                                                   measurementNoise: Matrix([[1]])))
        let far = try XCTUnwrap(filter.innovation(measurement: Matrix([[5]]), observation: Matrix([[1]]),
                                                  measurementNoise: Matrix([[1]])))
        XCTAssertGreaterThan(near.likelihood, far.likelihood)
        XCTAssertEqual(far.normalizedSquared, 12.5, accuracy: 1e-9)   // 5² / (1 + 1)
    }
}

// MARK: - Excess heart-rate filter

final class ExcessHeartRateFilterTests: XCTestCase {

    /// A calibrated baseline whose typical error is 3 bpm.
    private let baseline = BaselineModel(restingHeartRateBPM: 60, bpmPerG: 100, lagRiseSeconds: 30,
                                         lagFallSeconds: 120, residualSDBPM: 3, rSquared: 0.9,
                                         windowsUsed: 800, appleRestingHeartRateBPM: nil,
                                         calibratedAt: nil, isCalibrated: true)

    /// Feeds one measurement every 5 seconds. Returns the time of the last one and every estimate.
    @discardableResult
    private func feed(_ filter: inout ExcessHeartRateFilter, _ measurements: [Double?],
                      activity: Double = 0.01, startingAfter start: Double = 0)
        -> (time: Double, estimates: [ExcessHeartRateEstimate]) {
        var time = start
        var estimates: [ExcessHeartRateEstimate] = []
        for measurement in measurements {
            time += 5
            if let estimate = filter.update(measurement: measurement, activityG: activity, at: time) {
                estimates.append(estimate)
            }
        }
        return (time, estimates)
    }

    private func noise(_ count: Int, seed: UInt64, around level: Double = 0) -> [Double?] {
        var random = SeededRandom(seed: seed)
        return (0..<count).map { _ in level + random.gaussian(standardDeviation: 3) }
    }

    func testUsesCalibratedTrustLevel() {
        XCTAssertEqual(ExcessHeartRateFilter(baseline: baseline).restingMeasurementSDBPM, 3)
        XCTAssertEqual(ExcessHeartRateFilter().restingMeasurementSDBPM, 5)   // uncalibrated default
    }

    func testNothingUntilTheFirstMeasurement() {
        var filter = ExcessHeartRateFilter(baseline: baseline)
        XCTAssertNil(filter.update(measurement: nil, activityG: 0, at: 5))
        XCTAssertEqual(filter.update(measurement: 4, activityG: 0, at: 10)?.decision, .restarted)
    }

    func testSettlesNearZeroAtRest() throws {
        var filter = ExcessHeartRateFilter(baseline: baseline)
        let (_, estimates) = feed(&filter, noise(120, seed: 21))   // 10 minutes
        let last = try XCTUnwrap(estimates.last)

        XCTAssertEqual(last.excessBPM, 0, accuracy: 3)
        XCTAssertEqual(last.trendBPMPerMinute, 0, accuracy: 1)
        XCTAssertLessThan(last.excessSDBPM, 3)   // more certain than one measurement
    }

    func testTracksASteadyClimb() throws {
        // 5 minutes at rest, then excess climbs 2 bpm per minute for 15 minutes (to +30).
        var random = SeededRandom(seed: 22)
        let measurements: [Double?] = (1...240).map { i in
            let minutes = Double(i) * 5 / 60
            return max(0, (minutes - 5) * 2) + random.gaussian(standardDeviation: 3)
        }
        var filter = ExcessHeartRateFilter(baseline: baseline)
        let last = try XCTUnwrap(feed(&filter, measurements).estimates.last)

        XCTAssertEqual(last.excessBPM, 30, accuracy: 3.5)
        XCTAssertEqual(last.trendBPMPerMinute, 2, accuracy: 1)
    }

    func testIgnoresAOneOffSpike() throws {
        var filter = ExcessHeartRateFilter(baseline: baseline)
        let (time, estimates) = feed(&filter, noise(60, seed: 23))
        let before = try XCTUnwrap(estimates.last).excessBPM

        let spike = try XCTUnwrap(filter.update(measurement: 40, activityG: 0.01, at: time + 5))
        XCTAssertEqual(spike.decision, .rejectedAsSpike)
        XCTAssertEqual(spike.excessBPM, before, accuracy: 0.5)
    }

    func testAcceptsAPersistentJumpAfterThreeWindows() throws {
        var filter = ExcessHeartRateFilter(baseline: baseline)
        let (time, _) = feed(&filter, noise(60, seed: 24))
        let jump = feed(&filter, noise(9, seed: 25, around: 30), startingAfter: time).estimates

        XCTAssertEqual(jump.prefix(3).map { $0.decision }, [.rejectedAsSpike, .rejectedAsSpike, .restarted])
        XCTAssertEqual(try XCTUnwrap(jump.last).excessBPM, 30, accuracy: 6)
    }

    func testUncertaintyGrowsWhenReadingsAreMissing() throws {
        var filter = ExcessHeartRateFilter(baseline: baseline)
        let (time, estimates) = feed(&filter, [Double?](repeating: 0, count: 60))
        let before = try XCTUnwrap(estimates.last).excessSDBPM

        let gap = feed(&filter, [Double?](repeating: nil, count: 6), startingAfter: time).estimates
        XCTAssertEqual(gap.last?.decision, .missing)
        XCTAssertGreaterThan(try XCTUnwrap(gap.last).excessSDBPM, before)
    }

    func testMeasurementsCountForLessWhileMoving() throws {
        func movedBy8bpmReading(activity: Double) throws -> Double {
            var filter = ExcessHeartRateFilter(baseline: baseline)
            let (time, _) = feed(&filter, [Double?](repeating: 0, count: 60), activity: activity)
            return try XCTUnwrap(filter.update(measurement: 8, activityG: activity, at: time + 5)).excessBPM
        }
        let atRest = try movedBy8bpmReading(activity: 0)
        let dancing = try movedBy8bpmReading(activity: 0.5)
        XCTAssertGreaterThan(atRest, dancing)
        XCTAssertGreaterThan(dancing, 0)
    }

    func testRestartsAfterALongGap() {
        var filter = ExcessHeartRateFilter(baseline: baseline)
        feed(&filter, [Double?](repeating: 0, count: 12))
        let after = filter.update(measurement: 20, activityG: 0, at: 1_000)   // ~15 minutes later
        XCTAssertEqual(after?.decision, .restarted)
        XCTAssertEqual(after?.excessBPM, 20)
    }
}

// MARK: - Filter inside the pipeline

final class PipelineFilterTests: XCTestCase {

    func testPipelineReportsSmoothedExcess() throws {
        let baseline = BaselineModel(restingHeartRateBPM: 60, bpmPerG: 100, lagRiseSeconds: 30,
                                     lagFallSeconds: 120, residualSDBPM: 3, rSquared: 0.9,
                                     windowsUsed: 800, appleRestingHeartRateBPM: nil,
                                     calibratedAt: nil, isCalibrated: true)
        // Two minutes sitting still with heart rate 75: expected 60, so excess +15.
        let motion = (0..<6_000).map { i -> SensorReading in
            .motion(MotionSample(time: Double(i) / 50, userAcceleration: .zero,
                                 gravity: Vector3(x: 0, y: 0, z: -1), rotationRate: .zero))
        }
        let heart = (0..<120).map { SensorReading.heartRate(HeartRateSample(time: Double($0), bpm: 75)) }
        var pipeline = MonitoringPipeline(baseline: baseline)
        let results = (motion + heart).sorted { $0.time < $1.time }.compactMap { pipeline.process($0) }

        let filtered = try XCTUnwrap(results.last?.filtered)
        XCTAssertEqual(filtered.excessBPM, 15, accuracy: 0.5)
        XCTAssertEqual(filtered.trendBPMPerMinute, 0, accuracy: 0.5)
        XCTAssertEqual(filtered.decision, .accepted)
    }
}
