import Foundation
import WatchConnectivity

/// Sends CSV logs from the watch to the Night Watch iPhone app.
///
/// WatchConnectivity sends the file directly between your own paired watch and
/// iPhone. Nothing goes to any Night Watch server; there isn't one.
@MainActor
final class PhoneTransfer: NSObject, ObservableObject {
    static let shared = PhoneTransfer()

    @Published private(set) var status = ""

    /// Call once when the app starts.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ file: LogFile) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            status = "Still connecting to your iPhone. Try again in a moment."
            activate()
            return
        }
        guard session.isCompanionAppInstalled else {
            status = "Install the Night Watch iPhone app first (run the NightWatch scheme on your iPhone in Xcode)."
            return
        }
        session.transferFile(file.url, metadata: ["name": file.name])
        status = "Sending \(file.name)… Open Night Watch on your iPhone to receive it."
    }
}

extension PhoneTransfer: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        let message: String
        if let error {
            message = "Couldn't send \(name): \(error.localizedDescription)"
        } else {
            message = "Sent \(name) to your iPhone."
        }
        Task { @MainActor in
            PhoneTransfer.shared.status = message
        }
    }
}
