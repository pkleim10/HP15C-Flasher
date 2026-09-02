import Darwin
import Foundation

/// In-memory ATSAM4LC2C that speaks SAM-BA. Used by unit tests (delay 0) and
/// the hidden in-app simulator (small per-page delay so progress is visible).
public final class SimulatedCalculatorTransport: ByteTransport {
    public static let demoPort = SerialPort(path: "/dev/cu.usbmodemDEMO")

    /// Extra sleep per 512-byte flash page on `S`/`R` (0 in tests).
    public var operationDelay: TimeInterval
    public var memory = [UInt32: UInt8]()
    public var closed = false

    private var inbound = Data()
    private var outbound = Data()
    private var pendingPayload: (address: UInt32, remaining: Int, total: Int)?

    public init(operationDelay: TimeInterval = 0, preloadApplication: Bool = false) {
        self.operationDelay = operationDelay
        storeWord(FlashCalw.chipidCIDR, 0xAB0A07E0)
        storeWord(FlashCalw.chipidEXID, 0x0400000F)
        storeWord(FlashCalw.cpuid, 0x410FC241)
        storeWord(FlashCalw.fsr, FlashCalw.fsrFRDY)
        if preloadApplication {
            // Factory-style dump so DEMO backup assesses as 9090h (safe to proceed).
            for i in 0..<FlashLayout.expectedFirmwareByteCount {
                memory[FlashLayout.applicationStart &+ UInt32(i)] = 0
            }
            memory[FlashLayout.applicationStart] = 0x90
            memory[FlashLayout.applicationStart &+ 1] = 0x90
        }
    }

    public func storeWord(_ address: UInt32, _ value: UInt32) {
        for i in 0..<4 {
            memory[address &+ UInt32(i)] = UInt8((value >> (8 * i)) & 0xFF)
        }
    }

