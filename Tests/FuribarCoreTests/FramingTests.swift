import Testing
@testable import FuribarCore

/// Expected bytes here are worked out by hand from the RS Common V2 rules
/// (FF/DD · SEQ · LEN · PAYLOAD · SUM · AA, SUM = low byte of the sum of all bytes before it).
struct EncoderTests {
    @Test func encodesNoiseModeWriteLikeTheReportExample() {
        var encoder = FrameEncoder()
        #expect(encoder.encode([0x09, 0x01]) == [0xFF, 0x01, 0x02, 0x09, 0x01, 0x0C, 0xAA])
    }

    @Test func encodesTheConnectTimeReadAllRequest() {
        var encoder = FrameEncoder()
        let frame = encoder.encode(Payload.read(SettingType.connectReadAll))
        #expect(frame == [
            0xFF, 0x01, 0x1E, 0xFA, 0x01, 0x07, 0x08, 0x09, 0x0C, 0x0D, 0x0E, 0x12, 0x2A, 0x2B, 0x2C, 0x2D,
            0x2E, 0x2F, 0x31, 0x32, 0x33, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3F, 0x45, 0x46,
            0x49, 0xEA, 0xAA,
        ])
    }

    @Test func sequenceNumberIncrementsAndWrapsAfterFF() {
        var encoder = FrameEncoder()
        var seqs: [UInt8] = []
        for _ in 0..<257 { seqs.append(encoder.encode([0x0C])[1]) }
        #expect(seqs[0] == 0x01)
        #expect(seqs[1] == 0x02)
        #expect(seqs[254] == 0xFF)
        #expect(seqs[255] == 0x00)
        #expect(seqs[256] == 0x01)
    }

    @Test func reportsTheSequenceNumberItUsed() {
        var encoder = FrameEncoder()
        _ = encoder.encode([0x0C])
        let (seq, frame) = encoder.encodeWithSeq([0x0E, 0x01])
        #expect(seq == 0x02)
        #expect(frame == [0xFF, 0x02, 0x02, 0x0E, 0x01, 0x12, 0xAA])
    }
}

struct HostFrameParsingTests {
    @Test func parsesAHostFrame() {
        let parsed = HostFrame.parse([0xFF, 0x05, 0x02, 0x0E, 0x01, 0x15, 0xAA])
        #expect(parsed?.seq == 0x05)
        #expect(parsed?.payload == [0x0E, 0x01])
    }

    @Test func rejectsAHostFrameWithABadChecksum() {
        #expect(HostFrame.parse([0xFF, 0x05, 0x02, 0x0E, 0x01, 0x16, 0xAA]) == nil)
    }
}

struct DecoderTests {
    @Test func decodesOneDeviceFrameIntoRecords() {
        var decoder = FrameDecoder()
        let frames = decoder.feed([0xDD, 0x01, 0x03, 0x09, 0x01, 0x01, 0xEC, 0xAA])
        #expect(frames == [InboundFrame(seq: 0x01, records: [LTV(type: 0x09, value: [0x01])])])
    }

    @Test func decodesSeveralRecordsInOneFrame() {
        var decoder = FrameDecoder()
        let frames = decoder.feed([0xDD, 0x07, 0x08, 0x0C, 0x03, 0x50, 0x4B, 0x64, 0x2A, 0x01, 0x05, 0x2A, 0xAA])
        #expect(frames.first?.records == [
            LTV(type: 0x0C, value: [0x50, 0x4B, 0x64]),
            LTV(type: 0x2A, value: [0x05]),
        ])
    }

    @Test func acceptsAChecksumThatStartsAtByteTwo() {
        var decoder = FrameDecoder()
        let frames = decoder.feed([0xDD, 0x01, 0x03, 0x09, 0x01, 0x01, 0x0E, 0xAA])
        #expect(frames.count == 1)
    }

    @Test func reassemblesAFrameSplitAcrossNotifications() {
        var decoder = FrameDecoder()
        #expect(decoder.feed([0xDD, 0x02, 0x04, 0xFE]).isEmpty)
        let frames = decoder.feed([0x02, 0x05, 0x00, 0xE8, 0xAA])
        #expect(frames == [InboundFrame(seq: 0x02, records: [LTV(type: 0xFE, value: [0x05, 0x00])])])
    }

    @Test func skipsGarbageBeforeTheHeader() {
        var decoder = FrameDecoder()
        let frames = decoder.feed([0x00, 0x13, 0xDD, 0x01, 0x03, 0x09, 0x01, 0x01, 0xEC, 0xAA])
        #expect(frames.count == 1)
    }

    @Test func dropsACorruptFrameAndRecoversOnTheNextOne() {
        var decoder = FrameDecoder()
        let corrupt: [UInt8] = [0xDD, 0x01, 0x03, 0x09, 0x01, 0x01, 0x00, 0xAA]
        let good: [UInt8] = [0xDD, 0x02, 0x04, 0xFE, 0x02, 0x05, 0x00, 0xE8, 0xAA]
        let frames = decoder.feed(corrupt + good)
        #expect(frames == [InboundFrame(seq: 0x02, records: [LTV(type: 0xFE, value: [0x05, 0x00])])])
    }

    @Test func toleratesALengthByteThatCountsTheWholeFrame() {
        // The report could not confirm what inbound LEN counts; accept this layout too.
        var decoder = FrameDecoder()
        let frames = decoder.feed([0xDD, 0x01, 0x08, 0x09, 0x01, 0x01, 0xF1, 0xAA])
        #expect(frames == [InboundFrame(seq: 0x01, records: [LTV(type: 0x09, value: [0x01])])])
    }

    @Test func decodesTwoFramesInOneChunk() {
        var decoder = FrameDecoder()
        let a: [UInt8] = [0xDD, 0x01, 0x03, 0x09, 0x01, 0x01, 0xEC, 0xAA]
        let b: [UInt8] = [0xDD, 0x01, 0x03, 0x0E, 0x01, 0x01, 0xF1, 0xAA]
        #expect(decoder.feed(a + b).count == 2)
    }
}

struct PayloadTests {
    @Test func writePayloadIsTypeFollowedByValue() {
        #expect(Payload.write(.noiseMode, [0x03]) == [0x09, 0x03])
    }

    @Test func readPayloadIsFAFollowedByTypes() {
        #expect(Payload.read([.battery, .firmwareVersion]) == [0xFA, 0x0C, 0x0D])
    }
}
