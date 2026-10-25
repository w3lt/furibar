import Foundation
import Observation

/// Something that carries bytes to and from the earbuds: a BLE characteristic pair,
/// an RFCOMM channel, or the demo device.
@MainActor
public protocol ByteLink: AnyObject {
    var onReceive: (@MainActor ([UInt8]) -> Void)? { get set }
    func send(_ bytes: [UInt8])
}

/// The status byte in an ACK record (`FE · SEQ · STATUS`).
public struct AckStatus: RawRepresentable, Equatable, Sendable, CustomStringConvertible {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let success = AckStatus(rawValue: 0x00)
    public static let checksumError = AckStatus(rawValue: 0x01)
    public static let unknownCommand = AckStatus(rawValue: 0x02)
    public static let invalidParameter = AckStatus(rawValue: 0x03)
    public static let notSupported = AckStatus(rawValue: 0x04)
    public static let busy = AckStatus(rawValue: 0x05)

    public var description: String {
        switch self {
        case .success: "success"
        case .checksumError: "checksum error"
        case .unknownCommand: "the earbuds don't know this command"
        case .invalidParameter: "invalid value"
        case .notSupported: "not supported by these earbuds"
        case .busy: "the earbuds are busy"
        default: "error \(Hex.byte(rawValue))"
        }
    }
}

public enum CommandError: Error, Equatable, LocalizedError {
    case rejected(AckStatus)

    public var errorDescription: String? {
        switch self {
        case .rejected(let status): "The earbuds refused the change (\(status))."
        }
    }
}

public struct LogEntry: Identifiable, Sendable {
    public enum Direction: Sendable { case sent, received, note }
    public let id = UUID()
    public let date: Date
    public let direction: Direction
    public let text: String
}

/// One connection to a pair of earbuds: sends commands, matches ACKs, keeps the reported state.
@MainActor
@Observable
public final class DeviceSession {
    public private(set) var state = DeviceState()
    public private(set) var hasReceivedData = false
    public private(set) var lastError: String?
    public private(set) var log: [LogEntry] = []

    private let link: ByteLink
    private let ackTimeout: Duration
    private var encoder = FrameEncoder()
    private var decoder = FrameDecoder()
    private var pendingAcks: [UInt8: CheckedContinuation<AckOutcome, Never>] = [:]
    private static let maxLogEntries = 400

    private enum AckOutcome { case status(AckStatus), timeout }

    public init(link: ByteLink, ackTimeout: Duration = .seconds(2)) {
        self.link = link
        self.ackTimeout = ackTimeout
        link.onReceive = { [weak self] bytes in self?.receive(bytes) }
    }

    /// Asks for every setting RoseLink reads on connect.
    public func start() {
        refresh(SettingType.connectReadAll)
    }

    public func refresh(_ types: [SettingType]) {
        send(Payload.read(types))
    }

    /// Changes a setting. The UI updates right away; if the earbuds refuse, the old value comes back
    /// and this throws. If they don't answer at all, the setting is read back to learn the truth.
    public func apply(_ change: SettingChange) async throws {
        let record = change.record
        let type = SettingType(record.type)
        let previous = state.raw[type]
        state.apply(record)
        lastError = nil

        let seq = send(Payload.write(type, record.value))
        switch await waitForAck(seq) {
        case .status(.success):
            return
        case .status(let status):
            state.restore(type, previous)
            lastError = CommandError.rejected(status).errorDescription
            note("\(type.name): rejected (\(status))")
            throw CommandError.rejected(status)
        case .timeout:
            note("\(type.name): no acknowledgement, reading it back")
            refresh([type])
        }
    }

    /// Diagnostics: send any payload, wrapped in a frame.
    public func sendRaw(_ payload: [UInt8]) {
        send(payload)
    }

    public func clearError() { lastError = nil }

    // MARK: - Internals

    @discardableResult
    private func send(_ payload: [UInt8]) -> UInt8 {
        let (seq, frame) = encoder.encodeWithSeq(payload)
        append(.sent, Hex.string(frame))
        link.send(frame)
        return seq
    }

    private func receive(_ bytes: [UInt8]) {
        append(.received, Hex.string(bytes))
        for frame in decoder.feed(bytes) {
            for record in frame.records {
                if SettingType(record.type) == .ack, record.value.count >= 2 {
                    resolveAck(seq: record.value[0], outcome: .status(AckStatus(rawValue: record.value[1])))
                } else {
                    state.apply(record)
                    hasReceivedData = true
                }
            }
        }
    }

    private func waitForAck(_ seq: UInt8) async -> AckOutcome {
        await withCheckedContinuation { continuation in
            pendingAcks[seq]?.resume(returning: .timeout) // seq wrapped around; give up on the old one
            pendingAcks[seq] = continuation
            let timeout = ackTimeout
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolveAck(seq: seq, outcome: .timeout)
            }
        }
    }

    private func resolveAck(seq: UInt8, outcome: AckOutcome) {
        pendingAcks.removeValue(forKey: seq)?.resume(returning: outcome)
    }

    private func note(_ text: String) { append(.note, text) }

    private func append(_ direction: LogEntry.Direction, _ text: String) {
        log.append(LogEntry(date: Date(), direction: direction, text: text))
        if log.count > Self.maxLogEntries { log.removeFirst(log.count - Self.maxLogEntries) }
    }
}
