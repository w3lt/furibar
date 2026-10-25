import CoreBluetooth
import FuribarCore
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

    public let preferences: Preferences

    @ObservationIgnored private var ble: BLEConnector?
    @ObservationIgnored private var classic: ClassicConnector?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    public func start() {
        if preferences.demoMode {
            attach(DemoEarbuds(), name: "Demo earbuds", model: Advert.furina, via: .demo)
        } else {
            search()
        }
    }

    /// Drops the current link and starts over (after a settings change, or from the Reconnect button).
    public func restart() {
        dropSession()
        ble?.stop()
        classic?.stop()
        status = .idle
        start()
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
        }
    }

    private func handle(_ event: ClassicConnector.Event) {
        switch event {
        case .ready(let link, let name):
            attach(link, name: name, model: Advert.furina, via: .classic)
        case .lost:
            if transport == .classic { linkLost() }
        }
    }

    private func updateStatus(for state: CBManagerState) {
        switch state {
        case .poweredOff: status = .bluetoothOff
        case .unauthorized: status = .unauthorized
        case .unsupported: status = .unsupported
        case .poweredOn: if session == nil { status = .searching }
        default: break
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
        status = .connected
        newSession.start()
        startBatteryPolling()
    }

    private func linkLost() {
        dropSession()
        status = .searching
        beginSearchIfPossible()
    }

    private func dropSession() {
        pollTask?.cancel()
        pollTask = nil
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
}
