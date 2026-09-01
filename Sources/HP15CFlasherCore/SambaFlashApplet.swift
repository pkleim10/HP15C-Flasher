import Foundation

/// Official SAM-BA 2.16 SAM4L flash applet (`applet-flash-sam4l4.bin`).
/// Copyright (c) 2011–2012 Atmel Corporation. See `THIRD_PARTY.md`.
///
/// `G#` is a vector-table **call** at `loadAddress` (not a Thumb PC). The host
/// waits by polling mailbox command until it equals `~cmd`. Never issues
/// host `W#` to FLASHCALW.
public enum SambaAppletCommand: UInt32 {
    case initialize = 0x00
    case write = 0x02
    case read = 0x03
    case lock = 0x04
    case unlock = 0x05
    case erasePage = 0x44
}

public struct SambaAppletInfo: Equatable, Sendable {
    public var memorySize: UInt32
    public var bufferAddress: UInt32
    public var bufferSize: UInt32
    public var pageSize: UInt32
    public var pageCount: UInt32
    public var appStartPage: UInt32
    public var lockRegionSize: UInt16
    public var lockBitCount: UInt16
}

public final class SambaFlashApplet {
    public static let loadAddress: UInt32 = 0x2000_2000
    public static let mailboxAddress: UInt32 = 0x2000_2040
    public static let goAddress: UInt32 = 0x2000_2000
    public static var image: Data { Data(imageBytes) }

    private let samba: SambaClient
    /// Official `GENERIC::Run` waits 10 ms after `G#` before the first poll.
    public var goDelay: TimeInterval
    public private(set) var info: SambaAppletInfo?

    public init(samba: SambaClient, goDelay: TimeInterval = 0) {
        self.samba = samba
        self.goDelay = goDelay
        if goDelay > 0 {
            samba.afterSendDelay = 0.020
        }
    }

    public func upload() throws {
        samba.discardAvailable(timeout: 0.05)
        try samba.write(to: Self.loadAddress, data: Self.image)
    }

    @discardableResult
    public func initialize(
        comType: UInt32 = 0,
        traceLevel: UInt32 = 0,
        bank: UInt32 = 0
    ) throws -> SambaAppletInfo {
        try samba.writeWord(Self.mailboxAddress, value: SambaAppletCommand.initialize.rawValue)
        try samba.writeWord(Self.mailboxAddress &+ 0x04, value: 0)
        try samba.writeWord(Self.mailboxAddress &+ 0x08, value: comType)
        try samba.writeWord(Self.mailboxAddress &+ 0x0C, value: traceLevel)
        try samba.writeWord(Self.mailboxAddress &+ 0x10, value: bank)
        try run(.initialize)
        let lockWord = try samba.readWord(Self.mailboxAddress &+ 0x14)
        let loaded = SambaAppletInfo(
            memorySize: try samba.readWord(Self.mailboxAddress &+ 0x08),
            bufferAddress: try samba.readWord(Self.mailboxAddress &+ 0x0C),
            bufferSize: try samba.readWord(Self.mailboxAddress &+ 0x10),
            pageSize: try samba.readWord(Self.mailboxAddress &+ 0x18),
            pageCount: try samba.readWord(Self.mailboxAddress &+ 0x1C),
            appStartPage: try samba.readWord(Self.mailboxAddress &+ 0x20),
            lockRegionSize: UInt16(truncatingIfNeeded: lockWord),
            lockBitCount: UInt16(truncatingIfNeeded: lockWord >> 16)
        )
        guard loaded.bufferAddress != 0, loaded.bufferSize > 0, loaded.pageSize > 0 else {
            throw FlasherError.sambaProtocol("applet INIT returned an empty buffer")
        }
        info = loaded
        return loaded
    }

    @discardableResult
    public func loadAndInitialize(
        comType: UInt32 = 0,
        traceLevel: UInt32 = 0,
        bank: UInt32 = 0
    ) throws -> SambaAppletInfo {
        try upload()
        return try initialize(comType: comType, traceLevel: traceLevel, bank: bank)
    }

    public func unlockRegion(_ region: Int) throws {
        try samba.writeWord(Self.mailboxAddress, value: SambaAppletCommand.unlock.rawValue)
        try samba.writeWord(Self.mailboxAddress &+ 0x04, value: 0)
        try samba.writeWord(Self.mailboxAddress &+ 0x08, value: UInt32(region))
        try run(.unlock)
    }

    public func write(flashOffset: UInt32, data: Data) throws -> Int {
        guard flashOffset >= FlashLayout.applicationStart else {
            throw FlasherError.writeWouldTouchBootloader(address: flashOffset)
        }
        guard let info else {
            throw FlasherError.sambaProtocol("flash applet is not initialized")
        }
        guard !data.isEmpty, data.count <= Int(info.bufferSize) else {
            throw FlasherError.sambaProtocol("applet WRITE size \(data.count) exceeds buffer \(info.bufferSize)")
        }
        try samba.write(to: info.bufferAddress, data: data)
        try samba.writeWord(Self.mailboxAddress, value: SambaAppletCommand.write.rawValue)
        try samba.writeWord(Self.mailboxAddress &+ 0x04, value: 0)
        try samba.writeWord(Self.mailboxAddress &+ 0x08, value: info.bufferAddress)
        try samba.writeWord(Self.mailboxAddress &+ 0x0C, value: UInt32(data.count))
        try samba.writeWord(Self.mailboxAddress &+ 0x10, value: flashOffset)
        try run(.write)
        return Int(try samba.readWord(Self.mailboxAddress &+ 0x08))
    }

    /// `G#` then poll mailbox+0 until the word equals `~command`.
    ///
    /// Matches SAM-BA 2.16 `GENERIC::Run` (Windows): 10 ms, then up to 10 reads
    /// with 1 s between tries (25 for erase). Do not re-issue `w#` in a tight
    /// loop on USB NACK — that desyncs the monitor after a page program.
    func run(_ command: SambaAppletCommand, timeout: TimeInterval = 12) throws {
        try samba.go(Self.goAddress)
        let firstWait = firstPollDelay(for: command)
        if firstWait > 0 {
            Thread.sleep(forTimeInterval: firstWait)
        }
        let expected = ~command.rawValue
        let retries = command == .erasePage ? 25 : 10
        let deadline = Date().addingTimeInterval(timeout)
        for attempt in 0..<retries {
            if Date() >= deadline {
                break
            }
            do {
                let word = try samba.readWord(Self.mailboxAddress, timeout: 1.0)
                if word == expected {
                    let status = try samba.readWord(Self.mailboxAddress &+ 0x04)
                    if status != 0 {
                        throw FlasherError.appletFailed(status: status)
                    }
                    return
                }
            } catch {
                if case FlasherError.sambaTimeout = error {
                    if goDelay > 0, attempt + 1 < retries {
                        Thread.sleep(forTimeInterval: 1.0)
                    }
                    continue
                }
                throw error
            }
            if goDelay > 0, attempt + 1 < retries {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
        throw FlasherError.sambaTimeout(
            "Timed out waiting for the SAM-BA flash applet (command 0x\(String(command.rawValue, radix: 16))). Leave the cable plugged in. If Status is not Connected, hold ERASE, press RESET, then release ERASE."
        )
    }

    /// Every applet command may touch FLASHCALW (`flashcalw_get_flash_size` runs
    /// on entry). USB NACKs until that returns; do not send `w#` during it.
    private func firstPollDelay(for command: SambaAppletCommand) -> TimeInterval {
        guard goDelay > 0 else { return 0 }
        _ = command
        return max(goDelay, 0.100)
    }
}
