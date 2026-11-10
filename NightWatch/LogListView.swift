import SwiftUI
import NightWatchCore

/// iPhone screen: logs received from the watch. Tap one to share or save it
/// (Files, AirDrop, Mail, Numbers…). Swipe left to delete.
struct LogListView: View {
    @StateObject private var receiver = PhoneLogReceiver()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("On the watch: Night Watch › Logs, then tap a log to send it here. Keep this app open while it arrives.")
                        .font(.footnote)
                }

                Section("Logs from your watch") {
                    if receiver.logs.isEmpty {
                        Text("No logs yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(receiver.logs, id: \.self) { url in
                        ShareLink(item: url) {
                            Label(url.lastPathComponent, systemImage: "tablecells")
                                .font(.footnote)
                        }
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { receiver.logs[$0] }
                        for url in doomed { receiver.delete(url) }
                    }
                }

                Section {
                    Text("Logs contain sensitive health data. They stay on your devices unless you share them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(SafetyText.disclaimer)
                        .font(.footnote)
                }
            }
            .navigationTitle("Night Watch")
            .refreshable { receiver.refresh() }
        }
    }
}

#Preview {
    LogListView()
}
