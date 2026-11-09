// swift-tools-version:5.9
//
// NightWatchCore holds ALL of Night Watch's logic: feature extraction,
// filters, risk rules, logging and the simulator.
//
// It deliberately uses only plain Swift + Foundation (no HealthKit, no
// CoreMotion, no SwiftUI). That means:
//   • its tests run on your Mac in seconds:  cd NightWatchCore && swift test
//   • the simulator and the real sensors feed exactly the same code.

import PackageDescription

let package = Package(
    name: "NightWatchCore",
    platforms: [
        .watchOS("11.0"),
        .iOS("18.0"),
        .macOS("14.0"),   // only so `swift test` can run on your Mac
    ],
    products: [
        .library(name: "NightWatchCore", targets: ["NightWatchCore"]),
    ],
    targets: [
        .target(name: "NightWatchCore"),
        .testTarget(name: "NightWatchCoreTests", dependencies: ["NightWatchCore"]),
    ]
)
