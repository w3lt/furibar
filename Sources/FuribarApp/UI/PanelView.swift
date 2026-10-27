import AppKit
import SwiftUI
import FuribarCore

/// The window that drops down from the menu bar icon.
public struct PanelView: View {
    @Environment(ConnectionManager.self) private var manager
    @AppStorage("expandedSection") private var expanded = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            HeaderView(
                title: manager.status == .connected ? manager.model.displayName : Advert.furina.displayName,
                subtitle: subtitle,
                connected: manager.status == .connected,
                battery: manager.session?.state.battery
            )

            if let error = manager.session?.lastError {
                Banner(text: error) { manager.session?.clearError() }
            }

            if manager.status == .connected, let session = manager.session {
                ConnectedContent(session: session, expanded: $expanded)
            } else {
                StatusCard(
                    status: manager.status,
                    nearby: manager.nearby,
                    retry: { manager.restart() },
                    tryDemo: { manager.setDemoMode(true) },
                    connect: { manager.connect(to: $0) }
                )
                FoldSection(id: "diagnostics", title: "Diagnostics", symbol: "waveform.circle", expanded: $expanded) {
                    DiagnosticsContent(session: nil)
                }
            }

            FooterView()
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { manager.panelOpened() }
        // The menu bar window is kept around between openings, so onAppear may only fire once.
        // It becomes key each time it opens, and it's the app's only window.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            manager.panelOpened()
        }
    }

    private var subtitle: String {
        switch manager.status {
        case .connected:
            let via = manager.transport.map { " · \($0.rawValue)" } ?? ""
            return "Connected\(via)"
        case .searching: return "Searching…"
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Needs Bluetooth permission"
        case .unsupported: return "Bluetooth unavailable"
        case .idle: return "Starting…"
        }
    }
}

struct HeaderView: View {
    let title: String
    let subtitle: String
    let connected: Bool
    let battery: Battery?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.accent)
                    Circle().strokeBorder(Theme.gold.opacity(0.85), lineWidth: 1.5)
                    Image(systemName: connected ? "earbuds" : "earbuds.case")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(connected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if let battery, battery.left != nil || battery.right != nil || battery.chargingCase != nil {
                HStack(spacing: 6) {
                    if let l = battery.left { BatteryPill(label: "L", level: l) }
                    if let r = battery.right { BatteryPill(label: "R", level: r) }
                    if let c = battery.chargingCase { BatteryPill(label: "CASE", level: c) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Shown when there is no connection: what's wrong and what to do about it.
public struct StatusCard: View {
    let status: ConnectionManager.Status
    let nearby: [NearbyEarbuds]
    let retry: () -> Void
    let tryDemo: () -> Void
    let connect: (NearbyEarbuds) -> Void

    public init(status: ConnectionManager.Status, nearby: [NearbyEarbuds] = [],
                retry: @escaping () -> Void, tryDemo: @escaping () -> Void,
                connect: @escaping (NearbyEarbuds) -> Void = { _ in }) {
        self.status = status
        self.nearby = nearby
        self.retry = retry
        self.tryDemo = tryDemo
        self.connect = connect
    }

    public var body: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.hydro)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                if let settings = settingsLink {
                    Chip(title: "Open Settings", symbol: "gearshape", selected: true) {
                        NSWorkspace.shared.open(settings)
                    }
                } else {
                    Chip(title: "Try Again", symbol: "arrow.clockwise", selected: true, action: retry)
                }
                Chip(title: "Try Demo", symbol: "sparkles", selected: false, action: tryDemo)
            }

            if status == .searching, !nearby.isEmpty {
                Divider().padding(.vertical, 2)
                CardTitle(text: "Nearby")
                Text("These aren't paired with this Mac, so Furibar won't connect to them on its own. Connect only to your own earbuds.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(nearby) { earbuds in
                    HStack(spacing: 8) {
                        Image(systemName: "earbuds")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.hydro)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(earbuds.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(earbuds.model).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Chip(title: "Connect", selected: false) { connect(earbuds) }
                            .frame(width: 80)
                    }
                }
            }
        }
    }

    private var symbol: String {
        switch status {
        case .bluetoothOff, .unsupported: "antenna.radiowaves.left.and.right.slash"
        case .unauthorized: "lock.shield"
        default: "earbuds.case"
        }
    }

    private var title: String {
        switch status {
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Furibar needs Bluetooth access"
        case .unsupported: "Bluetooth isn't available"
        default: "Looking for your earbuds"
        }
    }

    private var message: String {
        switch status {
        case .bluetoothOff: "Turn Bluetooth on to control your earbuds."
        case .unauthorized: "Allow Furibar in System Settings → Privacy & Security → Bluetooth, then try again."
        case .unsupported: "This Mac doesn't report a usable Bluetooth controller."
        default: "Take the earbuds out of the case and make sure they're connected to this Mac in Bluetooth settings. Furibar connects on its own."
        }
    }

    private var settingsLink: URL? {
        switch status {
        case .bluetoothOff: URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")
        case .unauthorized: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        default: nil
        }
    }
}

