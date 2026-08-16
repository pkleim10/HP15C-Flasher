import Foundation

public struct FlashPlan: Equatable {
    public let image: FirmwareImage
    public let address: UInt32
    public let port: SerialPort?

    public var byteCount: Int { image.byteCount }
}

public enum FlashProgressPhase: Sendable {
    case reading
    case writing
    case verifying
}

public typealias FlashProgress = (_ fraction: Double, _ phase: FlashProgressPhase) -> Void

/// Coordinates cable detection, image checks, and SAM-BA flash I/O.
public struct Flasher {
    public var ports: SerialPortListing
    public var requireExactFirmwareSize: Bool
    public var openTransport: (SerialPort) throws -> ByteTransport

    public init(
        ports: SerialPortListing = DeviceSerialPortListing(),
        requireExactFirmwareSize: Bool = true,
        openTransport: @escaping (SerialPort) throws -> ByteTransport = { try POSIXSerialLink(path: $0.path) }
    ) {
        self.ports = ports
        self.requireExactFirmwareSize = requireExactFirmwareSize
        self.openTransport = openTransport
    }

    public func listProgrammingCables() throws -> [SerialPort] {
        try ports.listPorts().programmingCables
    }

    public func requireProgrammingCable() throws -> SerialPort {
        let cables = try listProgrammingCables()
        if let modem = cables.first(where: { $0.name.lowercased().hasPrefix("cu.usbmodem") }) {
            return modem
        }
        guard let first = cables.first else {
            throw FlasherError.noProgrammingCable
        }
        return first
    }

    public func planWrite(firmwareURL: URL, address: UInt32 = FlashLayout.applicationStart) throws -> FlashPlan {
        let image = try FirmwareImage.load(from: firmwareURL, requireExactSize: requireExactFirmwareSize)
        guard FlashLayout.isSafeApplicationRange(address: address, length: UInt32(image.byteCount)) else {
            throw FlasherError.writeWouldTouchBootloader(address: address)
        }
        let port = try? requireProgrammingCable()
        return FlashPlan(image: image, address: address, port: port)
    }

    /// Opens the cable, enters SAM-BA mode, and reads CHIPID.
    public func connect() throws -> ConnectedTarget {
        let port = try requireProgrammingCable()
        let transport = try openTransport(port)
        let client = SambaClient(transport: transport)
        do {
            try client.connect()
            let flash = FlashCalw(samba: client)
            let identity = try flash.identify()
            return ConnectedTarget(port: port, client: client, identity: identity)
        } catch {
            client.close()
            throw error
        }
    }

    public func write(
        firmwareURL: URL,
        address: UInt32 = FlashLayout.applicationStart,
        client: SambaClient? = nil,
        progress: FlashProgress? = nil
    ) throws {
        let plan = try planWrite(firmwareURL: firmwareURL, address: address)
        if client == nil, plan.port == nil {
            throw FlasherError.noProgrammingCable
        }
        try withClient(client) { samba in
            let flash = FlashCalw(samba: samba)
            try flash.writeApplication(
                plan.image.data,
                progress: { progress?($0, .writing) },
                verifyProgress: { progress?($0, .verifying) }
            )
        }
    }

    @discardableResult
    public func read(to fileURL: URL, client: SambaClient? = nil, progress: FlashProgress? = nil) throws -> Data {
        var saved = Data()
        try withClient(client) { samba in
            let flash = FlashCalw(samba: samba)
            let identity = try flash.identify()
            guard identity.isSupported15C else {
                throw FlasherError.unsupportedDevice(name: identity.name, cidr: identity.cidr, exid: identity.exid)
            }
            saved = try flash.readApplication { progress?($0, .reading) }
            try saved.write(to: fileURL)
        }
        return saved
    }

    private func withClient(_ existing: SambaClient?, body: (SambaClient) throws -> Void) throws {
        if let existing {
            try body(existing)
            return
        }
        let connected = try connect()
        defer { connected.client.close() }
        guard connected.identity.isSupported15C else {
            throw FlasherError.unsupportedDevice(
                name: connected.identity.name,
                cidr: connected.identity.cidr,
                exid: connected.identity.exid
            )
        }
        try body(connected.client)
    }
}

public struct ConnectedTarget {
    public let port: SerialPort
    public let client: SambaClient
    public let identity: DeviceIdentity
}
