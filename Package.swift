// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ThingsBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: models, Things client, filtering. No UI, fully unit-testable.
        .target(name: "ThingsBarCore"),
        // The menu bar app itself (SwiftUI MenuBarExtra).
        .executableTarget(name: "ThingsBar", dependencies: ["ThingsBarCore"]),
        .testTarget(name: "ThingsBarCoreTests", dependencies: ["ThingsBarCore"]),
    ]
)
