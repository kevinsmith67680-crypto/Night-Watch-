import XCTest
@testable import NightWatchCore

/// Builds one window's results with just the values the risk rules look at.
private func windowResult(at time: Double, still: Bool, heartRate: Double?, excess: Double?,
                          trend: Double, tremor: Double, rhythm: Double, calibrated: Bool) -> WindowResult {
    let motion = MotionFeatures(sampleCount: 250, sampleRateHz: 50, qualityOK: true,
                                activityG: still ? 0.01 : 0.4, isStill: still,
                                tremorAccelMilliG: 0, tremorGyroDegPerSec: tremor, tremorPeakHz: 9,
                                tremorRhythmicity: rhythm, tremorReliable: still,
                                forearmElevationDegrees: 0, armOrientation: .forearmHorizontal)
    let features = WindowFeatures(start: time - 5, end: time, heartRateBPM: heartRate,
                                  heartRateSampleCount: heartRate == nil ? 0 : 5,
                                  motion: motion, wristTemperatureDeviation: nil)
    let filtered = excess.map {
        ExcessHeartRateEstimate(time: time, excessBPM: $0, trendBPMPerMinute: trend,
                                excessSDBPM: 1, trendSDBPMPerMinute: 0.3, decision: .accepted)
    }
    return WindowResult(features: features, laggedActivityG: still ? 0.01 : 0.4,
                        expectedHeartRateBPM: 60, excessHeartRateBPM: excess,
                        baselineIsCalibrated: calibrated, filtered: filtered)
}

/// Plays a scenario through the rules, a few minutes at a time.
private struct Session {
    var rules = PlaceholderRiskRules()
    var time = 0.0

    /// Feeds `minutes` of identical 5-second windows and returns the last verdict.
    @discardableResult
    mutating func run(minutes: Double, still: Bool = true, heartRate: Double? = 70,
                      excess: Double? = 0, trend: Double = 0, tremor: Double = 0.3,
                      rhythm: Double = 0.2, calibrated: Bool = true) -> RiskAssessment {
        let windows = Int((minutes * 12).rounded())
        precondition(windows > 0, "Run at least one window")
        var verdicts: [RiskAssessment] = []
        for _ in 0..<windows {
            time += 5
            verdicts.append(rules.assess(windowResult(at: time, still: still, heartRate: heartRate,
                                                      excess: excess, trend: trend, tremor: tremor,
                                                      rhythm: rhythm, calibrated: calibrated)))
        }
        return verdicts[verdicts.count - 1]
    }
}

final class RiskRulesTests: XCTestCase {

    // MARK: Things that must stay green

    func testCalmRestStaysGreen() {
        var session = Session()
        let verdict = session.run(minutes: 15, heartRate: 65, excess: 2)
        XCTAssertEqual(verdict.level, .green)
        XCTAssertEqual(verdict.stillMinutes, 15, accuracy: 0.01)
        XCTAssertEqual(verdict.engineName, "Temporary rules")
    }

    func testDancingNeverRaisesTheLevel() {
        // Very high heart rate, but explained by movement.
        var session = Session()
        let verdict = session.run(minutes: 15, still: false, heartRate: 150, excess: 40, trend: 2)
        XCTAssertEqual(verdict.level, .green)
        XCTAssertEqual(verdict.stillMinutes, 0)
    }

    func testRecoveringAfterExerciseStaysGreen() {
        // Excess still high but clearly falling.
        var session = Session()
        XCTAssertEqual(session.run(minutes: 12, excess: 26, trend: -1).level, .green)
    }

    // MARK: Amber

    func testRisingExcessWhileStillTurnsAmberAfterFiveMinutes() {
        var session = Session()
        XCTAssertEqual(session.run(minutes: 4, excess: 22, trend: 1).level, .green)   // not still long enough yet
        let verdict = session.run(minutes: 2, excess: 22, trend: 1)
        XCTAssertEqual(verdict.level, .amber)
        XCTAssertTrue(verdict.reasons.contains { $0.contains("rising") })
    }