    public func loadWord(_ address: UInt32) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(memory[address &+ UInt32(i)] ?? 0xFF) << (8 * i)
        }
        return value
    }

    public func write(_ data: Data) throws {
        if closed { throw FlasherError.notConnected }
        if var pending = pendingPayload {
            let take = min(pending.remaining, data.count)
            for i in 0..<take {
                memory[pending.address &+ UInt32(i)] = data[data.startIndex + i]
            }
            pending.address &+= UInt32(take)
            pending.remaining -= take
            pendingPayload = pending.remaining > 0 ? pending : nil
            if pendingPayload == nil {
                delay(forBytes: pending.total)
            }
            if take < data.count {
                inbound.append(data.subdata(in: take..<data.count))
                try drainCommands()
            }
            return
        }
        inbound.append(data)
        try drainCommands()
    }

    public func read(max maxCount: Int, timeout: TimeInterval) throws -> Data {
        if closed { throw FlasherError.notConnected }
        if outbound.isEmpty {
            return Data()
        }
        let take = min(maxCount, outbound.count)
        let slice = outbound.prefix(take)
        outbound.removeFirst(take)
        return Data(slice)
    }

    public func close() {
        inbound.removeAll()
        outbound.removeAll()
        pendingPayload = nil
    }

    private func drainCommands() throws {
        while pendingPayload == nil {
            guard let hash = inbound.firstIndex(of: UInt8(ascii: "#")) else { return }
            let command = inbound.prefix(upTo: hash)
            inbound.removeSubrange(...hash)
            try handle(command: String(decoding: command, as: UTF8.self))
        }
        if let pending = pendingPayload, !inbound.isEmpty {
            let take = min(pending.remaining, inbound.count)
            var next = pending
            for i in 0..<take {
                memory[next.address &+ UInt32(i)] = inbound[inbound.startIndex + i]
            }
            inbound.removeFirst(take)
            next.address &+= UInt32(take)
            next.remaining -= take
            pendingPayload = next.remaining > 0 ? next : nil
            if pendingPayload == nil {
                delay(forBytes: next.total)
            }
        }
    }

    private func handle(command: String) throws {
        if command == "T" {
            outbound.append(contentsOf: Array("\r\n>".utf8))
            return
        }
        if command == "N" {
            outbound.append(contentsOf: Array("\r\n".utf8))
            return
        }
        if command == "V" {
            outbound.append(contentsOf: Array("v1.1 Dec 15 2013 19:03:14\r\n".utf8))
            return
        }
        if command.first == "w" {
            let address = try parseAddress(command)
            appendWordBytes(loadWord(address))
            return
        }
        if command.first == "W" {
            let (address, value) = try parseAddressValue(command)
            storeWord(address, value)
            if address == FlashCalw.fcmd {
                applyFlashCommand(value)
            }
            return
        }
        if command.first == "R" {
            let (address, length) = try parseAddressValue(command)
            delay(forBytes: Int(length))
            for i in 0..<Int(length) {
                outbound.append(memory[address &+ UInt32(i)] ?? 0xFF)
            }
            return
        }
        if command.first == "S" {
            let (address, length) = try parseAddressValue(command)
            pendingPayload = (address, Int(length), Int(length))
            return
        }
        if command.first == "G" {
            let address = try parseAddress(command)
            runOfficialApplet(goAddress: address)
            return
        }
        throw FlasherError.sambaProtocol("unknown command \(command)")
    }

    /// `G#` calls `[address+4]`. Official applet mailbox is at `0x20002040`.
    private func runOfficialApplet(goAddress: UInt32) {
        let mailbox = SambaFlashApplet.mailboxAddress
        if goAddress != SambaFlashApplet.goAddress {
            return
        }
        let cmd = loadWord(mailbox)
        var status: UInt32 = 0
        if cmd == SambaAppletCommand.initialize.rawValue {
            storeWord(mailbox &+ 0x08, 0x0002_0000)
            storeWord(mailbox &+ 0x0C, 0x2000_2C00)
            storeWord(mailbox &+ 0x10, 0x200)
            storeWord(mailbox &+ 0x14, 0x0010_2000)
            storeWord(mailbox &+ 0x18, 0x200)
            storeWord(mailbox &+ 0x1C, 256)
            storeWord(mailbox &+ 0x20, 32)
        } else if cmd == SambaAppletCommand.write.rawValue {
            let buffer = loadWord(mailbox &+ 0x08)
            let length = Int(loadWord(mailbox &+ 0x0C))
            let offset = loadWord(mailbox &+ 0x10)
            if offset < FlashLayout.applicationStart {
                storeWord(mailbox &+ 0x08, 0)
                status = 0x02
            } else {
                for i in 0..<length {
                    memory[offset &+ UInt32(i)] = memory[buffer &+ UInt32(i)] ?? 0xFF
                }
                storeWord(mailbox &+ 0x08, UInt32(length))
            }
        } else if cmd == SambaAppletCommand.unlock.rawValue {
            status = 0
        } else if cmd == SambaAppletCommand.erasePage.rawValue {
            let page = Int(loadWord(mailbox &+ 0x08))
            if page < 32 {
                status = 0x04
            } else {
                let pageAddress = UInt32(page * FlashCalw.pageSize)
                for i in 0..<FlashCalw.pageSize {
                    memory[pageAddress &+ UInt32(i)] = 0xFF
                }
            }
        } else if cmd == SambaAppletCommand.read.rawValue {
            let buffer = loadWord(mailbox &+ 0x08)
            let length = Int(loadWord(mailbox &+ 0x0C))
            let offset = loadWord(mailbox &+ 0x10)
            for i in 0..<length {
                memory[buffer &+ UInt32(i)] = memory[offset &+ UInt32(i)] ?? 0xFF
            }
            storeWord(mailbox &+ 0x08, UInt32(length))
        } else {
            status = 0x0F
        }
        storeWord(mailbox &+ 0x04, status)
        storeWord(mailbox, ~cmd)
    }

    private func applyFlashCommand(_ value: UInt32) {
        let cmd = value & 0x3F
        let page = Int((value >> 8) & 0xFFFF)
        let pageAddress = UInt32(page * FlashCalw.pageSize)
        if cmd == FlashCalw.cmdEP {
            for i in 0..<FlashCalw.pageSize {
                memory[pageAddress &+ UInt32(i)] = 0xFF
            }
        }
        storeWord(FlashCalw.fsr, FlashCalw.fsrFRDY)
    }

    private func delay(forBytes byteCount: Int) {
        guard operationDelay > 0, byteCount > 0 else { return }
        let pages = max(1, (byteCount + FlashCalw.pageSize - 1) / FlashCalw.pageSize)
        let usec = useconds_t((operationDelay * 1_000_000 * Double(pages)).rounded())
        if usec > 0 {
            usleep(min(usec, 500_000))
        }
    }

    private func appendWordBytes(_ value: UInt32) {
        outbound.append(UInt8(value & 0xFF))
        outbound.append(UInt8((value >> 8) & 0xFF))
        outbound.append(UInt8((value >> 16) & 0xFF))
        outbound.append(UInt8((value >> 24) & 0xFF))
    }

    private func parseAddress(_ command: String) throws -> UInt32 {
        let body = String(command.dropFirst())
        let addressHex = body.split(separator: ",").first.map(String.init) ?? ""
        guard let address = UInt32(addressHex, radix: 16) else {
            throw FlasherError.sambaProtocol("bad address in \(command)")
        }
        return address
    }

    private func parseAddressValue(_ command: String) throws -> (UInt32, UInt32) {
        let body = String(command.dropFirst())
        let parts = body.split(separator: ",")
        guard parts.count == 2,
              let address = UInt32(parts[0], radix: 16),
              let value = UInt32(parts[1], radix: 16) else {
            throw FlasherError.sambaProtocol("bad command \(command)")
        }
        return (address, value)
    }
}

public struct SimulatedPortListing: SerialPortListing {
    public init() {}

    public func listPorts() throws -> [SerialPort] {
        [SimulatedCalculatorTransport.demoPort]
    }
}
