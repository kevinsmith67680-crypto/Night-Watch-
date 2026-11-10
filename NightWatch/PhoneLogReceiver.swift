import Foundation
import WatchConnectivity

/// Receives CSV logs sent from the watch and keeps them in the iPhone app's
/// Documents/Logs folder. Files travel directly between your own watch and
/// phone; there is no Night Watch server.
@MainActor
final class PhoneLogReceiver: NSObject, ObservableObject {
    @Published private(set) var logs: [URL] = []

    override init() {
        super.init()
        refresh()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Where received logs are kept.
    nonisolated static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        logs = urls
            .filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refresh()
    }
}

extension PhoneLogReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The incoming file is deleted as soon as this method returns, so move it now.
        let name = (file.metadata?["name"] as? String) ?? file.fileURL.lastPathComponent
        let destination = Self.folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: file.fileURL, to: destination)
        Task { @MainActor in
            self.refresh()
        }
    }
}
