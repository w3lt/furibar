/// Recognises Roseselsa earbuds from BLE manufacturer data.
///
/// RoseLink matches the first bytes of the manufacturer data (company ID included) against
/// a per-model prefix list. Only models on the RS Common V2 protocol are listed here,
/// because that is the protocol Furibar speaks. Furina is the one this app is built for;
/// the others share the protocol but are untested.

public struct EarbudModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let prefixes: [[UInt8]]

    public var isFurina: Bool { id == "furina" }
}

public enum Advert {
    public enum Kind: Equatable, Sendable { case earbuds, microphone, headphones }

    public struct Info: Equatable, Sendable {
        public let model: EarbudModel
        public let kind: Kind
        public let hasClassicBluetooth: Bool
        /// Present when the advert is long enough (17+ bytes).
        public let macAddress: String?
    }

    public static func identify(manufacturerData d: [UInt8]) -> Info? {
        guard let model = model(for: d) else { return nil }
        let kind: Kind = d.count > 6 ? (d[6] == 0x01 ? .earbuds : d[6] == 0x04 ? .microphone : .headphones) : .earbuds
        let classic = d.count > 7 && d[7] == 0x01
        let mac = d.count >= 17 ? d[11...16].map(Hex.byte).joined(separator: ":") : nil
        return Info(model: model, kind: kind, hasClassicBluetooth: classic, macAddress: mac)
    }

    /// Longest prefix wins, mirroring RoseLink's 6 → 4 → 3 byte comparison.
    static func model(for d: [UInt8]) -> EarbudModel? {
        for length in [6, 4, 3] where d.count >= length {
            let head = Array(d.prefix(length))
            if let hit = models.first(where: { $0.prefixes.contains(head) }) { return hit }
        }
        return nil
    }

    public static let furina = EarbudModel(id: "furina", displayName: "Furina · Endless Solo", prefixes: [[0x0B, 0x11, 0x0A, 0x0C]])

    /// RS Common V2 models from RoseLink's device table.
    public static let models: [EarbudModel] = [
        furina,
        m("astro_x", "Astro X", "0b0e0a0b"),
        m("budsfeel_mk2", "Budsfeel MK2", "0b150a0b"),
        m("ceramics_mk2", "Ceramics MK2", "0b0e0a0c"),
        m("ceramics_mk2_5736", "Ceramics MK2", "45d7b286"),
        m("ceramics_mk2_8912f", "Ceramics MK2", "0b0e208b"),
        m("ceramics_u", "Ceramics U", "0b0d0a0b"),
        m("ceramics_u_hsc_2710", "Ceramics U", "0b137957"),
        m("coral", "Coral", "0b0e0a0e"),
        m("earfeel_i7", "Earfeel i7", "b8e5290f"),
        m("first_angel", "First Angel", "0b0e64be"),
        m("hyacinth", "Hyacinth", "0b120a0b"),
        m("jasmine", "Jasmine", "0b0a0a11"),
        m("ky01", "KY01", "0a0b0a0d"),
        m("luminous_agumon", "Luminous Agumon", "0b0a34fd"),
        m("luminous_gabumon", "Luminous Gabumon", "0b0a2aed"),
        m("luminous_patamon", "Luminous Patamon", "0b0ae916"),
        m("luminous_tailmon", "Luminous Tailmon", "0b0a941f"),
        m("magician", "Magician", "0b0e0a0d"),
        m("mirror", "Mirror", "0b0a0a13"),
        m("moka", "Moka", "68f5b8eb"),
        m("opal", "Opal", "0b0a0a12"),
        m("openfeel_l", "Openfeel L", "45d7cbed"),
        m("openfeel_mk2", "Openfeel MK2", "0b0eb657"),
        m("speakfeel2", "Speakfeel 2", "0b0e3ce6"),
        m("speakfree", "Speakfree", "0b0f0a0b"),
        m("sportfeel_8912f", "Sportfeel", "5d2f61f0"),
        m("swift2", "Swift 2", "5999064c"),
        m("zircon", "Zircon", "0b110a0b"),
    ]

    private static func m(_ id: String, _ name: String, _ prefix: String) -> EarbudModel {
        EarbudModel(id: id, displayName: name, prefixes: [Hex.parse(prefix)!])
    }
}
