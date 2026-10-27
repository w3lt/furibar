/// Bluetooth device addresses, as macOS writes them ("aa-bb-cc-dd-ee-ff") and as Furibar
/// reads them from adverts ("AA:BB:CC:DD:EE:FF").
public enum BluetoothAddress {
    /// The six address bytes, or nil if the text isn't exactly six hex bytes.
    public static func bytes(_ text: String) -> [UInt8]? {
        let digits = text.filter { $0 != "-" && $0 != ":" && !$0.isWhitespace }
        guard digits.count == 12, let bytes = Hex.parse(digits) else { return nil }
        return bytes
    }

    /// True when an advertised address is one of `known`. Either byte order counts,
    /// because the order of the address in the advert hasn't been confirmed.
    public static func isAmong(_ advertised: String?, _ known: [String]) -> Bool {
        guard let advertised, let mac = bytes(advertised) else { return false }
        let reversed = Array(mac.reversed())
        return known.contains { other in
            guard let k = bytes(other) else { return false }
            return k == mac || k == reversed
        }
    }
}
