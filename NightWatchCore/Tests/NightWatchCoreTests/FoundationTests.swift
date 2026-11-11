import XCTest
@testable import NightWatchCore

/// Step 1 tests: check the basic building blocks and the safety wording.
/// Run them with:  cd NightWatchCore && swift test
final class SafetyTextTests: XCTestCase {

    func testDisclaimerWordingIsExact() {
        XCTAssertEqual(
            SafetyText.disclaimer,
            "Prototype — not a medical device. If someone has chest pain, is overheating or having a seizure, call 999."
        )
    }

    func testGreenNeverClaimsTheUserIsSafe() {
        XCTAssertTrue(RiskLevel.green.message.contains("does not mean you are safe"))
    }

    func testAmberSuggestsECGAndWaterWithoutFalseReassurance() {
        let text = RiskLevel.amber.message
        XCTAssertTrue(text.contains("ECG"))
        XCTAssertTrue(text.contains("water"))
        XCTAssertTrue(text.contains("does not rule out"))
    }

    func testAmberStepsPromptAnECGFirstAndKeepTheCaution() {
        XCTAssertTrue(SafetyText.amberSteps.first?.contains("ECG") ?? false)
        XCTAssertTrue(SafetyText.amberSteps.contains { $0.contains("water") })
        XCTAssertTrue(SafetyText.ecgCaution.contains("does not rule out"))
    }

    func testRedPointsTo999() {
        XCTAssertTrue(RiskLevel.red.message.contains("999"))
    }
}

final class SensorBasicsTests: XCTestCase {

    func testWristTemperatureSourceIsDisabled() {
        let source = DisabledWristTemperatureSource()
        XCTAssertFalse(source.isAvailable)
        XCTAssertEqual(source.provides, [.wristTemperature])
        XCTAssertThrowsError(try source.start { _ in XCTFail("A disabled source must never deliver readings") })
    }

    func testReadingReportsItsTimeAndKind() {
        let reading = SensorReading.heartRate(HeartRateSample(time: 12.5, bpm: 72))
        XCTAssertEqual(reading.time, 12.5)
        XCTAssertEqual(reading.kind, .heartRate)
    }

    func testRiskLevelsAreOrdered() {
        XCTAssertTrue(RiskLevel.green < RiskLevel.amber)
        XCTAssertTrue(RiskLevel.amber < RiskLevel.red)
        XCTAssertEqual(RiskLevel.allCases.max(), .red)
    }

    func testVectorMagnitude() {
        XCTAssertEqual(Vector3(x: 3, y: 4, z: 0).magnitude, 5, accuracy: 1e-12)
        XCTAssertEqual(Vector3.zero.magnitude, 0)
    }
}
