/// Typed values for the settings Furibar can show and change.
/// Byte values come from the RoseLink protocol report. Where the report gives no layout,
/// the parsing is a best guess and says so; Diagnostics always shows the raw bytes.

public enum NoiseMode: UInt8, CaseIterable, Sendable, Identifiable {
    case noiseCancelling = 0x01
    case off = 0x02
    case transparency = 0x03
    case wind = 0x04
    case auto = 0x05
    case deep = 0x06
    case autoDynamic = 0x07

    public var id: UInt8 { rawValue }

    /// The three modes every RoseLink earbud with noise control is expected to have.
    public static let primary: [NoiseMode] = [.noiseCancelling, .off, .transparency]
    public static let extra: [NoiseMode] = [.wind, .auto, .deep, .autoDynamic]

    public var title: String {
        switch self {
        case .noiseCancelling: "Noise Cancelling"
        case .off: "Off"
        case .transparency: "Transparency"
        case .wind: "Wind"
        case .auto: "Adaptive"
        case .deep: "Deep ANC"
        case .autoDynamic: "Auto Dynamic"
        }
    }

    public var shortTitle: String {
        switch self {
        case .noiseCancelling: "Cancel"
        case .transparency: "Aware"
        default: title
        }
    }
}

public enum EQPreset: Hashable, Sendable, Identifiable {
    case hifi, pop, rock, light, custom, bassPlus, eap
    case game(Int) // 1...5

    public var id: UInt8 { rawValue }

    public static let standard: [EQPreset] = [.hifi, .pop, .rock, .light, .bassPlus, .eap]

    public init?(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .hifi
        case 0x01: self = .pop
        case 0x02: self = .rock
        case 0x03: self = .light
        case 0x04: self = .custom
        case 0x05: self = .bassPlus
        case 0x06: self = .eap
        case 0xA0...0xA4: self = .game(Int(rawValue - 0xA0) + 1)
        default: return nil
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .hifi: 0x00
        case .pop: 0x01
        case .rock: 0x02
        case .light: 0x03
        case .custom: 0x04
        case .bassPlus: 0x05
        case .eap: 0x06
        case .game(let n): 0xA0 + UInt8(clamping: max(1, min(5, n)) - 1)
        }
    }

    public var title: String {
        switch self {
        case .hifi: "Hi-Fi"
        case .pop: "Pop"
        case .rock: "Rock"
        case .light: "Light"
        case .custom: "Custom"
        case .bassPlus: "Bass+"
        case .eap: "EAP"
        case .game(let n): "Game \(n)"
        }
    }
}

public enum Codec: UInt8, CaseIterable, Sendable {
    case aacSBC = 0x00, ldac, lhdc, lc3, aptX, aptXHD, aptXAdaptive

    public var title: String {
        switch self {
        case .aacSBC: "AAC / SBC"
        case .ldac: "LDAC"
        case .lhdc: "LHDC"
        case .lc3: "LC3"
        case .aptX: "aptX"
        case .aptXHD: "aptX HD"
        case .aptXAdaptive: "aptX Adaptive"
        }
    }
}

public enum PromptLanguage: UInt8, CaseIterable, Sendable, Identifiable {
    case chinese = 0x00
    case english = 0x01

    public var id: UInt8 { rawValue }
    public var title: String { self == .chinese ? "Chinese" : "English" }
}

public enum SpatialMode: UInt8, CaseIterable, Sendable, Identifiable {
    case off = 0x00, headTracked, fixed

    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .off: "Off"
        case .headTracked: "Head tracked"
        case .fixed: "Fixed"
        }
    }
}

public enum SpatialMusicMode: UInt8, CaseIterable, Sendable, Identifiable {
    case tv = 0x00, music, movie, game

    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .tv: "TV"
        case .music: "Music"
        case .movie: "Movie"
        case .game: "Game"
        }
    }
}

