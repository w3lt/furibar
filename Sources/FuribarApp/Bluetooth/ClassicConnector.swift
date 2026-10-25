import IOBluetooth
import FuribarCore

/// Bytes over an RFCOMM (serial port) channel.
@MainActor
final class RFCOMMLink: NSObject, ByteLink {
    var onReceive: (@MainActor ([UInt8]) -> Void)?
    var onOpen: (@MainActor (Bool) -> Void)?
    var onClosed: (@MainActor () -> Void)?
    var channel: IOBluetoothRFCOMMChannel?

    func send(_ bytes: [UInt8]) {
        guard let channel else { return }
        let mtu = max(1, Int(channel.getMTU()))
        var offset = 0
        while offset < bytes.count {
            var chunk = Array(bytes[offset..<min(offset + mtu, bytes.count)])
            _ = channel.writeSync(&chunk, length: UInt16(chunk.count))
            offset += chunk.count
        }
    }

    func close() {
        onClosed = nil
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
    }

    /// Furina control service: 0cf12d31-fac3-4553-bd80-d6832e7b3931
    static let furinaControlService: [UInt8] = [
        0x0C, 0xF1, 0x2D, 0x31, 0xFA, 0xC3, 0x45, 0x53, 0xBD, 0x80, 0xD6, 0x83, 0x2E, 0x7B, 0x39, 0x31,
    ]

    var onEvent: (@MainActor (Event) -> Void)?

    private var active = false
    private var link: RFCOMMLink?
    private var opening = false
    private var queried = Set<String>()
    private var connectNotification: IOBluetoothUserNotification?
    private var retryTimer: Timer?

    func start() {
        guard !active else { return }
        active = true
        queried.removeAll()
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
        opening = false
    }

    private func look() {
        guard active, link == nil, !opening else { return }
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for device in devices where device.isConnected() {
            if let channel = controlChannel(on: device) {
                open(device, channel: channel)
                return
            }
            // No cached service list for this device yet: ask it once.
            let address = device.addressString ?? ""
            if !queried.contains(address) {
                queried.insert(address)
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
        opening = true
        let name = device.name ?? "Furina"
        let newLink = RFCOMMLink()
        newLink.onOpen = { [weak self, weak newLink] ok in
            guard let self, let newLink else { return }
            self.opening = false
            guard ok, self.active else {
                newLink.close()
                return
            }
            self.link = newLink
            self.onEvent?(.ready(newLink, name: name))
        }
        newLink.onClosed = { [weak self] in
            guard let self else { return }
            self.link = nil
            self.opening = false
            self.queried.removeAll()
            self.onEvent?(.lost)
        }
        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: newLink)
        guard result == kIOReturnSuccess else {
            opening = false
            return
        }
        newLink.channel = channel
        pendingLink = newLink
    }

    /// Keeps the link alive while its channel is opening.
    private var pendingLink: RFCOMMLink?

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard active, link == nil, !opening, let channel = controlChannel(on: device) else { return }
        open(device, channel: channel)
    }

    @objc func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        queried.remove(device.addressString ?? "")
        // Give the audio connection a moment to settle before opening the control channel.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.look()
        }
    }
}
