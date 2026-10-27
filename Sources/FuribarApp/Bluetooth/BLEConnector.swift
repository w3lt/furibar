import CoreBluetooth
import FuribarCore
import IOBluetooth

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
        // The without-response size is what fits in one packet. The with-response size can be
        // larger because CoreBluetooth would fall back to a long write, which the earbuds may not support.
        let chunk = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
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

/// Roseselsa earbuds seen over Bluetooth LE that Furibar won't connect to without being asked.
public struct NearbyEarbuds: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let model: String

    public init(id: UUID, name: String, model: String) {
        self.id = id
        self.name = name
        self.model = model
    }
}

/// Finds Roseselsa earbuds over Bluetooth LE and opens the control link.
///
/// Other people's earbuds advertise the same way, so this connects on its own only to earbuds
/// that are already connected to this Mac, whose advertised address matches a device paired
/// with this Mac, or that the user picked before. Anything else is offered in `nearby`.
@MainActor
final class BLEConnector: NSObject {
    enum Event {
        case state(CBManagerState)
        case ready(BLELink, name: String, model: EarbudModel?)
        case lost
        case nearby([NearbyEarbuds])
        case note(String)
    }

    static let controlService = CBUUID(string: "00FE")
    static let controlWrite = CBUUID(string: "00F1")
    static let controlNotify = CBUUID(string: "00F2")

    var onEvent: (@MainActor (Event) -> Void)?
    var state: CBManagerState { central.state }
    /// Identifiers of earbuds the user picked before (see `Preferences.chosenEarbuds`).
    var chosen: Set<String> = []
    /// Earbuds the user told Furibar to forget this run. Their LE link can outlive the forget for a
    /// while, so they're not taken back through the "already connected to this Mac" path.
    private var forgotten = Set<UUID>()

    private var central: CBCentralManager!
    private var active = false
    private var target: CBPeripheral?
    private var targetName = ""
    private var targetModel: EarbudModel?
    private var writeCharacteristic: CBCharacteristic?
    private var link: BLELink?
    private var connectTimeout: Task<Void, Never>?
    private var retryDelay = BLEConnector.firstRetryDelay
    private var pairedAddresses: [String] = []
    private var pairedAddressesRead = Date.distantPast
    private var targetWasAlreadyConnected = false
    /// An already-connected peripheral that just timed out: the next search scans instead.
    private var skipConnectedOnce: UUID?
    /// Peripherals that turned out not to have the control service; skipped until restart.
    private var ignored = Set<UUID>()
    private var candidates: [UUID: Candidate] = [:]

    private struct Candidate {
        let peripheral: CBPeripheral
        let name: String
        let model: EarbudModel
        let address: String?
    }

    private static let firstRetryDelay: Duration = .seconds(2)
    private static let maxRetryDelay: Duration = .seconds(30)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        active = true
        ignored.removeAll()
        candidates.removeAll()
        publishNearby()
        retryDelay = Self.firstRetryDelay
        begin()
    }

    func stop() {
        active = false
        if central.state == .poweredOn { central.stopScan() }
        let old = target
        reset()
        if let old { central.cancelPeripheralConnection(old) }
        candidates.removeAll()
        publishNearby()
    }

    /// Connects to earbuds from the nearby list, after the user chose them.
    func connect(to id: UUID) {
        guard active, let candidate = candidates.removeValue(forKey: id) else { return }
        chosen.insert(id.uuidString)
        forgotten.remove(id)
        publishNearby()
        if let old = target {
            reset()
            central.cancelPeripheralConnection(old)
        }
        connect(candidate.peripheral, name: candidate.name, model: candidate.model)
    }

    /// Stops treating the chosen earbuds as known (the caller clears `chosen`).
    func forget(_ ids: [UUID]) {
        forgotten.formUnion(ids)
    }

    /// Looks again at the nearby list, in case one of them has been paired since it was seen.
    func recheckNearby() {
        guard active, target == nil, !candidates.isEmpty else { return }
        readPairedAddresses()
        if let (id, c) = candidates.first(where: { BluetoothAddress.isAmong($0.value.address, pairedAddresses) }) {
            candidates[id] = nil
            publishNearby()
            note("\(c.name) is paired with this Mac now")
            connect(c.peripheral, name: c.name, model: c.model)
        }
    }

    private func readPairedAddresses() {
        pairedAddresses = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).compactMap(\.addressString)
        pairedAddressesRead = Date()
    }

    private func reset() {
        connectTimeout?.cancel()
        connectTimeout = nil
        target = nil
        writeCharacteristic = nil
        link = nil
        targetModel = nil
    }

    private func begin() {
        guard active, central.state == .poweredOn, target == nil else { return }
        // Earbuds already connected to this Mac over LE don't advertise, so look for them first.
        let skip = skipConnectedOnce
        skipConnectedOnce = nil
        if let p = central.retrieveConnectedPeripherals(withServices: [Self.controlService]).first(where: {
            !ignored.contains($0.identifier) && !forgotten.contains($0.identifier) && $0.identifier != skip
        }) {
            note("\(p.name ?? "Earbuds") is already connected to this Mac")
            connect(p, name: p.name ?? "Earbuds", model: nil, alreadyConnected: true)
            return
        }
        readPairedAddresses()
        note("Scanning (\(pairedAddresses.count) paired devices on this Mac)")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ p: CBPeripheral, name: String, model: EarbudModel?, alreadyConnected: Bool = false) {
        central.stopScan()
        target = p
        targetName = name
        targetModel = model
        targetWasAlreadyConnected = alreadyConnected
        p.delegate = self
        note("Connecting to \(name)")
        central.connect(p)
        connectTimeout?.cancel()
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.isTarget(p), self.link == nil else { return }
            self.note("\(name) didn't finish connecting")
            if self.targetWasAlreadyConnected { self.skipConnectedOnce = p.identifier }
            self.reset()
            self.central.cancelPeripheralConnection(p)
            self.scheduleRetry()
        }
    }

    private func isTarget(_ p: CBPeripheral) -> Bool {
        p.identifier == target?.identifier
    }

    /// For peripherals that answered but aren't usable: skipped until the next start.
    private func giveUp(on p: CBPeripheral, _ reason: String) {
        note("Skipping \(targetName): \(reason)")
        ignored.insert(p.identifier)
        reset()
        central.cancelPeripheralConnection(p)
        begin()
    }

    /// For errors that may pass (a dropped link mid-setup): try the same earbuds again later.
    private func retryLater(_ p: CBPeripheral, _ what: String, _ error: Error) {
        note("\(what) failed on \(targetName): \(error.localizedDescription)")
        reset()
        central.cancelPeripheralConnection(p)
        scheduleRetry()
    }

    private func scheduleRetry() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.begin()
        }
    }

    private func publishNearby() {
        let list = candidates.map { NearbyEarbuds(id: $0.key, name: $0.value.name, model: $0.value.model.displayName) }
            .sorted { $0.name < $1.name }
        onEvent?(.nearby(list))
    }

    private func note(_ text: String) {
        onEvent?(.note(text))
    }
}