    func testHighSteadyExcessWhileStillTurnsAmber() {
        var session = Session()
        XCTAssertEqual(session.run(minutes: 6, excess: 30, trend: 0).level, .amber)
    }

    // MARK: Red

    func testFastClimbWhileStillTurnsRed() {
        var session = Session()
        XCTAssertEqual(session.run(minutes: 6, excess: 38, trend: 1.5).level, .red)
    }

    func testHighExcessWithTremorTurnsRed() {
        var withTremor = Session()
        let verdict = withTremor.run(minutes: 6, excess: 38, trend: 0, tremor: 2.5, rhythm: 0.7)
        XCTAssertEqual(verdict.level, .red)
        XCTAssertTrue(verdict.tremorRaised)

        // The same without tremor is only amber.
        var withoutTremor = Session()
        XCTAssertEqual(withoutTremor.run(minutes: 6, excess: 38, trend: 0).level, .amber)
    }

    func testVeryHighExcessAloneTurnsRed() {
        var session = Session()
        XCTAssertEqual(session.run(minutes: 6, excess: 46, trend: 0).level, .red)
    }

    // MARK: Backstops that don't need calibration

    func testUncalibratedIgnoresExcessButKeepsHeartRateBackstop() {
        var excessOnly = Session()
        let verdict = excessOnly.run(minutes: 12, heartRate: 90, excess: 30, trend: 2, calibrated: false)
        XCTAssertEqual(verdict.level, .green)
        XCTAssertTrue(verdict.reasons.contains { $0.contains("Not calibrated") })

        var highRate = Session()
        XCTAssertEqual(highRate.run(minutes: 9, heartRate: 115, calibrated: false).level, .green)
        XCTAssertEqual(highRate.run(minutes: 2, heartRate: 115, calibrated: false).level, .amber)
    }

    func testVeryHighHeartRateWhileStillTurnsRed() {
        var session = Session()
        XCTAssertEqual(session.run(minutes: 6, heartRate: 145, calibrated: false).level, .red)
    }

    // MARK: Behaviour

    func testStepsDownOnlyAfterThreeQuietMinutes() {
        var session = Session()
        XCTAssertEqual(session.run(minutes: 6, excess: 30).level, .amber)

        let holding = session.run(minutes: 2, excess: 5)
        XCTAssertEqual(holding.level, .amber)
        XCTAssertTrue(holding.reasons.contains { $0.contains("Staying amber") })

        XCTAssertEqual(session.run(minutes: 2, excess: 5).level, .green)
    }

    func testBriefMovementDoesNotEndStillness() {
        var brief = Session()
        brief.run(minutes: 4)
        brief.run(minutes: 2.0 / 12, still: false)          // 10 seconds of movement
        XCTAssertEqual(brief.run(minutes: 2).stillMinutes, 74.0 * 5 / 60, accuracy: 0.01)

        var longer = Session()
        longer.run(minutes: 4)
        longer.run(minutes: 3.0 / 12, still: false)         // 15 seconds of movement
        XCTAssertEqual(longer.run(minutes: 2).stillMinutes, 2, accuracy: 0.01)
    }

    func testMissingHeartRateIsReported() {
        var session = Session()
        session.run(minutes: 1)
        let verdict = session.run(minutes: 1.5, heartRate: nil, excess: nil)
        XCTAssertFalse(verdict.hasRecentHeartRate)
        XCTAssertTrue(verdict.reasons.contains { $0.contains("No heart rate") })
    }

    func testPipelineAttachesAVerdictToEveryWindow() {
        let motion = (0..<6_000).map { i -> SensorReading in
            .motion(MotionSample(time: Double(i) / 50, userAcceleration: .zero,
                                 gravity: Vector3(x: 0, y: 0, z: -1), rotationRate: .zero))
        }
        let heart = (0..<120).map { SensorReading.heartRate(HeartRateSample(time: Double($0), bpm: 70)) }
        var pipeline = MonitoringPipeline()
        let results = (motion + heart).sorted { $0.time < $1.time }.compactMap { pipeline.process($0) }

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.risk?.level == .green })
    }
}