struct ConnectedContent: View {
    let session: DeviceSession
    @Binding var expanded: String
    @Environment(ConnectionManager.self) private var manager
    @State private var waitedTooLong = false

    private var state: DeviceState { session.state }

    var body: some View {
        VStack(spacing: 10) {
            if !session.hasReceivedData {
                Card {
                    HStack(spacing: 8) {
                        if !waitedTooLong { ProgressView().controlSize(.small) }
                        Text(waitedTooLong
                             ? "The earbuds haven't answered yet. Diagnostics below shows what was sent and received."
                             : "Reading settings…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .task {
                    try? await Task.sleep(for: .seconds(6))
                    waitedTooLong = true
                }
            } else {
                if state.supports(.noiseMode) { NoiseCard(state: state) }
                QuickCard(state: state)
                if state.supports(.eqPreset) { SoundCard(state: state) }
                if hasControls {
                    FoldSection(id: "controls", title: "Controls", symbol: "hand.tap", expanded: $expanded) {
                        ControlsContent(state: state)
                    }
                }
                FoldSection(id: "device", title: "Device", symbol: "earbuds", expanded: $expanded) {
                    DeviceContent(state: state)
                }
            }
            FoldSection(id: "diagnostics", title: "Diagnostics", symbol: "waveform.circle", expanded: $expanded) {
                DiagnosticsContent(session: session)
            }
        }
    }

    private var hasControls: Bool {
        state.supports(.touchControl) || state.supports(.inEarDetection) || state.supports(.tapControl)
    }
}

struct NoiseCard: View {
    let state: DeviceState
    @Environment(ConnectionManager.self) private var manager

    var body: some View {
        Card(title: "Noise control") {
            HStack(spacing: 8) {
                ForEach(NoiseMode.primary) { mode in
                    ModeTile(title: mode.title, symbol: Self.symbol(mode), selected: state.noiseMode == mode) {
                        manager.apply(.noiseMode(mode))
                    }
                }
            }

            if let current = state.noiseMode, NoiseMode.extra.contains(current) {
                InfoRow(title: "Current mode", value: current.title)
            }

            if state.noiseMode == .noiseCancelling, let level = state.ancLevel, state.supports(.ancLevel) {
                LevelRow(title: "Cancelling strength", symbol: "dial.medium", value: level) {
                    manager.apply(.ancLevel($0))
                }
            }
            if state.noiseMode == .transparency, let level = state.transparencyLevel, state.supports(.transparencyLevel) {
                LevelRow(title: "Transparency level", symbol: "dial.medium", value: level) {
                    manager.apply(.transparencyLevel($0))
                }
            }
        }
    }

    static func symbol(_ mode: NoiseMode) -> String {
        switch mode {
        case .noiseCancelling, .deep: "waveform.badge.minus"
        case .off: "circle.slash"
        case .transparency: "ear.and.waveform"
        case .wind: "wind"
        case .auto, .autoDynamic: "sparkles"
        }
    }
}

struct QuickCard: View {
    let state: DeviceState
    @Environment(ConnectionManager.self) private var manager

    var body: some View {
        let tiles = available
        if !tiles.isEmpty {
            Card(title: "Quick settings") {
                HStack(spacing: 8) {
                    ForEach(tiles, id: \.title) { tile in
                        ToggleTile(title: tile.title, symbol: tile.symbol, isOn: tile.isOn) {
                            manager.apply(tile.change(!tile.isOn))
                        }
                    }
                }
            }
        }
    }

    private struct Tile {
        let title: String
        let symbol: String
        let isOn: Bool
        let change: (Bool) -> SettingChange
    }

    private var available: [Tile] {
        var tiles: [Tile] = []
        if state.supports(.gameMode), let on = state.gameMode {
            tiles.append(Tile(title: "Game Mode", symbol: "gamecontroller.fill", isOn: on, change: SettingChange.gameMode))
        }
        if state.supports(.spatialAudio), let on = state.spatialAudio {
            tiles.append(Tile(title: "Spatial Audio", symbol: "rotate.3d", isOn: on, change: SettingChange.spatialAudio))
        }
        if tiles.count < 2, state.supports(.multipoint), let on = state.multipoint {
            tiles.append(Tile(title: "Multipoint", symbol: "person.2.wave.2", isOn: on, change: SettingChange.multipoint))
        }
        return tiles
    }
}

struct SoundCard: View {
    let state: DeviceState
    @Environment(ConnectionManager.self) private var manager

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        Card(title: "Sound") {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(presets) { preset in
                    Chip(title: preset.title, selected: state.eqPreset == preset) {
                        manager.apply(.eqPreset(preset))
                    }
                }
            }
            if let current = state.eqPreset, case .game = current {
                InfoRow(title: "Current preset", value: current.title)
            }
        }
    }

