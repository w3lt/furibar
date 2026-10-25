// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Furibar",
    platforms: [.macOS(.v14)],
    targets: [
        // Protocol, device state and session logic. No Bluetooth or UI code, so it is fully unit-testable.
        .target(name: "FuribarCore"),
        // The menu bar app: SwiftUI UI plus CoreBluetooth / IOBluetooth transports.
        .executableTarget(
            name: "Furibar",
            dependencies: ["FuribarCore"]
        ),
        .testTarget(
            name: "FuribarCoreTests",
            dependencies: ["FuribarCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
