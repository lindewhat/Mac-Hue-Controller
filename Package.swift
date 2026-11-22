// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacHueControl",
    platforms: [.macOS(.v15)],
    targets: [
        // All Hue logic lives here so it can be tested without the app: finding and pairing the bridge,
        // talking to it, live updates, colour maths. No UI.
        .target(name: "HueKit"),
        // The menu bar app itself (SwiftUI).
        .executableTarget(name: "MacHueControl", dependencies: ["HueKit"]),
        .testTarget(name: "HueKitTests", dependencies: ["HueKit"]),
    ]
)
