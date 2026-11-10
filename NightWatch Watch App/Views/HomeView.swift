import SwiftUI
import NightWatchCore

/// The home menu: Monitoring or Calibration.
struct HomeView: View {
    @ObservedObject var monitor: MonitorController

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    MonitorView(monitor: monitor)
                } label: {
                    Label("Monitoring", systemImage: "heart.text.square")
                }

                NavigationLink {
                    CalibrationView(monitor: monitor)
                } label: {
                    Label("Calibration", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    SimulationView()
                } label: {
                    Label("Simulation", systemImage: "play.rectangle")
                }

                NavigationLink {
                    LogsView()
                } label: {
                    Label("Logs", systemImage: "doc.text")
                }

                if monitor.isActive {
                    Text(monitor.mode == .calibrating ? "Calibration recording…" : "Monitoring running…")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if monitor.baseline == nil {
                    Text("Not calibrated yet. Expected heart rate uses rough defaults until you calibrate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                DisclaimerBanner()
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("Night Watch")
        }
    }
}
