import Foundation

/// Atmel SAM-BA monitor client (non-interactive / binary mode).
public final class SambaClient {
    public static let defaultTimeout: TimeInterval = 3
    public static let blockSize = 4096

    private let transport: ByteTransport
    public private(set) var version: String = ""

    public init(transport: ByteTransport) {
        self.transport = transport
    }

    public func connect(timeout: TimeInterval = defaultTimeout) throws {
        try transport.write(Data("T#".utf8))
        _ = try readUntilPromptOrTimeout(timeout: min(1.0, timeout))

        try transport.write(Data("N#".utf8))
        try transport.discardAvailable(timeout: 0.2)

        try transport.write(Data("V#".utf8))
        version = try readASCIILine(timeout: timeout)
        if version.isEmpty {
            throw FlasherError.sambaProtocol("empty version string")
        }
    }

    public func readWord(_ address: UInt32, timeout: TimeInterval = defaultTimeout) throws -> UInt32 {
        try sendCommand(String(format: "w%08X,4#", address))
        let bytes = try transport.read(exactly: 4, timeout: timeout)
        return UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
    }

    public func writeWord(_ address: UInt32, value: UInt32) throws {
        try sendCommand(String(format: "W%08X,%08X#", address, value))
    }

    public func read(from address: UInt32, length: Int, timeout: TimeInterval = 30) throws -> Data {
        guard length > 0 else { return Data() }
        var result = Data()
        result.reserveCapacity(length)
        var offset = 0
        while offset < length {
            let chunk = min(Self.blockSize, length - offset)
            let addr = address &+ UInt32(offset)
            try sendCommand(String(format: "R%08X,%08X#", addr, UInt32(chunk)))
            result.append(try transport.read(exactly: chunk, timeout: timeout))
            offset += chunk
        }
        return result
    }

    public func write(to address: UInt32, data: Data) throws {
        guard !data.isEmpty else { return }
        var offset = 0
        while offset < data.count {
            let chunk = min(Self.blockSize, data.count - offset)
            let slice = data.subdata(in: offset..<(offset + chunk))
            let addr = address &+ UInt32(offset)
            try sendCommand(String(format: "S%08X,%08X#", addr, UInt32(chunk)))
            try transport.write(slice)
            offset += chunk
        }
    }

    public func close() {
        transport.close()
    }

    private func sendCommand(_ command: String) throws {
        try transport.write(Data(command.utf8))
    }

    private func readASCIILine(timeout: TimeInterval) throws -> String {
        var collected = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let chunk = try transport.read(max: 64, timeout: max(0.05, deadline.timeIntervalSinceNow))
            if chunk.isEmpty {
                continue
            }
            collected.append(chunk)
            if let nl = collected.firstIndex(of: 0x0A) {
                let line = collected.prefix(upTo: nl)
                return String(decoding: line, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        throw FlasherError.sambaTimeout
    }

    private func readUntilPromptOrTimeout(timeout: TimeInterval) throws -> Data {
        var collected = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let chunk = try transport.read(max: 64, timeout: max(0.05, deadline.timeIntervalSinceNow))
            if chunk.isEmpty {
                break
            }
            collected.append(chunk)
            if collected.contains(UInt8(ascii: ">")) {
                break
            }
        }
        return collected
    }
}
