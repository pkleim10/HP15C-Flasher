import Foundation

public enum WizardStep: Int, CaseIterable, Equatable, Hashable, Sendable {
    case cable
    case programmingMode
    case backup
    case firmware
    case flash
    case finish
    case checksum

    public var number: Int { rawValue + 1 }
    public static var count: Int { allCases.count }

    public var title: String {
        switch self {
        case .cable: return "Cable"
        case .programmingMode: return "Programming mode"
        case .backup: return "Backup"
        case .firmware: return "Firmware"
        case .flash: return "Flash"
        case .finish: return "Restart"
        case .checksum: return "Checksum"
        }
    }
}

public struct WizardState: Equatable, Sendable {
    public var step: WizardStep = .cable
    public var identitySupported = false
    public var backupResolved = false
    public var firmwareOK = false
    public var flashSucceeded = false
    public var isBusy = false

    public init() {}

    public var canGoBack: Bool {
        !isBusy && step != .cable
    }

    public var canAdvance: Bool {
        guard !isBusy else { return false }
        switch step {
        case .cable:
            return true
        case .programmingMode:
            return identitySupported
        case .backup:
            return backupResolved
        case .firmware:
            return firmwareOK
        case .flash:
            return flashSucceeded
        case .finish:
            return true
        case .checksum:
            return false
        }
    }

    public mutating func advance() {
        guard canAdvance, let next = WizardStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    public mutating func goBack() {
        guard canGoBack, let previous = WizardStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    public func isComplete(_ other: WizardStep) -> Bool {
        step.rawValue > other.rawValue
    }

    public func isUpcoming(_ other: WizardStep) -> Bool {
        step.rawValue < other.rawValue
    }
}