    /// The standard presets, plus Custom only when the earbuds are already on it
    /// (Furibar can't edit custom bands yet).
    private var presets: [EQPreset] {
        state.eqPreset == .custom ? EQPreset.standard + [.custom] : EQPreset.standard
    }
}

struct ControlsContent: View {
    let state: DeviceState
    @Environment(ConnectionManager.self) private var manager

    var body: some View {
        if state.supports(.touchControl), let on = state.touchControl {
            SwitchRow(title: "Touch controls", symbol: "hand.tap", detail: "Tap and hold gestures on the earbuds",
                      isOn: on) { manager.apply(.touchControl($0)) }
        }
        if state.supports(.tapControl), let on = state.tapControl {
            SwitchRow(title: "Tap control", symbol: "dot.circle.and.hand.point.up.left.fill",
                      isOn: on) { manager.apply(.tapControl($0)) }
        }
        if state.supports(.inEarDetection), let on = state.inEarDetection {
            SwitchRow(title: "In-ear detection", symbol: "ear", detail: "Pause when you take an earbud out",
                      isOn: on) { manager.apply(.inEarDetection($0)) }
        }
    }
}

struct DeviceContent: View {
    let state: DeviceState
    @Environment(ConnectionManager.self) private var manager

    var body: some View {
        if state.supports(.promptLanguage), let language = state.promptLanguage {
            HStack {
                RowLabel(title: "Voice prompts", symbol: "globe")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(PromptLanguage.allCases.reversed()) { lang in
                        Chip(title: lang.title, selected: language == lang) { manager.apply(.promptLanguage(lang)) }
                            .frame(width: 74)
                    }
                }
            }
        }
        if state.supports(.promptVolume), let volume = state.promptVolume {
            LevelRow(title: "Prompt volume", symbol: "speaker.wave.2", value: volume) { manager.apply(.promptVolume($0)) }
        }
        if state.supports(.multipoint), let on = state.multipoint {
            SwitchRow(title: "Multipoint", symbol: "person.2.wave.2", detail: "Stay connected to two devices",
                      isOn: on) { manager.apply(.multipoint($0)) }
        }
        if state.supports(.earAdaptive), let on = state.earAdaptive {
            SwitchRow(title: "Ear-adaptive sound", symbol: "ear.badge.waveform",
                      isOn: on) { manager.apply(.earAdaptive($0)) }
        }
        if state.supports(.spatialMode), let mode = state.spatialMode {
            HStack(spacing: 4) {
                ForEach(SpatialMode.allCases) { m in
                    Chip(title: m.title, selected: mode == m) { manager.apply(.spatialMode(m)) }
                }
            }
        }
        if state.supports(.hearingProtection), let level = state.hearingProtection {
            LevelRow(title: "Hearing protection", symbol: "ear.trianglebadge.exclamationmark", value: level) {
                manager.apply(.hearingProtection($0))
            }
        }

