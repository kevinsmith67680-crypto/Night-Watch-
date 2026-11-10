import Foundation
import WatchKit
import NightWatchCore

/// Taps the wearer's wrist when the light turns amber or red.
///
/// This is the ONLY alert in this prototype: nothing is called, messaged or
/// sent anywhere. Because monitoring runs as a workout session, the tap still
/// happens when the screen is off.
final class HapticAlerts: EscalationHandler {
    private let config: RiskConfig
    private var lastRedTap: Date?

    init(config: RiskConfig) {
        self.config = config
    }

    func handle(_ assessment: RiskAssessment, previousLevel: RiskLevel?) {
        guard config.hapticAlertsEnabled else { return }
        let device = WKInterfaceDevice.current()
        let now = Date()

        if assessment.level > (previousLevel ?? .green) {
            // The level just went up.
            device.play(assessment.level == .red ? .failure : .notification)
            lastRedTap = assessment.level == .red ? now : nil
        } else if assessment.level == .red {
            // Still red: remind every few minutes.
            if let last = lastRedTap, now.timeIntervalSince(last) >= config.redHapticRepeatMinutes * 60 {
                device.play(.failure)
                lastRedTap = now
            }
        } else {
            lastRedTap = nil
        }
    }
}