extension BLEConnector: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state != .poweredOn {
            reset()
            candidates.removeAll()
            publishNearby()
        }
        onEvent?(.state(c.state))
        begin()
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        guard active, target == nil, !ignored.contains(p.identifier),
              let data = ad[CBAdvertisementDataManufacturerDataKey] as? Data,
              let info = Advert.identify(manufacturerData: [UInt8](data)) else { return }
        let id = p.identifier
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? info.model.displayName
        let address = info.macAddress ?? "no address in advert"
        let seenBefore = candidates[id] != nil
        // A later advert may carry the address the first one lacked, or the user may have paired since.
        if seenBefore, Date().timeIntervalSince(pairedAddressesRead) > 10 { readPairedAddresses() }

        if chosen.contains(id.uuidString) || BluetoothAddress.isAmong(info.macAddress, pairedAddresses) {
            if candidates.removeValue(forKey: id) != nil { publishNearby() }
            note(chosen.contains(id.uuidString) ? "Found \(name), chosen before" : "Found \(name) (\(address)), paired with this Mac")
            connect(p, name: name, model: info.model)
        } else if !seenBefore {
            note("Saw \(name) (\(address)), not paired with this Mac; waiting to be chosen")
            candidates[id] = Candidate(peripheral: p, name: name, model: info.model, address: info.macAddress)
            publishNearby()
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        guard active, isTarget(p) else {
            c.cancelPeripheralConnection(p)
            return
        }
        p.discoverServices([Self.controlService])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard isTarget(p) else { return }
        note("Couldn't connect to \(targetName): \(error?.localizedDescription ?? "unknown error")")
        reset()
        scheduleRetry()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard isTarget(p) else { return }
        note("\(targetName) disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
        let hadLink = link != nil
        reset()
        if hadLink { onEvent?(.lost) }
        scheduleRetry()
    }
}

extension BLEConnector: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard isTarget(p) else { return }
        if let error { return retryLater(p, "Service discovery", error) }
        guard let service = p.services?.first(where: { $0.uuid == Self.controlService }) else {
            giveUp(on: p, "no control service (00FE)")
            return
        }
        p.discoverCharacteristics([Self.controlWrite, Self.controlNotify], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard isTarget(p) else { return }
        if let error { return retryLater(p, "Characteristic discovery", error) }
        let chars = s.characteristics ?? []
        guard let write = chars.first(where: { $0.uuid == Self.controlWrite }),
              let notify = chars.first(where: { $0.uuid == Self.controlNotify }) else {
            giveUp(on: p, "control characteristics (00F1/00F2) missing")
            return
        }
        writeCharacteristic = write
        p.setNotifyValue(true, for: notify)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard isTarget(p), ch.uuid == Self.controlNotify else { return }
        if let error { return retryLater(p, "Turning on notifications", error) }
        guard ch.isNotifying, link == nil, let write = writeCharacteristic else { return }
        connectTimeout?.cancel()
        connectTimeout = nil
        retryDelay = Self.firstRetryDelay
        let newLink = BLELink(peripheral: p, writeCharacteristic: write)
        link = newLink
        note("Control link ready")
        onEvent?(.ready(newLink, name: targetName, model: targetModel))
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard isTarget(p), ch.uuid == Self.controlNotify, let value = ch.value else { return }
        link?.deliver(value)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        guard isTarget(p), let error else { return }
        note("Write failed: \(error.localizedDescription)")
    }
}
