import CoreBluetooth
import FuribarCore

/// Bytes over the RoseLink control characteristics: write 00F1, notify 00F2 (service 00FE).
@MainActor
final class BLELink: ByteLink {
    var onReceive: (@MainActor ([UInt8]) -> Void)?
    private let peripheral: CBPeripheral
    private let writeCharacteristic: CBCharacteristic

    init(peripheral: CBPeripheral, writeCharacteristic: CBCharacteristic) {
        self.peripheral = peripheral
        self.writeCharacteristic = writeCharacteristic
    }

    func send(_ bytes: [UInt8]) {
        let type: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        let chunk = max(20, peripheral.maximumWriteValueLength(for: type))
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunk, bytes.count)
            peripheral.writeValue(Data(bytes[offset..<end]), for: writeCharacteristic, type: type)
            offset = end
        }
    }

    fileprivate func deliver(_ data: Data) {
        onReceive?([UInt8](data))
    }
}

/// Finds Roseselsa earbuds over Bluetooth LE and opens the control link.
@MainActor
final class BLEConnector: NSObject {
    enum Event {
        case state(CBManagerState)
        case ready(BLELink, name: String, model: EarbudModel?)
        case lost
    }

    static let controlService = CBUUID(string: "00FE")
    static let controlWrite = CBUUID(string: "00F1")
    static let controlNotify = CBUUID(string: "00F2")

    var onEvent: (@MainActor (Event) -> Void)?
    var state: CBManagerState { central.state }

    private var central: CBCentralManager!
    private var active = false
    private var target: CBPeripheral?
    private var targetName = ""
    private var targetModel: EarbudModel?
    private var writeCharacteristic: CBCharacteristic?
    private var link: BLELink?
    /// Peripherals that turned out not to have the control service; skipped until restart.
    private var ignored = Set<UUID>()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        active = true
        ignored.removeAll()
        begin()
    }

    func stop() {
        active = false
        if central.state == .poweredOn { central.stopScan() }
        let old = target
        reset()
        if let old { central.cancelPeripheralConnection(old) }
    }

    private func reset() {
        target = nil
        writeCharacteristic = nil
        link = nil
        targetModel = nil
    }

    private func begin() {
        guard active, central.state == .poweredOn, target == nil else { return }
        // Earbuds already connected to this Mac over LE don't advertise, so look for them first.
        if let p = central.retrieveConnectedPeripherals(withServices: [Self.controlService])
            .first(where: { !ignored.contains($0.identifier) }) {
            connect(p, name: p.name ?? "Earbuds", model: nil)
            return
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ p: CBPeripheral, name: String, model: EarbudModel?) {
        central.stopScan()
        target = p
        targetName = name
        targetModel = model
        p.delegate = self
        central.connect(p)
    }

    private func giveUp(on p: CBPeripheral) {
        ignored.insert(p.identifier)
        reset()
        central.cancelPeripheralConnection(p)
        begin()
    }

    private func scheduleRetry() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.begin()
        }
    }
}

extension BLEConnector: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state != .poweredOn { reset() }
        onEvent?(.state(c.state))
        begin()
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        guard active, target == nil, !ignored.contains(p.identifier),
              let data = ad[CBAdvertisementDataManufacturerDataKey] as? Data,
              let info = Advert.identify(manufacturerData: [UInt8](data)) else { return }
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? info.model.displayName
        connect(p, name: name, model: info.model)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.controlService])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        reset()
        scheduleRetry()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p.identifier == target?.identifier else { return }
        let hadLink = link != nil
        reset()
        if hadLink { onEvent?(.lost) }
        scheduleRetry()
    }
}

extension BLEConnector: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == Self.controlService }) else {
            giveUp(on: p)
            return
        }
        p.discoverCharacteristics([Self.controlWrite, Self.controlNotify], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        let chars = s.characteristics ?? []
        guard let write = chars.first(where: { $0.uuid == Self.controlWrite }),
              let notify = chars.first(where: { $0.uuid == Self.controlNotify }) else {
            giveUp(on: p)
            return
        }
        writeCharacteristic = write
        p.setNotifyValue(true, for: notify)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.controlNotify, ch.isNotifying, link == nil, let write = writeCharacteristic else {
            if error != nil { giveUp(on: p) }
            return
        }
        let newLink = BLELink(peripheral: p, writeCharacteristic: write)
        link = newLink
        onEvent?(.ready(newLink, name: targetName, model: targetModel))
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.controlNotify, let value = ch.value else { return }
        link?.deliver(value)
    }
}
