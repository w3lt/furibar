import CoreBluetooth
import FuribarCore
import Foundation
import Observation

/// Finds the earbuds, keeps one control link open, and reconnects when it drops.
///
/// In Automatic mode both Classic Bluetooth and Bluetooth LE are tried at once; whichever
/// opens first is used and the other stops looking.
@MainActor
@Observable
public final class ConnectionManager {
    public enum Status: Equatable, Sendable {
        case idle, bluetoothOff, unauthorized, unsupported, searching, connected
    }

    public enum Transport: String, Sendable {
        case classic = "Classic Bluetooth"
        case ble = "Bluetooth LE"
        case demo = "Demo"
    }

    public private(set) var status: Status = .idle
    public private(set) var session: DeviceSession?
    public private(set) var transport: Transport?
    public private(set) var deviceName = ""
    public private(set) var model: EarbudModel = Advert.furina
    /// Earbuds seen over Bluetooth LE that aren't paired with this Mac, for the user to pick from.
    public private(set) var nearby: [NearbyEarbuds] = []
    /// What happened while finding and connecting, for Diagnostics. Kept across reconnects.
    public private(set) var events: [LogEntry] = []
    /// Traffic from the last session, kept after it ends so it can still be copied.
    public private(set) var previousTraffic: [LogEntry] = []

    public let preferences: Preferences

    @ObservationIgnored private var ble: BLEConnector?
    @ObservationIgnored private var classic: ClassicConnector?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    private static let maxEvents = 200

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    public func start() {
        if preferences.demoMode {
            note("Demo mode: using pretend earbuds")
            attach(DemoEarbuds(), name: "Demo earbuds", model: Advert.furina, via: .demo)
        } else {
            note("Looking for earbuds (\(preferences.connection.title))")
            search()
        }
    }

    /// Drops the current link and starts over (after a settings change, or from the Reconnect button).
    public func restart() {
        dropSession()
        ble?.stop()
        classic?.stop()
        nearby = []
        status = .idle
        start()
    }

    public func setConnection(_ connection: Preferences.Connection) {
        guard connection != preferences.connection else { return }
        preferences.connection = connection
        restart()
    }

    public func setDemoMode(_ on: Bool) {
        guard on != preferences.demoMode else { return }
        preferences.demoMode = on
        restart()
    }

    /// Connects to earbuds from `nearby` and remembers the choice.
    public func connect(to earbuds: NearbyEarbuds) {
        note("You chose \(earbuds.name)")
        preferences.choose(earbuds.id)
        ble?.chosen = preferences.chosenEarbuds
        ble?.connect(to: earbuds.id)
    }

    public func forgetChosenEarbuds() {
        preferences.forgetChosenEarbuds()
        note("Forgot the earbuds chosen before")
        restart()
    }

    /// Sends a change. Failures show up as `session.lastError`.
    public func apply(_ change: SettingChange) {
        guard let session else { return }
        Task { try? await session.apply(change) }
    }

    /// Cheap refresh for when the panel opens.
    public func refreshQuickState() {
        session?.refresh([.battery, .noiseMode])
    }

    // MARK: - Searching

    private func search() {
        if ble == nil {
            // Creating the central manager is what triggers the Bluetooth permission prompt,
            // so it only happens once the user actually wants a real connection.
            let connector = BLEConnector()
            connector.onEvent = { [weak self] in self?.handle($0) }
            ble = connector
        }
        ble?.chosen = preferences.chosenEarbuds
        if classic == nil {
            let connector = ClassicConnector()
            connector.onEvent = { [weak self] in self?.handle($0) }
            classic = connector
        }
        updateStatus(for: ble?.state ?? .unknown)
        beginSearchIfPossible()
    }

    private func beginSearchIfPossible() {
        guard !preferences.demoMode, session == nil, let ble, ble.state == .poweredOn else { return }
        status = .searching
        if preferences.connection != .ble { classic?.start() }
        if preferences.connection != .classic { ble.start() }
    }

    private func handle(_ event: BLEConnector.Event) {
        switch event {
        case .state(let state):
            guard transport != .demo else { return }
            note("Bluetooth: \(Self.describe(state))")
            if state != .poweredOn {
                dropSession()
                classic?.stop()
            }
            updateStatus(for: state)
            beginSearchIfPossible()
        case .ready(let link, let name, let model):
            attach(link, name: name, model: model ?? Advert.furina, via: .ble)
        case .lost:
            if transport == .ble { linkLost() }
        case .nearby(let list):
            nearby = list
        case .note(let text):
            note("LE · \(text)")
        }
    }

    private func handle(_ event: ClassicConnector.Event) {
        switch event {
        case .ready(let link, let name):
            attach(link, name: name, model: Advert.furina, via: .classic)
        case .lost:
            if transport == .classic { linkLost() }
        case .note(let text):
            note("Classic · \(text)")
        }
    }

    private func updateStatus(for state: CBManagerState) {
        switch state {
        case .poweredOff: status = .bluetoothOff
        case .unauthorized: status = .unauthorized
        case .unsupported: status = .unsupported
        case .poweredOn: if session == nil { status = .searching }
        default: if session == nil { status = .idle } // resetting or not known yet
        }
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "on"
        case .poweredOff: "off"
        case .unauthorized: "not allowed for Furibar"
        case .unsupported: "not supported"
        case .resetting: "resetting"
        default: "starting"
        }
    }

    // MARK: - Session lifecycle

    private func attach(_ link: ByteLink, name: String, model: EarbudModel, via: Transport) {
        guard session == nil else { return } // the first link to open wins
        if via != .ble { ble?.stop() }
        if via != .classic { classic?.stop() }
        let newSession = DeviceSession(link: link)
        session = newSession
        transport = via
        deviceName = name
        self.model = model
        nearby = []
        status = .connected
        note("Connected to \(name) over \(via.rawValue)")
        newSession.start()
        startBatteryPolling()
    }

    private func linkLost() {
        note("Lost the connection to \(deviceName)")
        dropSession()
        status = .searching
        beginSearchIfPossible()
    }

    private func dropSession() {
        pollTask?.cancel()
        pollTask = nil
        if let session { previousTraffic = session.log }
        session = nil
        transport = nil
    }

    private func startBatteryPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.session?.refresh([.battery])
            }
        }
    }

    private func note(_ text: String) {
        events.append(LogEntry(direction: .note, text: text))
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
    }
}
