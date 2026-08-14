import Foundation

/// Checksum shown on the HP 15C CE test menu (`g`+`ENTER`+`ON`, then `2`).
///
/// The ARM Voyager 2.C screen displays an 8-bit additive checksum as a
/// repeated byte (for example `0A0Ah`). Two matching halves are the whole
/// scheme — collision odds are 1 in 256.
public enum VoyagerFirmwareChecksum {
    /// Trailing `0x00` padding is ignored; the last remaining byte is the
    /// stored checksum. The displayed value is that byte duplicated.
    public static func displayedValue(of data: Data) -> UInt16 {
        let payload = trimmingTrailingZeros(data)
        guard payload.count >= 2 else { return 0 }
        let sum = payload.dropLast().reduce(UInt16(0)) { ($0 &+ UInt16($1)) & 0xFF }
        return (sum << 8) | sum
    }

    public static func formatted(_ value: UInt16) -> String {
        String(format: "%04Xh", value)
    }

    public static func formatted(of data: Data) -> String {
        formatted(displayedValue(of: data))
    }

    static func trimmingTrailingZeros(_ data: Data) -> Data {
        var end = data.count
        while end > 0, data[end - 1] == 0 {
            end -= 1
        }
        return data.prefix(end)
    }
}
