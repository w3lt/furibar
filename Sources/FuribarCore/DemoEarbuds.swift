/// A pretend pair of Furina earbuds that speaks RS Common V2. Used by Demo mode, so the
/// app can be tried without hardware, and by the tests as a realistic far end.
@MainActor
public final class DemoEarbuds: ByteLink {
    public var onReceive: (@MainActor ([UInt8]) -> Void)?

    /// What the pretend earbuds currently hold.
    public private(set) var settings: [SettingType: [UInt8]] = [
        .touchControl: [0x00],
        .inEarDetection: [0x00],
        .noiseMode: [0x01],
        .battery: [0x52, 0x4F, 0xC0], // 82 %, 79 %, case 64 % charging
        .firmwareVersion: Array("1.0.8".utf8),
        .gameMode: [0x00],
        .eqPreset: [0x00],
        .codec: [0x00],
        .ancLevel: [0x02],
        .transparencyLevel: [0x01],
        .promptVolume: [0x08],
        .promptLanguage: [0x01],
        .multipoint: [0x01],
        .spatialAudio: [0x00],
    ]

    /// Settings these earbuds refuse to change (answered with "not supported").
    public var rejected: Set<SettingType> = []

    public init() {}

    public func send(_ bytes: [UInt8]) {
        guard let frame = HostFrame.parse(bytes), let first = frame.payload.first else { return }
        let reply: [LTV]
        if first == SettingType.read.rawValue {
            reply = frame.payload.dropFirst().compactMap { t in
                settings[SettingType(t)].map { LTV(type: t, value: $0) }
            }
        } else {
            let type = SettingType(first)
            let value = Array(frame.payload.dropFirst())
            if rejected.contains(type) {
                reply = [LTV(type: SettingType.ack.rawValue, value: [frame.seq, AckStatus.notSupported.rawValue])]
            } else {
                if type != .findDevice { settings[type] = value }
                reply = [LTV(type: SettingType.ack.rawValue, value: [frame.seq, AckStatus.success.rawValue])]
            }
        }
        let out = InboundFrame.encode(seq: frame.seq, records: reply)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            self?.onReceive?(out)
        }
    }
}
