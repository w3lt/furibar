// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Furibar",
    platforms: [.macOS(.v14)],
    targets: [
        // Protocol, device state and session logic. No Bluetooth or UI code, so it is fully unit-testable.
        .target(name: "FuribarCore"),
        // Menu bar UI, connection management and the CoreBluetooth / IOBluetooth links.
        .target(name: "FuribarApp", dependencies: ["FuribarCore"]),
        // The app entry point. scripts/build-app.sh wraps it in Furibar.app.
        .executableTarget(name: "Furibar", dependencies: ["FuribarApp"]),
        // Developer tool: renders the panel (Demo mode) to PNGs, for checking the design without hardware.
        .executableTarget(
            name: "furibar-snapshots",
            dependencies: ["FuribarApp", "FuribarCore"],
            path: "Tools/Snapshots"
        ),
        .testTarget(name: "FuribarCoreTests", dependencies: ["FuribarCore"]),
    ],
    swiftLanguageModes: [.v6]
)
