import Darwin
import Foundation

/// Raw 8N1 serial link on a `/dev/cu.*` node (CDC ACM for the HP pogo cable).
public final class POSIXSerialLink: ByteTransport {
    private var fd: Int32 = -1
    public let path: String

    public init(path: String, baud: speed_t = speed_t(B115200)) throws {
        self.path = path
        let opened = path.withCString { Darwin.open($0, O_RDWR | O_NOCTTY | O_NONBLOCK) }
        guard opened >= 0 else {
            throw FlasherError.serialOpenFailed(path)
        }
        fd = opened

        var tio = termios()
        guard tcgetattr(fd, &tio) == 0 else {
            close()
            throw FlasherError.serialOpenFailed(path)
        }
        cfmakeraw(&tio)
        cfsetispeed(&tio, baud)
        cfsetospeed(&tio, baud)
        tio.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tio.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        tio.c_cflag = (tio.c_cflag & ~tcflag_t(CSIZE)) | tcflag_t(CS8)
        withUnsafeMutableBytes(of: &tio.c_cc) { buf in
            buf[Int(VMIN)] = 0
            buf[Int(VTIME)] = 0
        }
        guard tcsetattr(fd, TCSANOW, &tio) == 0 else {
            close()
            throw FlasherError.serialOpenFailed(path)
        }
        _ = tcflush(fd, TCIOFLUSH)
    }

    deinit {
        close()
    }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var sent = 0
            let total = raw.count
            let base = raw.bindMemory(to: UInt8.self).baseAddress
            while sent < total {
                let n = Darwin.write(fd, base! + sent, total - sent)
                if n < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                        usleep(2000)
                        continue
                    }
                    throw FlasherError.sambaProtocol("serial write failed (errno \(errno))")
                }
                sent += n
            }
        }
    }

    public func read(max maxCount: Int, timeout: TimeInterval) throws -> Data {
        guard fd >= 0 else { throw FlasherError.notConnected }
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: max(1, maxCount))
        while true {
            let n = Darwin.read(fd, &buffer, maxCount)
            if n > 0 {
                return Data(buffer[0..<n])
            }
            if n == 0 {
                throw FlasherError.sambaProtocol("serial port closed")
            }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                if Date() >= deadline {
                    return Data()
                }
                usleep(2000)
                continue
            }
            throw FlasherError.sambaProtocol("serial read failed (errno \(errno))")
        }
    }

    public func close() {
        if fd >= 0 {
            _ = Darwin.close(fd)
            fd = -1
        }
    }
}
