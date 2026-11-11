import SwiftUI
import WatchKit

/// The starting point of the watch app. `@main` tells Swift to begin here.
@main
struct NightWatchApp: App {
    /// Handles crash recovery of a running monitoring session.
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Get ready to send logs to the iPhone. (The app starts on the main
        // thread, which PhoneTransfer requires.)
        MainActor.assumeIsolated {
            PhoneTransfer.shared.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
