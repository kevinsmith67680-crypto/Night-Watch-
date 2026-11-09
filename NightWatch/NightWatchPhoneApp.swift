import SwiftUI

/// The iPhone companion app. Its only job (from Step 7) is to receive CSV logs
/// from the watch so you can open or share them on your phone.
@main
struct NightWatchPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            LogListView()
        }
    }
}
