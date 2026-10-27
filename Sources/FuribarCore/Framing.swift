/// RS Common V2 framing.
///
/// Host → earbuds:  `FF · SEQ · LEN · PAYLOAD · SUM · AA`
/// Earbuds → host:  `DD · SEQ · LEN · LTV records · SUM · AA`
///
/// SUM is the low byte of the sum of every byte before it. RoseLink also accepts an inbound
/// SUM that starts at byte 2, so the decoder does too.

public enum Hex {
    public static func byte(_ b: UInt8) -> String {
        let s = String(b, radix: 16, uppercase: true)
        return s.count == 1 ? "0" + s : s
    }

    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map(byte).joined(separator: " ")
    }

    /// Parses "09 01", "0901" or "09:01". Returns nil for odd length or non-hex input.
    public static func parse(_ text: String) -> [UInt8]? {
        let digits = text.filter { !$0.isWhitespace && $0 != ":" && $0 != "," }
        guard !digits.isEmpty, digits.count % 2 == 0, digits.allSatisfy(\.isHexDigit) else { return nil }
        var out: [UInt8] = []
        var i = digits.startIndex
        while i < digits.endIndex {
            let j = digits.index(i, offsetBy: 2)
            guard let b = UInt8(digits[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }
}

func checksum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
    bytes.reduce(UInt8(0)) { $0 &+ $1 }
}

enum FrameByte {
    static let hostHeader: UInt8 = 0xFF
    static let deviceHeader: UInt8 = 0xDD
    static let tail: UInt8 = 0xAA
}

/// Wraps payloads in host frames and keeps the sequence counter.
public struct FrameEncoder: Sendable {
    /// LEN is one byte, so this is the most one frame can carry.
    public static let maxPayloadLength = 0xFF

    private var lastSeq: UInt8 = 0
    public init() {}

    public mutating func encode(_ payload: [UInt8]) -> [UInt8] {
        encodeWithSeq(payload).frame
    }

    public mutating func encodeWithSeq(_ payload: [UInt8]) -> (seq: UInt8, frame: [UInt8]) {
        precondition(payload.count <= Self.maxPayloadLength, "payload too long for one frame")
        lastSeq &+= 1
        var frame: [UInt8] = [FrameByte.hostHeader, lastSeq, UInt8(payload.count)] + payload
        frame.append(checksum(frame))
        frame.append(FrameByte.tail)
        return (lastSeq, frame)
    }
}

/// A host frame as the earbuds see it. Used by the demo device.
public struct HostFrame: Equatable, Sendable {
    public let seq: UInt8
    public let payload: [UInt8]

    public static func parse(_ bytes: [UInt8]) -> HostFrame? {
        guard bytes.count >= 5, bytes[0] == FrameByte.hostHeader, bytes.last == FrameByte.tail else { return nil }
        let len = Int(bytes[2])
        guard bytes.count == 3 + len + 2 else { return nil }
        guard bytes[3 + len] == checksum(bytes[0..<(3 + len)]) else { return nil }
        return HostFrame(seq: bytes[1], payload: Array(bytes[3..<(3 + len)]))
    }
}

/// One type-length-value record from the earbuds.
public struct LTV: Equatable, Sendable {
    public let type: UInt8
    public let value: [UInt8]
    public init(type: UInt8, value: [UInt8]) {
        self.type = type
        self.value = value
    }

    /// Splits a payload into records. Returns nil if the records don't exactly fill it.
    public static func split(_ payload: [UInt8]) -> [LTV]? {
        var records: [LTV] = []
        var i = 0
        while i < payload.count {
            guard i + 2 <= payload.count else { return nil }
            let len = Int(payload[i + 1])
            guard i + 2 + len <= payload.count else { return nil }
            records.append(LTV(type: payload[i], value: Array(payload[(i + 2)..<(i + 2 + len)])))
            i += 2 + len
        }
        return records
    }

    /// Builds the payload bytes for a list of records (used by the demo device).
    public static func join(_ records: [LTV]) -> [UInt8] {
        records.flatMap { [$0.type, UInt8($0.value.count)] + $0.value }
    }
}

public struct InboundFrame: Equatable, Sendable {
    public let seq: UInt8
    public let records: [LTV]
    public init(seq: UInt8, records: [LTV]) {
        self.seq = seq
        self.records = records
    }

    /// Builds a device frame (used by the demo device): DD · SEQ · LEN · records · SUM · AA.
    public static func encode(seq: UInt8, records: [LTV]) -> [UInt8] {
        let payload = LTV.join(records)
        var frame: [UInt8] = [FrameByte.deviceHeader, seq, UInt8(payload.count)] + payload
        frame.append(checksum(frame))
        frame.append(FrameByte.tail)
        return frame
    }
}

/// Streaming decoder for frames from the earbuds. Feed it whatever each notification or
/// serial read delivers; it buffers partial frames and resynchronises after bad bytes.
public struct FrameDecoder: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func reset() { buffer.removeAll() }

    public mutating func feed(_ bytes: [UInt8]) -> [InboundFrame] {
        buffer += bytes
        var frames: [InboundFrame] = []
        while true {
            guard let start = buffer.firstIndex(of: FrameByte.deviceHeader) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 3 else { break }

            switch tryFrame(at: 0) {
            case .frame(let frame, let length):
                frames.append(frame)
                buffer.removeFirst(length)
            case .needMore:
                // Usually the rest of this frame is on its way. But if a complete frame
                // already follows, this header was a stray byte: skip ahead to that frame.
                guard let next = laterCompleteFrame() else { return frames }
                buffer.removeFirst(next)
            case .invalid:
                // Not a frame at this header: drop it and look for the next one.
                buffer.removeFirst()
            }
        }
        return frames
    }

    private func laterCompleteFrame() -> Int? {
        var i = 1
        while let next = buffer[i...].firstIndex(of: FrameByte.deviceHeader) {
            if case .frame = tryFrame(at: next) { return next }
            i = next + 1
        }
        return nil
    }

    private enum Attempt {
        case frame(InboundFrame, length: Int)
        case needMore
        case invalid
    }

    /// The report could not confirm what the inbound LEN byte counts, so try the plausible
    /// readings (payload only, payload + SUM + AA, whole frame) and keep the one that checks out.
    private func tryFrame(at start: Int) -> Attempt {
        let available = buffer.count - start
        guard available >= 3 else { return .needMore }
        let b = buffer[start...]
        let len = Int(b[start + 2])
        let candidates = Set([3 + len + 2, 3 + len, len]).filter { $0 >= 5 }.sorted()
        var waiting = false
        for total in candidates {
            guard available >= total else {
                waiting = true
                continue
            }
            let end = start + total
            guard b[end - 1] == FrameByte.tail else { continue }
            let sum = b[end - 2]
            guard sum == checksum(b[start..<(end - 2)]) || sum == checksum(b[(start + 2)..<(end - 2)]) else { continue }
            guard let records = LTV.split(Array(b[(start + 3)..<(end - 2)])) else { continue }
            return .frame(InboundFrame(seq: b[start + 1], records: records), length: total)
        }
        return waiting ? .needMore : .invalid
    }
}
