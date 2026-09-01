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
    /// Official SAM-BA `GENERIC::Run` delay after `G#` before the first mailbox poll.
    public var commandSettleSeconds: TimeInterval

    public init(samba: SambaClient, commandSettleSeconds: TimeInterval = 0) {
        self.samba = samba
        self.commandSettleSeconds = commandSettleSeconds
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

    public func writeApplication(_ data: Data, progress: Progress? = nil, verifyProgress: Progress? = nil, verify: Bool = true) throws {
        try FirmwareImage.validate(data, requireExactSize: true)
        let address = FlashLayout.applicationStart
        guard FlashLayout.isSafeApplicationRange(address: address, length: UInt32(data.count)) else {
            throw FlasherError.writeWouldTouchBootloader(address: address)
        }

        let identity = try withTimeout("identifying the calculator", identify)
        guard identity.isSupported15C else {
            throw FlasherError.unsupportedDevice(name: identity.name, cidr: identity.cidr, exid: identity.exid)
        }

        let applet = SambaFlashApplet(samba: samba, goDelay: commandSettleSeconds)
        try withTimeout("uploading the flash applet") {
            try applet.upload()
        }
        let info = try withTimeout("starting the flash applet") {
            try applet.initialize()
        }
        try withTimeout("unlocking flash") {
            try unlockApplicationRegions(using: applet, info: info)
        }

        let pageSize = Int(info.pageSize == 0 ? UInt32(Self.pageSize) : info.pageSize)
        let pageCount = (data.count + pageSize - 1) / pageSize
        for index in 0..<pageCount {
            let flashOffset = address &+ UInt32(index * pageSize)
            if flashOffset < FlashLayout.applicationStart {
                throw FlasherError.writeWouldTouchBootloader(address: flashOffset)
            }
            var pageData = data.subdata(in: (index * pageSize)..<min((index + 1) * pageSize, data.count))
            if pageData.count < pageSize {
                pageData.append(Data(repeating: 0xFF, count: pageSize - pageData.count))
            }
            _ = try withTimeout("writing page \(index + 1) of \(pageCount)") {
                try applet.write(flashOffset: flashOffset, data: pageData)
            }
            progress?(Double(index + 1) / Double(pageCount))
        }
        progress?(1.0)
        guard verify else { return }

        try verifyApplication(data, progress: verifyProgress)
    }

    public func verifyApplication(_ data: Data, progress: Progress? = nil) throws {
        try FirmwareImage.validate(data, requireExactSize: true)
        progress?(0)
        let readback = try withTimeout("verifying firmware") {
            try readApplication { fraction in
                progress?(fraction)
            }
        }
        if readback != data {
            throw FlasherError.verifyMismatch
        }
        progress?(1.0)
    }

    private func unlockApplicationRegions(using applet: SambaFlashApplet, info: SambaAppletInfo) throws {
        let lockBits = max(1, Int(info.lockBitCount == 0 ? UInt16(Self.lockRegions) : info.lockBitCount))
        let pageCount = Int(info.pageCount == 0 ? 256 : info.pageCount)
        let pagesPerRegion = max(1, pageCount / lockBits)
        let firstAppPage = Int(info.appStartPage == 0 ? 32 : info.appStartPage)
        let firstRegion = firstAppPage / pagesPerRegion
        for region in firstRegion..<lockBits {
            do {
                try applet.unlockRegion(region)
            } catch {
                if case FlasherError.appletFailed = error {
                    continue
                }
                throw error
            }
        }
    }

    private func withTimeout<T>(_ stage: String, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            if case FlasherError.sambaTimeout = error {
                throw timeoutError(stage)
            }
            throw error
        }
    }

    private func timeoutError(_ stage: String) -> FlasherError {
        .sambaTimeout(
            "Timed out \(stage). Leave the cable plugged in. If Status is not Connected, hold ERASE, press RESET, then release ERASE."
        )
    }

}
