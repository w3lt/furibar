import Testing
@testable import FuribarCore

struct AdvertTests {
    // Manufacturer data as CoreBluetooth hands it over: company ID (2 bytes, little-endian) then data.
    let furinaAdvert: [UInt8] = [
        0x0B, 0x11, 0x0A, 0x0C, // model prefix
        0x00, 0x00,
        0x01, // device type: earbuds
        0x01, // Classic Bluetooth available
        0x00, 0x00, 0x00,
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, // MAC address, bytes 11–16
    ]

    @Test func identifiesFurinaFromItsPrefix() {
        let info = Advert.identify(manufacturerData: furinaAdvert)
        #expect(info?.model.id == "furina")
        #expect(info?.model.isFurina == true)
    }

    @Test func readsMACAddressAndClassicFlag() {
        let info = Advert.identify(manufacturerData: furinaAdvert)
        #expect(info?.macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(info?.hasClassicBluetooth == true)
        #expect(info?.kind == .earbuds)
    }

    @Test func shortAdvertHasNoMACAddress() {
        let info = Advert.identify(manufacturerData: Array(furinaAdvert.prefix(10)))
        #expect(info?.model.id == "furina")
        #expect(info?.macAddress == nil)
    }

    @Test func neighbouringPrefixIsADifferentModel() {
        var zircon = furinaAdvert
        zircon[3] = 0x0B
        let info = Advert.identify(manufacturerData: zircon)
        #expect(info?.model.id == "zircon")
        #expect(info?.model.isFurina == false)
    }

    @Test func unrelatedDevicesAreIgnored() {
        #expect(Advert.identify(manufacturerData: [0x4C, 0x00, 0x10, 0x05, 0x01, 0x18]) == nil)
        #expect(Advert.identify(manufacturerData: [0x0B]) == nil)
    }
}

struct BluetoothAddressTests {
    @Test func readsTheFormatsMacOSAndAdvertsUse() {
        let expected: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        #expect(BluetoothAddress.bytes("aa-bb-cc-dd-ee-ff") == expected)
        #expect(BluetoothAddress.bytes("AA:BB:CC:DD:EE:FF") == expected)
        #expect(BluetoothAddress.bytes("aabbccddeeff") == expected)
    }

    @Test func rejectsAnythingThatIsNotSixBytes() {
        #expect(BluetoothAddress.bytes("aa-bb-cc-dd-ee") == nil)
        #expect(BluetoothAddress.bytes("aa-bb-cc-dd-ee-ff-00") == nil)
        #expect(BluetoothAddress.bytes("gg-bb-cc-dd-ee-ff") == nil)
        #expect(BluetoothAddress.bytes("") == nil)
    }

    @Test func advertMatchesAPairedAddressInEitherByteOrder() {
        let paired = ["11-22-33-44-55-66", "aa-bb-cc-dd-ee-ff"]
        #expect(BluetoothAddress.isAmong("AA:BB:CC:DD:EE:FF", paired))
        #expect(BluetoothAddress.isAmong("FF:EE:DD:CC:BB:AA", paired))
    }

    @Test func unknownOrMissingAddressDoesNotMatch() {
        let paired = ["11-22-33-44-55-66"]
        #expect(!BluetoothAddress.isAmong("AA:BB:CC:DD:EE:FF", paired))
        #expect(!BluetoothAddress.isAmong(nil, paired))
        #expect(!BluetoothAddress.isAmong("AA:BB:CC:DD:EE:FF", []))
    }
}
