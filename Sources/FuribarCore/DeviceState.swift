/// Everything the earbuds have reported, keyed by type byte, with typed accessors on top.
public struct DeviceState: Equatable, Sendable {
    public private(set) var raw: [SettingType: [UInt8]] = [:]

    public init() {}

    public mutating func apply(_ record: LTV) {
        let type = SettingType(record.type)
        guard type != .ack, type != .read else { return }
        raw[type] = record.value
    }

    /// Puts back a value saved before an optimistic change (nil = it was never reported).
    public mutating func restore(_ type: SettingType, _ value: [UInt8]?) {
        raw[type] = value
    }

    /// A setting counts as supported once the earbuds report a non-empty value for it.
    public func supports(_ type: SettingType) -> Bool {
        guard let v = raw[type] else { return false }
        return !v.isEmpty
    }

    private func firstByte(_ type: SettingType) -> UInt8? { raw[type]?.first }

    private func flag(_ type: SettingType, onValue: UInt8) -> Bool? {
        firstByte(type).map { $0 == onValue }
    }

    public var noiseMode: NoiseMode? { firstByte(.noiseMode).flatMap(NoiseMode.init(rawValue:)) }
    public var gameMode: Bool? { flag(.gameMode, onValue: 0x01) }
    public var touchControl: Bool? { flag(.touchControl, onValue: 0x00) }
    public var inEarDetection: Bool? { flag(.inEarDetection, onValue: 0x00) }
    public var eqPreset: EQPreset? { firstByte(.eqPreset).flatMap(EQPreset.init(rawValue:)) }
    public var codec: Codec? { firstByte(.codec).flatMap(Codec.init(rawValue:)) }
    public var ancLevel: UInt8? { firstByte(.ancLevel) }
    public var transparencyLevel: UInt8? { firstByte(.transparencyLevel) }
    public var promptVolume: UInt8? { firstByte(.promptVolume) }
    public var promptLanguage: PromptLanguage? { firstByte(.promptLanguage).flatMap(PromptLanguage.init(rawValue:)) }
    public var multipoint: Bool? { flag(.multipoint, onValue: 0x01) }
    public var spatialAudio: Bool? { flag(.spatialAudio, onValue: 0x01) }
    public var spatialMode: SpatialMode? { firstByte(.spatialMode).flatMap(SpatialMode.init(rawValue:)) }
    public var spatialMusicMode: SpatialMusicMode? { firstByte(.spatialMusicMode).flatMap(SpatialMusicMode.init(rawValue:)) }
    public var earAdaptive: Bool? { flag(.earAdaptive, onValue: 0x01) }
    public var tapControl: Bool? { flag(.tapControl, onValue: 0x01) }
    public var hearingProtection: UInt8? { firstByte(.hearingProtection) }

    public var battery: Battery? {
        guard let v = raw[.battery], !v.isEmpty else { return nil }
        return Battery(bytes: v)
    }

    /// Printable ASCII is shown as is; otherwise bytes are joined with dots (assumed layout).
    public var firmwareVersion: String? {
        guard let v = raw[.firmwareVersion], !v.isEmpty else { return nil }
        if v.allSatisfy({ (0x20...0x7E).contains($0) }) {
            return String(decoding: v, as: UTF8.self)
        }
        return v.map { String($0) }.joined(separator: ".")
    }
}
