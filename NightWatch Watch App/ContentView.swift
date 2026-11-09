import SwiftUI
import NightWatchCore

/// The main watch screen.
/// Step 1: checks Health permission. Later steps add monitoring, calibration,
/// the traffic light and the simulator.
struct ContentView: View {
    @StateObject private var health = HealthKitAuthorizer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Night Watch")
                    .font(.headline)

                permissionSection

                DisclaimerBanner()
            }
            .padding(.horizontal, 4)
        }
        // Check permission when the screen first appears...
        .task { await health.refreshStatus() }
        // ...and again whenever the app comes back to the front,
        // in case the user changed it in Settings meanwhile.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await health.refreshStatus() }
            }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch health.status {
        case .checking:
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

        case .ready:
            Label("Health access set up", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.footnote)
            Text("Monitoring comes in Step 2.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
