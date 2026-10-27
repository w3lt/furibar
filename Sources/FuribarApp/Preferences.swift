import Foundation
import Observation
import ServiceManagement

/// User settings for the app itself (not the earbuds). Stored in UserDefaults, which stays on this Mac.
@MainActor
@Observable
public final class Preferences {
    public enum Connection: String, CaseIterable, Identifiable, Sendable {
        case automatic, classic, ble
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .automatic: "Automatic"
            case .classic: "Classic Bluetooth only"
            case .ble: "Bluetooth LE only"
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var connection: Connection {
        didSet { defaults.set(connection.rawValue, forKey: Keys.connection) }
    }

    public var showBatteryInMenuBar: Bool {
        didSet { defaults.set(showBatteryInMenuBar, forKey: Keys.showBattery) }
    }

    /// Only for this run, so a relaunch never shows pretend battery levels by surprise.
    /// The `--demo` launch argument turns it on at startup.
    public var demoMode: Bool

    /// Bluetooth LE earbuds the user picked from the nearby list (CoreBluetooth identifiers,
    /// which are specific to this Mac). Furibar reconnects to these without asking again.
    public private(set) var chosenEarbuds: Set<String> {
        didSet { defaults.set(Array(chosenEarbuds).sorted(), forKey: Keys.chosenEarbuds) }
    }

    public private(set) var launchAtLogin: Bool

    public init(defaults: UserDefaults = .standard, arguments: [String] = CommandLine.arguments) {
        self.defaults = defaults
        connection = Connection(rawValue: defaults.string(forKey: Keys.connection) ?? "") ?? .automatic
        showBatteryInMenuBar = defaults.object(forKey: Keys.showBattery) as? Bool ?? true
        demoMode = arguments.contains("--demo")
        chosenEarbuds = Set(defaults.stringArray(forKey: Keys.chosenEarbuds) ?? [])
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    public func choose(_ earbuds: UUID) {
        chosenEarbuds.insert(earbuds.uuidString)
    }

    public func forgetChosenEarbuds() {
        chosenEarbuds.removeAll()
    }

    public func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Registration can fail for an app outside /Applications; the toggle just reflects reality.
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private enum Keys {
        static let connection = "connection"
        static let showBattery = "showBatteryInMenuBar"
        static let chosenEarbuds = "chosenEarbuds"
    }
}
