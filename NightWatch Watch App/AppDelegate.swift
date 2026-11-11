import WatchKit

/// Receives system events that SwiftUI doesn't handle directly.
final class AppDelegate: NSObject, WKApplicationDelegate {

    /// watchOS calls this after relaunching Night Watch because it stopped
    /// unexpectedly (e.g. crashed) while a monitoring or calibration workout
    /// session was still running. We pick the session back up so monitoring
    /// doesn't silently stop.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            MonitorController.shared.recoverActiveSession()
        }
    }
}
