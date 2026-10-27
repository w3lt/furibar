// Renders the Furibar panel in Demo mode to PNG files, for checking the design without earbuds.
// Usage: swift run furibar-snapshots [output-dir]   (default: build/snapshots)
// AppKit-backed controls (the gear menu, the raw-payload text field) don't render in snapshots.

import AppKit
import SwiftUI
import FuribarApp
import FuribarCore

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/snapshots")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let defaults = UserDefaults(suiteName: "furibar-snapshots")!
let manager = ConnectionManager(preferences: Preferences(defaults: defaults, arguments: ["--demo"]))
manager.start()
try await Task.sleep(for: .milliseconds(300)) // let the demo earbuds answer the read-all

@MainActor func render<V: View>(_ view: V, _ name: String, dark: Bool = false) {
    let content = view
        .background(dark ? Color(white: 0.17) : Color(white: 0.95))
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("failed: \(name)")
        return
    }
    let url = outDir.appendingPathComponent("\(name).png")
    try? png.write(to: url)
    print("wrote \(url.path)")
}

for (section, name) in [("", "panel"), ("controls", "panel-controls"), ("device", "panel-device"), ("diagnostics", "panel-diagnostics")] {
    UserDefaults.standard.set(section, forKey: "expandedSection")
    render(PanelView().environment(manager), name)
}
UserDefaults.standard.set("", forKey: "expandedSection")
render(PanelView().environment(manager), "panel-dark", dark: true)

for (status, name) in [(ConnectionManager.Status.searching, "status-searching"), (.unauthorized, "status-unauthorized")] {
    render(StatusCard(status: status, retry: {}, tryDemo: {}).padding(12).frame(width: 340), name)
}

let nearby = [
    NearbyEarbuds(id: UUID(), name: "Furina", model: Advert.furina.displayName),
    NearbyEarbuds(id: UUID(), name: "Zircon", model: "Zircon"),
]
render(StatusCard(status: .searching, nearby: nearby, retry: {}, tryDemo: {}).padding(12).frame(width: 340), "status-nearby")
