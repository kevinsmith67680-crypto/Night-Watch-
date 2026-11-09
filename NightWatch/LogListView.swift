import SwiftUI
import NightWatchCore

/// iPhone screen. Step 1: an explanation only. Step 7 adds the list of logs.
struct LogListView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Monitoring runs on your Apple Watch. Open Night Watch on the watch to start.")
                }
                Section("Exported logs") {
                    Text("Logs sent from your watch will appear here (coming in Step 7).")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text(SafetyText.disclaimer)
                        .font(.footnote)
                }
            }
            .navigationTitle("Night Watch")
        }
    }
}

#Preview {
    LogListView()
}
