import Foundation

/// Bidirectional byte stream used by the SAM-BA client.
public protocol ByteTransport: AnyObject {
    func write(_ data: Data) throws
    /// Returns up to `maxCount` bytes, or empty if the timeout elapses with no data.
    func read(max maxCount: Int, timeout: TimeInterval) throws -> Data
    func close()
}

public extension ByteTransport {
    func read(exactly count: Int, timeout: TimeInterval) throws -> Data {
        precondition(count > 0)
        var result = Data()
        result.reserveCapacity(count)
        let deadline = Date().addingTimeInterval(timeout)
        while result.count < count {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                throw FlasherError.sambaTimeout()
            }
            let chunk = try read(max: count - result.count, timeout: remaining)
            if chunk.isEmpty {
                throw FlasherError.sambaTimeout()
            }
            result.append(chunk)
        }
        return result
    }

    func discardAvailable(timeout: TimeInterval = 0.15) throws {
        _ = try read(max: 4096, timeout: timeout)
    }
}
