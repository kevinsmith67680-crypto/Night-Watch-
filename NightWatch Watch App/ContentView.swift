import SwiftUI
import NightWatchCore

/// The app's first screen: asks for Health access, then shows the home menu.
struct ContentView: View {
    @StateObject private var health = HealthKitAuthorizer()
    @StateObject private var monitor = MonitorController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if health.status == .ready {
                HomeView(monitor: monitor)
            } else {
                PermissionView(health: health)
            }
        }
        // Check permission when the app opens...
        .task { await health.refreshStatus() }
        // ...and again whenever it comes back to the front,
        // in case the user changed it in Settings meanwhile.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await health.refreshStatus() }
            }
        }
    }
}

/// Shown until Health access is set up.
private struct PermissionView: View {
    @ObservedObject var health: HealthKitAuthorizer

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Night Watch")
                    .font(.headline)
                message
                DisclaimerBanner()
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var message: some View {
        switch health.status {
        case .checking, .ready:
            ProgressView()

        case .unavailable:
            Text("Health data isn't available on this device.")
                .font(.footnote)

        case .needsPermission:
            Text("Night Watch needs access to your heart rate.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Allow Health access") {
                Task { await health.requestAccess() }
            }

        case .workoutDenied:
            Text("Workout permission is off, so monitoring can't run. "
                 + "On your iPhone: Settings › Privacy & Security › Health › Night Watch.")
                .font(.footnote)
                .multilineTextAlignment(.center)

        case .failed(let message):
            Text("Something went wrong: \(message)")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    ContentView()
}
