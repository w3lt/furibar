import Testing
@testable import FuribarCore

/// A link that records what the session sends and lets a test inject bytes from the "earbuds".
@MainActor
final class RecordingLink: ByteLink {
    var onReceive: (@MainActor ([UInt8]) -> Void)?
    var sent: [[UInt8]] = []
    func send(_ bytes: [UInt8]) { sent.append(bytes) }
    func deliver(_ bytes: [UInt8]) { onReceive?(bytes) }
}

@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
struct SessionTests {
    @Test func startSendsTheReadAllRequest() {
        let link = RecordingLink()
        let session = DeviceSession(link: link)
        session.start()
        #expect(link.sent.first == [
            0xFF, 0x01, 0x1E, 0xFA, 0x01, 0x07, 0x08, 0x09, 0x0C, 0x0D, 0x0E, 0x12, 0x2A, 0x2B, 0x2C, 0x2D,
            0x2E, 0x2F, 0x31, 0x32, 0x33, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3F, 0x45, 0x46,
            0x49, 0xEA, 0xAA,
        ])
    }

    @Test func fillsStateFromTheEarbudsReply() async {
        let demo = DemoEarbuds()
        let session = DeviceSession(link: demo)
        session.start()
        await waitUntil { session.hasReceivedData }
        #expect(session.state.noiseMode == .noiseCancelling)
        #expect(session.state.battery?.left?.percent == 82)
        #expect(session.state.firmwareVersion == "1.0.8")
    }

    @Test func unsolicitedReportsUpdateState() {
        let link = RecordingLink()
        let session = DeviceSession(link: link)
        link.deliver([0xDD, 0x01, 0x03, 0x09, 0x01, 0x03, 0xEE, 0xAA])
        #expect(session.state.noiseMode == .transparency)
    }

    @Test func acceptedChangeSticksOnTheEarbuds() async throws {
        let demo = DemoEarbuds()
        let session = DeviceSession(link: demo, ackTimeout: .milliseconds(500))
        try await session.apply(.noiseMode(.transparency))
        #expect(session.state.noiseMode == .transparency)
        #expect(demo.settings[.noiseMode] == [0x03])
        // Resolved by the ACK, not by the timeout path.
        #expect(!session.log.contains { $0.direction == .note })
    }

    @Test func rejectedChangeIsUndoneAndReported() async {
        let demo = DemoEarbuds()
        demo.rejected = [.spatialAudio]
        let session = DeviceSession(link: demo)
        session.start()
        await waitUntil { session.hasReceivedData }
        #expect(session.state.spatialAudio == false)

        await #expect(throws: CommandError.rejected(.notSupported)) {
            try await session.apply(.spatialAudio(true))
        }
        #expect(session.state.spatialAudio == false)
        #expect(session.lastError != nil)
    }

    @Test func missingAckKeepsTheChangeAndRereadsTheSetting() async throws {
        let link = RecordingLink()
        let session = DeviceSession(link: link, ackTimeout: .milliseconds(20))
        try await session.apply(.noiseMode(.transparency))
        #expect(session.state.noiseMode == .transparency)
        // Write with seq 1, then a read of 0x09 with seq 2.
        #expect(link.sent.last == [0xFF, 0x02, 0x02, 0xFA, 0x09, 0x06, 0xAA])
    }

    @Test func rawSendWrapsThePayloadInAFrame() {
        let link = RecordingLink()
        let session = DeviceSession(link: link)
        session.sendRaw([0x2F, 0x04])
        #expect(link.sent == [[0xFF, 0x01, 0x02, 0x2F, 0x04, 0x35, 0xAA]])
    }

    @Test func logRecordsTrafficInBothDirections() {
        let link = RecordingLink()
        let session = DeviceSession(link: link)
        session.sendRaw([0x2F, 0x04])
        link.deliver([0xDD, 0x01, 0x03, 0x09, 0x01, 0x03, 0xEE, 0xAA])
        #expect(session.log.map(\.direction) == [.sent, .received])
        #expect(session.log.first?.text == "FF 01 02 2F 04 35 AA")
    }
}
