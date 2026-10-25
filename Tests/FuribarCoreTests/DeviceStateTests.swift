import Testing
@testable import FuribarCore

struct DeviceStateTests {
    private func state(_ records: [LTV]) -> DeviceState {
        var s = DeviceState()
        for r in records { s.apply(r) }
        return s
    }

    @Test func readsNoiseMode() {
        #expect(state([LTV(type: 0x09, value: [0x03])]).noiseMode == .transparency)
        #expect(state([LTV(type: 0x09, value: [0x01])]).noiseMode == .noiseCancelling)
    }

    @Test func unknownNoiseModeValueIsKeptRawButNotGuessed() {
        let s = state([LTV(type: 0x09, value: [0x20])])
        #expect(s.noiseMode == nil)
        #expect(s.raw[.noiseMode] == [0x20])
    }

    @Test func touchControlAndInEarUseZeroForOn() {
        #expect(state([LTV(type: 0x07, value: [0x00])]).touchControl == true)
        #expect(state([LTV(type: 0x07, value: [0x01])]).touchControl == false)
        #expect(state([LTV(type: 0x08, value: [0x00])]).inEarDetection == true)
        #expect(state([LTV(type: 0x08, value: [0x01])]).inEarDetection == false)
    }

    @Test func gameModeUsesOneForOn() {
        #expect(state([LTV(type: 0x0E, value: [0x01])]).gameMode == true)
        #expect(state([LTV(type: 0x0E, value: [0x00])]).gameMode == false)
    }

    @Test func readsEQPresetIncludingGamePresets() {
        #expect(state([LTV(type: 0x2A, value: [0x05])]).eqPreset == .bassPlus)
        #expect(state([LTV(type: 0x2A, value: [0xA2])]).eqPreset == .game(3))
    }

    @Test func batteryReadsLeftRightAndCasePercentages() {
        let b = state([LTV(type: 0x0C, value: [0x50, 0x4B, 0x64])]).battery
        #expect(b?.left == BatteryLevel(percent: 80, charging: false))
        #expect(b?.right == BatteryLevel(percent: 75, charging: false))
        #expect(b?.chargingCase == BatteryLevel(percent: 100, charging: false))
    }

    @Test func batteryHighBitMeansChargingAndFFMeansUnavailable() {
        let b = state([LTV(type: 0x0C, value: [0xD0, 0x4B, 0xFF])]).battery
        #expect(b?.left == BatteryLevel(percent: 80, charging: true))
        #expect(b?.chargingCase == nil)
    }

    @Test func batteryIgnoresImpossiblePercentages() {
        let b = state([LTV(type: 0x0C, value: [0x7F, 0x4B])]).battery
        #expect(b?.left == nil)
        #expect(b?.right == BatteryLevel(percent: 75, charging: false))
        #expect(b?.chargingCase == nil)
    }

    @Test func firmwareVersionFromASCII() {
        #expect(state([LTV(type: 0x0D, value: Array("1.2.3".utf8))]).firmwareVersion == "1.2.3")
    }

    @Test func firmwareVersionFromBinaryBytes() {
        #expect(state([LTV(type: 0x0D, value: [0x01, 0x00, 0x07])]).firmwareVersion == "1.0.7")
    }

    @Test func supportsOnlyWhatTheEarbudsReported() {
        let s = state([LTV(type: 0x09, value: [0x02]), LTV(type: 0x0E, value: [0x00])])
        #expect(s.supports(.noiseMode))
        #expect(s.supports(.gameMode))
        #expect(!s.supports(.spatialAudio))
    }

    @Test func emptyValueDoesNotCountAsSupported() {
        // Some firmware answers unsupported reads with a zero-length record.
        #expect(!state([LTV(type: 0x33, value: [])]).supports(.spatialAudio))
    }

    @Test func acknowledgementsAreNotSettings() {
        #expect(state([LTV(type: 0xFE, value: [0x01, 0x00])]).raw.isEmpty)
    }

    @Test func laterReportsReplaceEarlierOnes() {
        let s = state([LTV(type: 0x09, value: [0x01]), LTV(type: 0x09, value: [0x02])])
        #expect(s.noiseMode == .off)
    }
}

struct SettingChangeTests {
    @Test func encodesWritesWithTheRightPolarity() {
        #expect(SettingChange.touchControl(true).record == LTV(type: 0x07, value: [0x00]))
        #expect(SettingChange.inEarDetection(false).record == LTV(type: 0x08, value: [0x01]))
        #expect(SettingChange.gameMode(true).record == LTV(type: 0x0E, value: [0x01]))
        #expect(SettingChange.multipoint(false).record == LTV(type: 0x32, value: [0x00]))
    }

    @Test func encodesEnumeratedSettings() {
        #expect(SettingChange.noiseMode(.transparency).record == LTV(type: 0x09, value: [0x03]))
        #expect(SettingChange.eqPreset(.game(2)).record == LTV(type: 0x2A, value: [0xA1]))
        #expect(SettingChange.promptLanguage(.english).record == LTV(type: 0x31, value: [0x01]))
        #expect(SettingChange.spatialMode(.fixed).record == LTV(type: 0x38, value: [0x02]))
        #expect(SettingChange.ancLevel(4).record == LTV(type: 0x2C, value: [0x04]))
    }

    @Test func applyingAChangeUpdatesTheState() {
        var s = DeviceState()
        s.apply(SettingChange.noiseMode(.transparency).record)
        #expect(s.noiseMode == .transparency)
    }
}
