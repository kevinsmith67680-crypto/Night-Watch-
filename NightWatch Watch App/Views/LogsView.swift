import SwiftUI
import NightWatchCore

/// Lists the CSV logs on the watch and sends them to the iPhone.
struct LogsView: View {
    @ObservedObject private var transfer = PhoneTransfer.shared
    @State private var files: [LogFile] = []

    var body: some View {
        List {
            if !transfer.status.isEmpty {
                Text(transfer.status)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if files.isEmpty {
                Text("No logs yet. Every monitoring, calibration or simulation run saves one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(files) { file in
                Button {
                    transfer.send(file)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.footnote)
                        Text("\(file.sizeText) · tap to send to iPhone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { LogStore.delete(files[index]) }
                files = LogStore.list()
            }

            Text("Swipe left on a log to delete it. Logs contain sensitive health data and only leave the watch when you send them to your own iPhone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Logs")
        .onAppear { files = LogStore.list() }
    }
}
