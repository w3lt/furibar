import IOBluetooth
import FuribarCore

/// Bytes over an RFCOMM (serial port) channel.
@MainActor
final class RFCOMMLink: NSObject, ByteLink {
    var onReceive: (@MainActor ([UInt8]) -> Void)?
    var onOpen: (@MainActor (Bool) -> Void)?
    var onClosed: (@MainActor () -> Void)?
    var onWriteError: (@MainActor (IOReturn) -> Void)?
    var channel: IOBluetoothRFCOMMChannel?

    /// Frames are at most a few dozen bytes, so a blocking write returns almost at once.
    func send(_ bytes: [UInt8]) {
        guard let channel else { return }
        let mtu = max(1, Int(channel.getMTU()))
        var offset = 0
        while offset < bytes.count {
            var chunk = Array(bytes[offset..<min(offset + mtu, bytes.count)])
            let result = channel.writeSync(&chunk, length: UInt16(chunk.count))
            guard result == kIOReturnSuccess else {
                onWriteError?(result)
                return
            }
            offset += chunk.count
        }
    }

    func close() {
        onClosed = nil
        onOpen = nil
        // The channel doesn't retain its delegate (macOS 10.6+), so detach before this object can go away.
        _ = channel?.setDelegate(nil)
        _ = channel?.close()
        channel = nil
    }
}

extension RFCOMMLink: @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onOpen?(error == kIOReturnSuccess)
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        onReceive?([UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength)))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        let closed = onClosed
        channel = nil
        closed?()
    }
}

/// Finds paired, connected Furina earbuds over Classic Bluetooth and opens their control channel.
///
/// RoseLink's device table gives Furina its own serial-port service UUID. macOS keeps the audio
/// connection itself; this only adds the control channel next to it.
@MainActor
final class ClassicConnector: NSObject {
    enum Event {
        case ready(RFCOMMLink, name: String)
        case lost
        case note(String)
    }

    /// Furina control service: 0cf12d31-fac3-4553-bd80-d6832e7b3931
    static let furinaControlService: [UInt8] = [
        0x0C, 0xF1, 0x2D, 0x31, 0xFA, 0xC3, 0x45, 0x53, 0xBD, 0x80, 0xD6, 0x83, 0x2E, 0x7B, 0x39, 0x31,
    ]

    var onEvent: (@MainActor (Event) -> Void)?

    private var active = false
    private var link: RFCOMMLink?
    /// The link whose channel is still opening. Holding it keeps it alive until then.
    private var pendingLink: RFCOMMLink?
    /// Links still opening when the connector stopped. Kept alive until the open finishes,
    /// then closed, so the channel is never left open with no owner.
    private var abandoned = Set<RFCOMMLink>()
    private var queried = Set<String>()
    private var sdpFailures: [String: Int] = [:]
    private static let maxSDPFailures = 3
    private var lastSeen: [String] = []
    private var connectNotification: IOBluetoothUserNotification?
    private var retryTimer: Timer?

    func start() {
        guard !active else { return }
        active = true
        queried.removeAll()
        sdpFailures.removeAll()
        lastSeen = []
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
        retryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        look()
    }

    func stop() {
        active = false
        connectNotification?.unregister()
        connectNotification = nil
        retryTimer?.invalidate()
        retryTimer = nil
        link?.close()
        link = nil
        if let pendingLink { abandoned.insert(pendingLink) }
        pendingLink = nil
    }

    private func look() {
        guard active, link == nil, pendingLink == nil else { return }
        let devices = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).filter { $0.isConnected() }
        let names = devices.map { $0.name ?? $0.addressString ?? "unknown" }
        if names != lastSeen {
            lastSeen = names
            note(names.isEmpty ? "No paired device is connected" : "Connected paired devices: \(names.joined(separator: ", "))")
        }
        for device in devices {
            if let channel = controlChannel(on: device) {
                open(device, channel: channel)
                return
            }
            // No cached service list for this device yet: ask it once.
            let address = device.addressString ?? ""
            if !queried.contains(address) {
                queried.insert(address)
                note("Asking \(device.name ?? address) for its services")
                device.performSDPQuery(self)
            }
        }
    }

    private func controlChannel(on device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        let uuid = IOBluetoothSDPUUID(bytes: Self.furinaControlService, length: 16)
        guard let record = device.getServiceRecord(for: uuid) else { return nil }
        var channel: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&channel) == kIOReturnSuccess ? channel : nil
    }

    private func open(_ device: IOBluetoothDevice, channel channelID: BluetoothRFCOMMChannelID) {
        let name = device.name ?? "Furina"
        note("Opening the control channel on \(name) (RFCOMM \(channelID))")
        let newLink = RFCOMMLink()
        newLink.onOpen = { [weak self, weak newLink] ok in
            guard let self, let newLink else { return }
            if self.abandoned.remove(newLink) != nil || newLink !== self.pendingLink {
                newLink.close() // stopped or replaced while opening
                return
            }
            self.pendingLink = nil
            guard ok, self.active else {
                self.note("Couldn't open the control channel on \(name)")
                newLink.close()
                return
            }
            self.link = newLink
            self.note("Control channel open")
            self.onEvent?(.ready(newLink, name: name))
        }
        newLink.onClosed = { [weak self, weak newLink] in
            guard let self, let newLink else { return }
            if self.abandoned.remove(newLink) != nil { return }
            if newLink === self.pendingLink {
                self.pendingLink = nil
                self.note("The control channel on \(name) closed while opening")
            } else if newLink === self.link {
                self.link = nil
                self.queried.removeAll()
                self.note("Control channel closed")
                self.onEvent?(.lost)
            }
        }
        newLink.onWriteError = { [weak self] result in
            self?.note("Write failed (\(Self.describe(result)))")
        }
        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: newLink)
        guard result == kIOReturnSuccess else {
            note("Couldn't start opening the control channel (\(Self.describe(result)))")
            return
        }
        newLink.channel = channel
        pendingLink = newLink
        Task { @MainActor [weak self, weak newLink] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, let newLink else { return }
            if newLink === self.pendingLink {
                self.pendingLink = nil
                self.note("The control channel on \(name) didn't open in time")
            } else if self.abandoned.remove(newLink) == nil {
                return // opened or closed normally
            }
            newLink.close()
        }
    }

    private func note(_ text: String) {
        onEvent?(.note(text))
    }

    private static func describe(_ result: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: result))
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        let name = device.name ?? device.addressString ?? "device"
        guard status == kIOReturnSuccess else {
            let address = device.addressString ?? ""
            let failures = sdpFailures[address, default: 0] + 1
            sdpFailures[address] = failures
            if failures < Self.maxSDPFailures {
                queried.remove(address) // the next look (every 15 seconds) asks again
                note("Service lookup on \(name) failed (\(Self.describe(status))); will retry")
            } else {
                note("Service lookup on \(name) failed \(failures) times; waiting until it reconnects")
            }
            return
        }
        guard active, link == nil, pendingLink == nil else { return }
        guard let channel = controlChannel(on: device) else {
            note("\(name) doesn't offer the Furina control service")
            return
        }
        open(device, channel: channel)
    }

    @objc func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        queried.remove(device.addressString ?? "")
        sdpFailures[device.addressString ?? ""] = nil
        // Give the audio connection a moment to settle before opening the control channel.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.look()
        }
    }
}