        FindEarbudsRow()

        VStack(spacing: 4) {
            if let fw = state.firmwareVersion { InfoRow(title: "Firmware", value: fw) }
            if let codec = state.codec { InfoRow(title: "Codec mode", value: codec.title) }
            if let via = manager.transport { InfoRow(title: "Connection", value: via.rawValue) }
            if !manager.deviceName.isEmpty { InfoRow(title: "Name", value: manager.deviceName) }
        }
        .padding(.top, 2)
    }
}

/// Plays a tone so a lost earbud can be found. The side bytes are a best guess (see `FindTarget`).
struct FindEarbudsRow: View {
    @Environment(ConnectionManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RowLabel(title: "Find my earbuds", symbol: "bell.and.waves.left.and.right",
                     detail: "Plays a loud tone. Take the earbuds out first.")
            HStack(spacing: 6) {
                Chip(title: "Left", symbol: "play.fill", selected: false) { manager.apply(.findDevice(.left)) }
                Chip(title: "Right", symbol: "play.fill", selected: false) { manager.apply(.findDevice(.right)) }
                Chip(title: "Stop", symbol: "stop.fill", selected: false) { manager.apply(.findDevice(.stop)) }
            }
        }
    }
}

struct FooterView: View {
    @Environment(ConnectionManager.self) private var manager

    var body: some View {
        @Bindable var prefs = manager.preferences
        HStack {
            Menu {
                Picker("Connection", selection: Binding(
                    get: { prefs.connection },
                    set: { manager.setConnection($0) }
                )) {
                    ForEach(Preferences.Connection.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show battery in menu bar", isOn: $prefs.showBatteryInMenuBar)
                Toggle("Launch at login", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.setLaunchAtLogin($0) }
                ))
                Toggle("Demo mode", isOn: Binding(
                    get: { prefs.demoMode },
                    set: { manager.setDemoMode($0) }
                ))
                Divider()
                Button("Reconnect") { manager.restart() }
                if !prefs.chosenEarbuds.isEmpty {
                    Button("Forget Chosen Earbuds") { manager.forgetChosenEarbuds() }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            Text("Offline · no data leaves this Mac")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

/// The menu bar item: an earbuds icon, optionally with the lower earbud battery level.
public struct MenuBarLabel: View {
    let manager: ConnectionManager

    public init(manager: ConnectionManager) { self.manager = manager }

    public var body: some View {
        let connected = manager.status == .connected
        HStack(spacing: 3) {
            Image(systemName: connected ? "earbuds" : "earbuds.case")
            if connected, manager.preferences.showBatteryInMenuBar,
               let level = manager.session?.state.battery?.lowestBud {
                Text("\(level.percent)%")
            }
        }
    }
}
