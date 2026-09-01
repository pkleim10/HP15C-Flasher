import Foundation

/// Checksum shown on the HP 15C CE test menu (`g`+`ENTER`+`ON`, then `2`).
///
/// The ARM Voyager 2.C screen displays an 8-bit additive checksum as a
/// repeated byte (for example `0A0Ah`). Two matching halves are the whole
/// scheme — collision odds are 1 in 256.
public enum VoyagerFirmwareChecksum {
    /// Factory Collector’s Edition image (test menu `9090h`).
    public static let factoryDisplayed: UInt16 = 0x9090

    /// Official 2024-06-03 / 120 ms image (test menu `0A0Ah`).
    public static let official2024Displayed: UInt16 = 0x0A0A

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

    /// LCD line after 2.C, for example `ChE - - 0A0Ah`.
    public static func testMenuDisplay(_ value: UInt16) -> String {
        "ChE - - \(formatted(value))"
    }

    public static func testMenuDisplay(of data: Data) -> String {
        testMenuDisplay(displayedValue(of: data))
    }

    public static func backupAssessment(of data: Data) -> BackupChecksumAssessment {
        BackupChecksumAssessment(displayed: displayedValue(of: data))
    }

    public static func firmwareFileAssessment(
        of data: Data,
        backup: BackupChecksumAssessment?,
        backupSkipped: Bool
    ) -> FirmwareFileAssessment {
        FirmwareFileAssessment(
            displayed: displayedValue(of: data),
            backup: backupSkipped ? nil : backup
        )
    }

    static func trimmingTrailingZeros(_ data: Data) -> Data {
        var end = data.count
        while end > 0, data[end - 1] == 0 {
            end -= 1
        }
        return data.prefix(end)
    }
}

/// Result of checking a just-saved backup against known stock images.
/// Does not assume which `.bin` the user will flash next.
public enum BackupChecksumAssessment: Equatable, Sendable {
    /// `9090h` — factory image; backup looks intact.
    case factoryOriginal(UInt16)
    /// `0A0Ah` — 2024 official image; backup looks intact.
    case official2024(UInt16)
    /// Any other displayed checksum.
    case unrecognized(UInt16)

    public init(displayed: UInt16) {
        switch displayed {
        case VoyagerFirmwareChecksum.factoryDisplayed:
            self = .factoryOriginal(displayed)
        case VoyagerFirmwareChecksum.official2024Displayed:
            self = .official2024(displayed)
        default:
            self = .unrecognized(displayed)
        }
    }

    public var displayed: UInt16 {
        switch self {
        case .factoryOriginal(let value), .official2024(let value), .unrecognized(let value):
            return value
        }
    }

    public var isRecognized: Bool {
        switch self {
        case .factoryOriginal, .official2024:
            return true
        case .unrecognized:
            return false
        }
    }

    public var message: String {
        let label = VoyagerFirmwareChecksum.formatted(displayed)
        switch self {
        case .factoryOriginal:
            return "Checksum \(label). This is the recognized factory installed firmware. It is safe to proceed."
        case .official2024:
            return "Checksum \(label): This is a recognized version of the firmware. It is safe to proceed."
        case .unrecognized:
            return "Checksum \(label). This is not a recognized firmware version. If you know you are currently using a custom version of the firmware, proceed at your own risk. If you are currently using the factory installed firmware, there may be a problem with the backup."
        }
    }
}

/// Verdict for a `.bin` the user picked to flash — independent of the backup dump’s health.
public enum FirmwareFileAssessment: Equatable, Sendable {
    /// Chosen file matches the backup already on the calculator.
    case alreadyOnCalculator(UInt16)
    /// Official 2024-06-03 / 120 ms image (`0A0Ah`).
    case knownLatest(UInt16)
    /// Factory image (`9090h`) while the calculator currently has the 2024 image.
    case downgradeToFactory(UInt16)
    /// Factory image (`9090h`), not the latest known drop.
    case factoryNotLatest(UInt16)
    /// Checksum is not 9090h or 0A0Ah.
    case unrecognized(UInt16)

    public init(displayed: UInt16, backup: BackupChecksumAssessment?) {
        if let backup, backup.displayed == displayed {
            self = .alreadyOnCalculator(displayed)
            return
        }
        switch displayed {
        case VoyagerFirmwareChecksum.official2024Displayed:
            self = .knownLatest(displayed)
        case VoyagerFirmwareChecksum.factoryDisplayed:
            if case .official2024 = backup {
                self = .downgradeToFactory(displayed)
            } else {
                self = .factoryNotLatest(displayed)
            }
        default:
            self = .unrecognized(displayed)
        }
    }

    public var displayed: UInt16 {
        switch self {
        case .alreadyOnCalculator(let value),
             .knownLatest(let value),
             .downgradeToFactory(let value),
             .factoryNotLatest(let value),
             .unrecognized(let value):
            return value
        }
    }

    public var isCaution: Bool {
        switch self {
        case .knownLatest:
            return false
        case .alreadyOnCalculator, .downgradeToFactory, .factoryNotLatest, .unrecognized:
            return true
        }
    }

    public var message: String {
        let label = VoyagerFirmwareChecksum.formatted(displayed)
        switch self {
        case .alreadyOnCalculator:
            return "Checksum \(label). This firmware is already on the calculator. You don’t need to install it again."
        case .knownLatest:
            return "Checksum \(label). This is the latest known firmware version. It is safe to proceed."
        case .downgradeToFactory:
            return "Checksum \(label). This is the factory-installed firmware. The calculator currently has a newer recognized version. Are you sure you want to install it?"
        case .factoryNotLatest:
            return "Checksum \(label). This is the factory-installed firmware. It is not the latest known version. Are you sure you want to install it?"
        case .unrecognized:
            return "Checksum \(label). This is not a known firmware version. You may have selected the wrong file, or firmware meant for a different calculator. Are you sure you want to install it?"
        }
    }
}
