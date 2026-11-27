// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ThingsBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates: download, EdDSA-verify, replace and relaunch.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Pure logic: models, Things client, filtering. No UI, fully unit-testable.
        .target(name: "ThingsBarCore"),
        // The menu bar app itself (SwiftUI MenuBarExtra).
        .executableTarget(
            name: "ThingsBar",
            dependencies: ["ThingsBarCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ThingsBarCoreTests", dependencies: ["ThingsBarCore"]),
    ]
)
