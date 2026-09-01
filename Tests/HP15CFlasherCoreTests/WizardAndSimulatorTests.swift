import Foundation
import HP15CFlasherCore
import XCTest

final class WizardStateTests: XCTestCase {
    func testCableAlwaysAllowsAdvance() {
        var state = WizardState()
        XCTAssertTrue(state.canAdvance)
        state.advance()
        XCTAssertEqual(state.step, .programmingMode)
    }

    func testCannotLeaveProgrammingModeWithoutSupportedChip() {
        var state = WizardState()
        state.step = .programmingMode
        XCTAssertFalse(state.canAdvance)
        state.advance()
        XCTAssertEqual(state.step, .programmingMode)

        state.identitySupported = true
        XCTAssertTrue(state.canAdvance)
        state.advance()
        XCTAssertEqual(state.step, .backup)
    }

    func testBackupRequiresResolvedOrSkip() {
        var state = WizardState()
        state.step = .backup
        XCTAssertFalse(state.canAdvance)
        state.backupResolved = true
        XCTAssertTrue(state.canAdvance)
    }

    func testCannotFlashAdvanceWithoutFirmwareAndSuccess() {
        var state = WizardState()
        state.step = .firmware
        XCTAssertFalse(state.canAdvance)

        state.firmwareOK = true
        state.advance()
        XCTAssertEqual(state.step, .flash)
        XCTAssertFalse(state.canAdvance)

        state.flashSucceeded = true
        state.advance()
        XCTAssertEqual(state.step, .finish)
        XCTAssertTrue(state.canAdvance)

        state.advance()
        XCTAssertEqual(state.step, .checksum)
        XCTAssertFalse(state.canAdvance)
        XCTAssertEqual(WizardStep.count, 7)
    }

    func testBusyBlocksBackAndAdvance() {
        var state = WizardState()
        state.identitySupported = true
        state.step = .programmingMode
        state.isBusy = true
        XCTAssertFalse(state.canAdvance)
        XCTAssertFalse(state.canGoBack)
        state.isBusy = false
        XCTAssertTrue(state.canGoBack)
        state.goBack()
        XCTAssertEqual(state.step, .cable)
        XCTAssertFalse(state.canGoBack)
    }

    func testCompletedStepsAreThoseAlreadyLeft() {
        var state = WizardState()
        XCTAssertFalse(state.isComplete(.cable))
        XCTAssertTrue(state.isUpcoming(.programmingMode))

        state.identitySupported = true
        state.advance()
        state.advance()
        XCTAssertEqual(state.step, .backup)
        XCTAssertTrue(state.isComplete(.cable))
        XCTAssertTrue(state.isComplete(.programmingMode))
        XCTAssertFalse(state.isComplete(.backup))
        XCTAssertFalse(state.isUpcoming(.backup))
        XCTAssertTrue(state.isUpcoming(.firmware))
    }

    func testFirmwareFileMustBe112KBBeforeFlash() throws {
        var state = WizardState()
        state.step = .firmware
        XCTAssertThrowsError(try FirmwareImage.validate(Data(count: 16)))
        let valid = Data(count: FlashLayout.expectedFirmwareByteCount)
        XCTAssertNoThrow(try FirmwareImage.validate(valid))
        state.firmwareOK = true
        XCTAssertTrue(state.canAdvance)
    }
}

final class VoyagerFirmwareChecksumTests: XCTestCase {
    func testRepeatedByteFromAdditiveSum() {
        var payload = Data(repeating: 0x01, count: 9)
        payload.append(0x09)
        payload.append(contentsOf: Data(repeating: 0, count: 8))
        XCTAssertEqual(VoyagerFirmwareChecksum.displayedValue(of: payload), 0x0909)
        XCTAssertEqual(VoyagerFirmwareChecksum.formatted(of: payload), "0909h")
    }

    func testOfficialStyle0A0APattern() {
        var payload = Data(repeating: 0x02, count: 5)
        payload.append(0x0A)
        XCTAssertEqual(VoyagerFirmwareChecksum.formatted(of: payload), "0A0Ah")
        XCTAssertEqual(VoyagerFirmwareChecksum.testMenuDisplay(of: payload), "ChE - - 0A0Ah")
    }

    func testFactoryBackupIsOKToProceed() {
        let data = Data([0x90, 0x90])
        let assessment = VoyagerFirmwareChecksum.backupAssessment(of: data)
        XCTAssertEqual(assessment, .factoryOriginal(0x9090))
        XCTAssertTrue(assessment.message.contains("safe to proceed"))
        XCTAssertTrue(assessment.message.contains("factory installed"))
        XCTAssertFalse(assessment.message.contains("already installed"))
    }