public struct BatteryLevel: Equatable, Sendable {
    public let percent: Int
    public let charging: Bool
    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }

    /// Assumed encoding (not confirmed by the report): low 7 bits = percent,
    /// high bit = charging, FF = not available (e.g. bud in a closed case).
    init?(byte: UInt8) {
        guard byte != 0xFF else { return nil }
        let percent = Int(byte & 0x7F)
        guard percent <= 100 else { return nil }
        self.init(percent: percent, charging: byte & 0x80 != 0)
    }
}

public struct Battery: Equatable, Sendable {
    public let left: BatteryLevel?
    public let right: BatteryLevel?
    public let chargingCase: BatteryLevel?

    /// Assumed order: left, right, case.
    init(bytes: [UInt8]) {
        func level(_ i: Int) -> BatteryLevel? { i < bytes.count ? BatteryLevel(byte: bytes[i]) : nil }
        left = level(0)
        right = level(1)
        chargingCase = level(2)
    }

    /// Lowest earbud level, for the menu bar.
    public var lowestBud: BatteryLevel? {
        [left, right].compactMap { $0 }.min { $0.percent < $1.percent }
    }
}

/// A change the user asks for, encoded as the record the earbuds expect.
/// Which earbud plays the find-me tone. *Assumed:* 01 left, 02 right; 04 stops (from the report).
public enum FindTarget: UInt8, Sendable {
    case left = 0x01
    case right = 0x02
    case stop = 0x04
}

public enum SettingChange: Sendable, Equatable {
    case noiseMode(NoiseMode)
    case gameMode(Bool)
    case touchControl(Bool)
    case inEarDetection(Bool)
    case eqPreset(EQPreset)
    case ancLevel(UInt8)
    case transparencyLevel(UInt8)
    case promptVolume(UInt8)
    case promptLanguage(PromptLanguage)
    case multipoint(Bool)
    case spatialAudio(Bool)
    case spatialMode(SpatialMode)
    case spatialMusicMode(SpatialMusicMode)
    case earAdaptive(Bool)
    case tapControl(Bool)
    case hearingProtection(UInt8)
    case findDevice(FindTarget)
    /// Anything else, for the Diagnostics raw sender.
    case raw(SettingType, [UInt8])

    public var record: LTV {
        let (type, value) = typeAndValue
        return LTV(type: type.rawValue, value: value)
    }

    public var type: SettingType { typeAndValue.0 }

    /// False for one-off commands (find my earbuds, raw writes), which don't change a stored setting.
    public var isSetting: Bool {
        switch self {
        case .findDevice, .raw: false
        default: true
        }
    }

    private var typeAndValue: (SettingType, [UInt8]) {
        switch self {
        case .noiseMode(let m): (.noiseMode, [m.rawValue])
        case .gameMode(let on): (.gameMode, [on ? 0x01 : 0x00])
        // RoseLink uses 00 = on for these two.
        case .touchControl(let on): (.touchControl, [on ? 0x00 : 0x01])
        case .inEarDetection(let on): (.inEarDetection, [on ? 0x00 : 0x01])
        case .eqPreset(let p): (.eqPreset, [p.rawValue])
        case .ancLevel(let l): (.ancLevel, [l])
        case .transparencyLevel(let l): (.transparencyLevel, [l])
        case .promptVolume(let l): (.promptVolume, [l])
        case .promptLanguage(let lang): (.promptLanguage, [lang.rawValue])
        case .multipoint(let on): (.multipoint, [on ? 0x01 : 0x00])
        case .spatialAudio(let on): (.spatialAudio, [on ? 0x01 : 0x00])
        case .spatialMode(let m): (.spatialMode, [m.rawValue])
        case .spatialMusicMode(let m): (.spatialMusicMode, [m.rawValue])
        case .earAdaptive(let on): (.earAdaptive, [on ? 0x01 : 0x00])
        case .tapControl(let on): (.tapControl, [on ? 0x01 : 0x00])
        case .hearingProtection(let l): (.hearingProtection, [l])
        case .findDevice(let t): (.findDevice, [t.rawValue])
        case .raw(let t, let v): (t, v)
        }
    }
}
