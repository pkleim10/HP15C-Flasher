import Darwin
import Foundation

/// CHIPID / CPUID snapshot for the calculator MCU.
public struct DeviceIdentity: Equatable, Sendable {
    public let cidr: UInt32
    public let exid: UInt32
    public let cpuid: UInt32
    public let name: String
    public let flashBytes: Int

    public var isSupported15C: Bool {
        flashBytes == FlashLayout.expectedFirmwareByteCount + Int(FlashLayout.bootloaderSize)
            && isCortexM4
            && isSAM4L
    }

    public var isCortexM4: Bool {
        ((cpuid >> 4) & 0xFFF) == 0xC24
    }

    public var isSAM4L: Bool {
        // ARCH field (bits 20–27) is 0xB0 for SAM4L.
        ((cidr >> 20) & 0xFF) == 0xB0
    }

    public init(cidr: UInt32, exid: UInt32, cpuid: UInt32, name: String, flashBytes: Int) {
        self.cidr = cidr
        self.exid = exid
        self.cpuid = cpuid
        self.name = name
        self.flashBytes = flashBytes
    }
}

enum SAM4LChipTable {
    /// CIDR values from the SAM4L datasheet (version nibble may vary).
    static let cidr128KB: UInt32 = 0xAB0A07E0
    static let cidrMask: UInt32 = 0xFFFFFFE0

    static let known: [(cidr: UInt32, exid: UInt32, name: String, flashKB: Int)] = [
        (0xAB0A07E0, 0x0400000F, "ATSAM4LC2C", 128),
        (0xAB0A07E0, 0x0300000F, "ATSAM4LC2B", 128),
        (0xAB0A07E0, 0x0200000F, "ATSAM4LC2A", 128),
        (0xAB0A07E0, 0x04000002, "ATSAM4LS2C", 128),
        (0xAB0A07E0, 0x03000002, "ATSAM4LS2B", 128),
        (0xAB0A07E0, 0x02000002, "ATSAM4LS2A", 128),
        (0xAB0A09E0, 0x0400000F, "ATSAM4LC4C", 256),
        (0xAB0B0AE0, 0x1400000F, "ATSAM4LC8C", 512),
    ]

    static func identify(cidr: UInt32, exid: UInt32, cpuid: UInt32) -> DeviceIdentity {
        if let match = known.first(where: {
            ($0.cidr & cidrMask) == (cidr & cidrMask) && $0.exid == exid
        }) {
            return DeviceIdentity(
                cidr: cidr,
                exid: exid,
                cpuid: cpuid,
                name: match.name,
                flashBytes: match.flashKB * 1024
            )
        }
        if (cidr & cidrMask) == (cidr128KB & cidrMask) {
            return DeviceIdentity(
                cidr: cidr,
                exid: exid,
                cpuid: cpuid,
                name: "ATSAM4Lx2",
                flashBytes: 128 * 1024
            )
        }
        return DeviceIdentity(
            cidr: cidr,
            exid: exid,
            cpuid: cpuid,
            name: "unknown",
            flashBytes: 0
        )
    }
}

/// FLASHCALW programming for SAM4L via the SAM-BA monitor. Never issues Erase All.
public final class FlashCalw {
    public static let chipidCIDR: UInt32 = 0x400E0740
    public static let chipidEXID: UInt32 = 0x400E0744
    public static let cpuid: UInt32 = 0xE000ED00
    public static let base: UInt32 = 0x400A0000
    public static let fcmd: UInt32 = 0x400A0004
    public static let fsr: UInt32 = 0x400A0008
    public static let pageSize = 512
    public static let lockRegions = 16
    public static let commandKey: UInt32 = 0xA5
    public static let cmdWP: UInt32 = 1
    public static let cmdEP: UInt32 = 2
    public static let cmdCPB: UInt32 = 3
    public static let cmdUP: UInt32 = 5
    public static let fsrFRDY: UInt32 = 1 << 0
    public static let fsrLOCKE: UInt32 = 1 << 2
    public static let fsrPROGE: UInt32 = 1 << 3

    public typealias Progress = (Double) -> Void

    private let samba: SambaClient

    public init(samba: SambaClient) {
        self.samba = samba
    }