    func testOfficial2024BackupIsVerifiedNotAlreadyInstalled() {
        let assessment = VoyagerFirmwareChecksum.backupAssessment(of: Data([0x0A, 0x0A]))
        XCTAssertEqual(assessment, .official2024(0x0A0A))
        XCTAssertTrue(assessment.message.contains("safe to proceed"))
        XCTAssertTrue(assessment.message.contains("recognized version"))
        XCTAssertFalse(assessment.message.contains("already installed"))
        XCTAssertEqual(
            VoyagerFirmwareChecksum.backupAssessment(of: Data([0xA0, 0xA0])),
            .unrecognized(0xA0A0)
        )
    }

    func testFirmwareFileKnownLatest() {
        let assessment = VoyagerFirmwareChecksum.firmwareFileAssessment(
            of: Data([0x0A, 0x0A]),
            backup: .factoryOriginal(0x9090),
            backupSkipped: false
        )
        XCTAssertEqual(assessment, .knownLatest(0x0A0A))
        XCTAssertTrue(assessment.message.contains("latest known firmware version"))
        XCTAssertFalse(assessment.isCaution)
    }

    func testFirmwareFileFactoryNotLatest() {
        let assessment = VoyagerFirmwareChecksum.firmwareFileAssessment(
            of: Data([0x90, 0x90]),
            backup: nil,
            backupSkipped: true
        )
        XCTAssertEqual(assessment, .factoryNotLatest(0x9090))
        XCTAssertTrue(assessment.message.contains("not the latest known version"))
        XCTAssertTrue(assessment.isCaution)
    }

    func testFirmwareFileDowngradeAndAlreadyOnCalculator() {
        XCTAssertEqual(
            VoyagerFirmwareChecksum.firmwareFileAssessment(
                of: Data([0x90, 0x90]),
                backup: .official2024(0x0A0A),
                backupSkipped: false
            ),
            .downgradeToFactory(0x9090)
        )
        XCTAssertEqual(
            VoyagerFirmwareChecksum.firmwareFileAssessment(
                of: Data([0x0A, 0x0A]),
                backup: .official2024(0x0A0A),
                backupSkipped: false
            ),
            .alreadyOnCalculator(0x0A0A)
        )
        XCTAssertEqual(
            VoyagerFirmwareChecksum.firmwareFileAssessment(
                of: Data([0x01, 0x01]),
                backup: nil,
                backupSkipped: true
            ),
            .unrecognized(0x0101)
        )
    }

    func testUnknownBackupWarns() {
        let assessment = VoyagerFirmwareChecksum.backupAssessment(of: Data([0x01, 0x01]))
        XCTAssertEqual(assessment, .unrecognized(0x0101))
        XCTAssertTrue(assessment.message.contains("not a recognized firmware version"))
        XCTAssertTrue(assessment.message.hasPrefix("Checksum 0101h."))
    }
}

final class SimulatedCalculatorTests: XCTestCase {
    func testDelayedWriteReportsIncreasingProgress() throws {
        let sim = SimulatedCalculatorTransport(operationDelay: 0.002, preloadApplication: true)
        let client = SambaClient(transport: sim)
        try client.connect()

        var image = Data(count: FlashLayout.expectedFirmwareByteCount)
        image[0] = 0x5A

        var samples: [Double] = []
        let started = Date()
        try FlashCalw(samba: client).writeApplication(image, progress: { fraction in
            samples.append(fraction)
        })
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThan(elapsed, 0.3)
        XCTAssertGreaterThan(samples.count, 5)
        let pairs = zip(samples, samples.dropFirst())
        XCTAssertTrue(pairs.allSatisfy { $0 <= $1 })
        XCTAssertEqual(samples.last, 1.0)
    }

    func testFlasherConnectsToSimulatedPort() throws {
        let sim = SimulatedCalculatorTransport(preloadApplication: true)
        let flasher = Flasher(
            ports: SimulatedPortListing(),
            openTransport: { _ in sim }
        )
        let connected = try flasher.connect()
        XCTAssertTrue(connected.identity.isSupported15C)
        XCTAssertEqual(connected.port.path, SimulatedCalculatorTransport.demoPort.path)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim-backup-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try flasher.read(to: url, client: connected.client)
        XCTAssertEqual(try Data(contentsOf: url).count, FlashLayout.expectedFirmwareByteCount)
    }
}
