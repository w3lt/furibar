/// A setting or command "type" byte in the RS Common V2 protocol.
///
/// The same byte is used three ways: the host writes `type · value`, reads with `FA · type…`,
/// and the earbuds report `type · len · value` records back. Any byte is allowed so that
/// unknown types the earbuds report can still be stored and shown in Diagnostics.
public struct SettingType: RawRepresentable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }

    public static func < (a: SettingType, b: SettingType) -> Bool { a.rawValue < b.rawValue }
    public var description: String { Hex.byte(rawValue) }

    public static let keyMapping = SettingType(0x01)
    public static let touchControl = SettingType(0x07)
    public static let inEarDetection = SettingType(0x08)
    public static let noiseMode = SettingType(0x09)
    public static let battery = SettingType(0x0C)
    public static let firmwareVersion = SettingType(0x0D)
    public static let gameMode = SettingType(0x0E)
    public static let eqPreset = SettingType(0x2A)
    public static let codec = SettingType(0x2B)
    public static let ancLevel = SettingType(0x2C)
    public static let transparencyLevel = SettingType(0x2D)
    public static let promptVolume = SettingType(0x2E)
    public static let findDevice = SettingType(0x2F)
    public static let promptLanguage = SettingType(0x31)
    public static let multipoint = SettingType(0x32)
    public static let spatialAudio = SettingType(0x33)
    public static let earbudMAC = SettingType(0x34)
    public static let ancList = SettingType(0x36)
    public static let gyroscopeMode = SettingType(0x37)
    public static let spatialMode = SettingType(0x38)
    public static let headMovementMode = SettingType(0x39)
    public static let earAdaptive = SettingType(0x3A)
    public static let tapControl = SettingType(0x3B)
    public static let tapKeyMapping = SettingType(0x3C)
    public static let spatialMusicMode = SettingType(0x3D)
    public static let customEQ = SettingType(0x3E)
    public static let dongleFirmware = SettingType(0x3F)
    public static let gainLevel = SettingType(0x45)
    public static let hearingProtection = SettingType(0x46)
    public static let micModeOrExtendedFirmware = SettingType(0x49)
    public static let read = SettingType(0xFA)
    public static let ack = SettingType(0xFE)

    /// What RoseLink reads right after connecting (`getInfo`). It includes 0x12,
    /// which RoseLink itself has no handler for.
    public static let connectReadAll: [SettingType] = [
        0x01, 0x07, 0x08, 0x09, 0x0C, 0x0D, 0x0E, 0x12, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x31,
        0x32, 0x33, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3F, 0x45, 0x46, 0x49,
    ].map { SettingType($0) }

    /// Human-readable name for Diagnostics.
    public var name: String {
        switch self {
        case .keyMapping: "Key mapping"
        case .touchControl: "Touch controls"
        case .inEarDetection: "In-ear detection"
        case .noiseMode: "Noise mode"
        case .battery: "Battery"
        case .firmwareVersion: "Firmware version"
        case .gameMode: "Game mode"
        case .eqPreset: "EQ preset"
        case .codec: "Codec"
        case .ancLevel: "ANC level"
        case .transparencyLevel: "Transparency level"
        case .promptVolume: "Prompt volume"
        case .findDevice: "Find device"
        case .promptLanguage: "Prompt language"
        case .multipoint: "Multipoint"
        case .spatialAudio: "Spatial audio"
        case .earbudMAC: "Earbud MAC"
        case .ancList: "ANC list"
        case .gyroscopeMode: "Gyroscope mode"
        case .spatialMode: "Spatial mode"
        case .headMovementMode: "Head-movement mode"
        case .earAdaptive: "Ear-adaptive mode"
        case .tapControl: "Tap control"
        case .tapKeyMapping: "Tap key mapping"
        case .spatialMusicMode: "Spatial music mode"
        case .customEQ: "Custom EQ"
        case .dongleFirmware: "Dongle firmware"
        case .gainLevel: "Gain level"
        case .hearingProtection: "Hearing protection"
        case .micModeOrExtendedFirmware: "Mic mode / extended firmware"
        case .read: "Read request"
        case .ack: "ACK"
        default: "Type \(Hex.byte(rawValue))"
        }
    }
}

/// Builders for host → earbuds payloads (the part inside the frame).
public enum Payload {
    /// Write a setting: `type · value…`.
    public static func write(_ type: SettingType, _ value: [UInt8]) -> [UInt8] {
        [type.rawValue] + value
    }

    /// Ask the earbuds to report settings: `FA · type…`.
    public static func read(_ types: [SettingType]) -> [UInt8] {
        [SettingType.read.rawValue] + types.map(\.rawValue)
    }
}