    public func identify() throws -> DeviceIdentity {
        let cpuid = try samba.readWord(Self.cpuid)
        let cidr = try samba.readWord(Self.chipidCIDR)
        let exid = try samba.readWord(Self.chipidEXID)
        return SAM4LChipTable.identify(cidr: cidr, exid: exid, cpuid: cpuid)
    }

    public func readApplication(progress: Progress? = nil) throws -> Data {
        let total = FlashLayout.expectedFirmwareByteCount
        var data = Data()
        data.reserveCapacity(total)
        var offset = 0
        while offset < total {
            let chunk = min(SambaClient.blockSize, total - offset)
            let part = try samba.read(
                from: FlashLayout.applicationStart &+ UInt32(offset),
                length: chunk
            )
            data.append(part)
            offset += chunk
            progress?(Double(offset) / Double(total))
        }
        return data
    }

    public func writeApplication(_ data: Data, progress: Progress? = nil, verifyProgress: Progress? = nil) throws {
        try FirmwareImage.validate(data, requireExactSize: true)
        let address = FlashLayout.applicationStart
        guard FlashLayout.isSafeApplicationRange(address: address, length: UInt32(data.count)) else {
            throw FlasherError.writeWouldTouchBootloader(address: address)
        }

        let identity = try identify()
        guard identity.isSupported15C else {
            throw FlasherError.unsupportedDevice(name: identity.name, cidr: identity.cidr, exid: identity.exid)
        }

        try waitReady()
        try unlockApplicationRegions()

        let startPage = Int(address) / Self.pageSize
        let pageCount = (data.count + Self.pageSize - 1) / Self.pageSize
        for index in 0..<pageCount {
            let page = startPage + index
            let pageAddress = UInt32(page * Self.pageSize)
            if pageAddress < FlashLayout.applicationStart {
                throw FlasherError.writeWouldTouchBootloader(address: pageAddress)
            }

            var pageData: Data
            let start = index * Self.pageSize
            let end = min(start + Self.pageSize, data.count)
            pageData = data.subdata(in: start..<end)
            if pageData.count < Self.pageSize {
                pageData.append(Data(repeating: 0xFF, count: Self.pageSize - pageData.count))
            }

            try issue(command: Self.cmdEP, page: page)
            try waitReady()
            try checkStatus()

            try issue(command: Self.cmdCPB, page: 0)
            try waitReady()

            try samba.write(to: pageAddress, data: pageData)
            try issue(command: Self.cmdWP, page: page)
            try waitReady()
            try checkStatus()

            progress?(Double(index + 1) / Double(pageCount))
        }
        progress?(1.0)
        Thread.sleep(forTimeInterval: 1.0)

        verifyProgress?(0)
        let readback = try readApplication { fraction in
            verifyProgress?(fraction)
        }
        if readback != data {
            throw FlasherError.verifyMismatch
        }
        verifyProgress?(1.0)
    }

    private var pagesPerRegion: Int {
        // 128 KB / 512 B = 256 pages, 16 lock regions.
        (128 * 1024 / Self.pageSize) / Self.lockRegions
    }

    private func unlockApplicationRegions() throws {
        let firstAppPage = Int(FlashLayout.applicationStart) / Self.pageSize
        let firstRegion = firstAppPage / pagesPerRegion
        for region in firstRegion..<Self.lockRegions {
            let page = region * pagesPerRegion
            try issue(command: Self.cmdUP, page: page)
            try waitReady()
            try checkStatus()
        }
    }

    private func issue(command: UInt32, page: Int) throws {
        let value = (Self.commandKey << 24) | (UInt32(page & 0xFFFF) << 8) | (command & 0x3F)
        try samba.writeWord(Self.fcmd, value: value)
    }

    private func waitReady(timeout: TimeInterval = 5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = try samba.readWord(Self.fsr)
            if status & Self.fsrFRDY != 0 {
                return
            }
            usleep(1000)
        }
        throw FlasherError.sambaTimeout
    }

    private func checkStatus() throws {
        let status = try samba.readWord(Self.fsr)
        if status & (Self.fsrLOCKE | Self.fsrPROGE) != 0 {
            throw FlasherError.flashControllerError(status: status)
        }
    }
}
