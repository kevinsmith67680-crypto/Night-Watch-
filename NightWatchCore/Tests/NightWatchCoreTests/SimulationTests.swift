import XCTest
@testable import NightWatchCore

/// The scenarios are the main proof that the logic works, since the real
/// dangerous situation can't be tested. Each one plays a pretend person
/// through the exact pipeline the watch uses.
/// (These take a little longer than the other tests: a few seconds each.)
final class ScenarioTests: XCTestCase {

    private func assertPasses(_ kind: ScenarioKind, seeds: [UInt64], file: StaticString = #filePath, line: UInt = #line) {
        for seed in seeds {
            let run = Simulator.run(kind, seed: seed)
            XCTAssertTrue(run.passed, "\(run.scenario.title), seed \(seed): \(run.summary)", file: file, line: line)
        }
    }

    func testRestingStaysGreen() {
        assertPasses(.resting, seeds: [1])
    }

    func testDancingAndRecoveryStayGreen() {
        assertPasses(.dancing, seeds: [1, 2])
    }

    func testCaffeineStaysGreen() {
        assertPasses(.caffeine, seeds: [1])
    }

    func testStrapGlitchesStayGreenAndSpikesAreIgnored() {
        let run = Simulator.run(.strapArtefacts, seed: 1)
        XCTAssertTrue(run.passed, run.summary)
        XCTAssertGreaterThanOrEqual(run.spikesIgnored, 5, run.summary)
    }

    func testStimulantToxicityGoesAmberThenRedInGoodTime() throws {
        for seed: UInt64 in [1, 2] {
            let run = Simulator.run(.stimulantToxicity, seed: seed)
            XCTAssertTrue(run.passed, run.summary)

            // The climb starts at minute 5. Amber should follow within about 10 minutes,
            // and red within about 20.
            let amber = try XCTUnwrap(run.minutesUntil(.amber), run.summary)
            let red = try XCTUnwrap(run.minutesUntil(.red), run.summary)
            XCTAssertLessThan(amber, 16, run.summary)
            XCTAssertLessThan(red, 25, run.summary)
            XCTAssertGreaterThan(red - amber, 2, "Amber should give real warning before red. \(run.summary)")
        }
    }

    func testDancingReallyMovesAndRecoveryReallyHappens() throws {
        // Check the scenario does what it claims, so the green result means something.
        let run = Simulator.run(.dancing, seed: 1)
        let activities = run.results.compactMap { $0.features.motion?.activityG }
        XCTAssertGreaterThan(activities.max() ?? 0, 0.3)
        // Sitting after dancing: the measured heart rate is still well above resting.
        let recovery = run.results.filter { ($0.features.end - run.startTime) / 60 > 25.5 && ($0.features.end - run.startTime) / 60 < 26.5 }
        let recoveryRate = try XCTUnwrap(recovery.compactMap { $0.features.heartRateBPM }.max())
        XCTAssertGreaterThan(recoveryRate, 80)
    }

    func testSameSeedGivesTheSameReadings() {
        var a = ScenarioGenerator(scenario: Scenario.make(.stimulantToxicity), seed: 9)
        var b = ScenarioGenerator(scenario: Scenario.make(.stimulantToxicity), seed: 9)
        for _ in 0..<500 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testGeneratorProducesReadingsInTimeOrder() {
        var generator = ScenarioGenerator(scenario: Scenario.make(.strapArtefacts), seed: 3)
        var previous = -Double.infinity
        var heartRates = 0
        var count = 0
        while let reading = generator.next(), count < 20_000 {
            XCTAssertGreaterThanOrEqual(reading.time, previous)
            previous = reading.time
            if case .heartRate = reading { heartRates += 1 }
            count += 1
        }
        // 20 000 readings is about 6.5 minutes: 50 motion + 0.5 heart-rate readings a second.
        XCTAssertEqual(Double(heartRates), Double(count) / 101, accuracy: 3)
    }
}

final class CSVFormatTests: XCTestCase {

    /// Splits one CSV line into fields, respecting quotes.
    private func fields(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(line)
        var i = 0
        while i < characters.count {
            let c = characters[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < characters.count && characters[i + 1] == "\"" {
                        current.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                result.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        result.append(current)
        return result
    }

    func testEveryRowHasOneValuePerColumn() throws {
        let run = Simulator.run(.stimulantToxicity, seed: 1)
        let columns = fields(CSVFormat.header)
        XCTAssertEqual(columns.count, CSVFormat.columns.count)

        for result in run.results {
            let row = fields(CSVFormat.row(for: result, source: "simulated-stimulantToxicity", batteryPercent: 87))
            XCTAssertEqual(row.count, columns.count)
        }

        // A red row: reasons contain commas, so they must be quoted and come back intact.
        let redResult = try XCTUnwrap(run.results.last { $0.risk?.level == .red })
        let row = fields(CSVFormat.row(for: redResult, source: "sim", batteryPercent: nil))
        let value = { (name: String) -> String in row[columns.firstIndex(of: name)!] }
        XCTAssertEqual(value("risk_level"), "red")
        XCTAssertTrue(value("risk_reasons").contains(","))
        XCTAssertEqual(value("battery_percent"), "")
        XCTAssertEqual(value("still"), "1")
    }

    func testMissingValuesAreEmptyCells() {
        let features = WindowFeatures(start: 0, end: 5, heartRateBPM: nil, heartRateSampleCount: 0,
                                      motion: nil, wristTemperatureDeviation: nil)
        let result = WindowResult(features: features, laggedActivityG: nil, expectedHeartRateBPM: nil,
                                  excessHeartRateBPM: nil, baselineIsCalibrated: false)
        let row = fields(CSVFormat.row(for: result, source: "test"))
        XCTAssertEqual(row.count, CSVFormat.columns.count)
        XCTAssertEqual(row[CSVFormat.columns.firstIndex(of: "hr_bpm")!], "")
        XCTAssertEqual(row[CSVFormat.columns.firstIndex(of: "baseline_calibrated")!], "0")
    }

    func testQuotesInsideTextAreEscaped() {
        XCTAssertEqual(CSVFormat.escape("plain"), "plain")
        XCTAssertEqual(CSVFormat.escape("a, b"), "\"a, b\"")
        XCTAssertEqual(CSVFormat.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }
}
