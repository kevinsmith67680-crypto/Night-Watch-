import SwiftUI
import UIKit

/// The iPhone companion app. Its only job (from Step 7) is to receive CSV logs
/// from the watch so you can open or share them on your phone.
@main
struct NightWatchPhoneApp: App {
    init() {
        // Screen titles in the icon's green (see Theme.swift). The app starts
        // on the main thread, which UIKit requires.
        MainActor.assumeIsolated {
            let green = UIColor(named: "BrandGreen") ?? .systemGreen
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.titleTextAttributes = [.foregroundColor: green]
            appearance.largeTitleTextAttributes = [.foregroundColor: green]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some Scene {
        WindowGroup {
            LogListView()
        }
    }
}
