import Foundation
import HP15CFlasherCore
import XCTest

final class FlashLayoutTests: XCTestCase {
    func testApplicationSizeMatchesOfficialDump() {
        XCTAssertEqual(FlashLayout.expectedFirmwareByteCount, 112 * 1024)
        XCTAssertEqual(FlashLayout.applicationStart, 0x4000)
        XCTAssertEqual(FlashLayout.applicationSize, 0x1C000)
    }

    func testSafeRangeRejectsBootloader() {
        XCTAssertFalse(FlashLayout.isSafeApplicationRange(address: 0, length: 16))
        XCTAssertFalse(FlashLayout.isSafeApplicationRange(address: 0x3FF0, length: 32))
        XCTAssertTrue(FlashLayout.isSafeApplicationRange(address: 0x4000, length: 0x1C000))
        XCTAssertFalse(FlashLayout.isSafeApplicationRange(address: 0x4000, length: 0x1C001))
        XCTAssertFalse(FlashLayout.isSafeApplicationRange(address: 0x4000, length: 0))
    }
}

final class FirmwareImageTests: XCTestCase {
    func testRejectsEmptyAndOversizedImages() {
        XCTAssertThrowsError(try FirmwareImage.validate(Data())) { error in
            XCTAssertEqual(error as? FlasherError, .firmwareEmpty)
        }

        let tooBig = Data(count: FlashLayout.expectedFirmwareByteCount + 1)
        XCTAssertThrowsError(try FirmwareImage.validate(tooBig)) { error in
            XCTAssertEqual(
                error as? FlasherError,
                .firmwareTooLarge(actual: tooBig.count, maximum: FlashLayout.expectedFirmwareByteCount)
            )
        }

        let short = Data(count: 16)
        XCTAssertThrowsError(try FirmwareImage.validate(short)) { error in
            XCTAssertEqual(
                error as? FlasherError,
                .firmwareWrongSize(actual: 16, expected: FlashLayout.expectedFirmwareByteCount)
            )
        }

        XCTAssertNoThrow(try FirmwareImage.validate(short, requireExactSize: false))
    }

    func testLoadFromTemporaryFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hp15c-test-\(UUID().uuidString).bin")
        let data = Data(count: FlashLayout.expectedFirmwareByteCount)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try FirmwareImage.load(from: url)
        XCTAssertEqual(image.byteCount, FlashLayout.expectedFirmwareByteCount)
    }
}

private struct FixedPortListing: SerialPortListing {
    var ports: [SerialPort]

    func listPorts() throws -> [SerialPort] {
        ports
    }
}

final class FlasherTests: XCTestCase {
    func testPlanWriteRefusesBootloaderAddress() throws {
        let url = try writeTempFirmware()
        defer { try? FileManager.default.removeItem(at: url) }

        let flasher = Flasher(ports: FixedPortListing(ports: []), requireExactFirmwareSize: true)
        XCTAssertThrowsError(try flasher.planWrite(firmwareURL: url, address: 0)) { error in
            XCTAssertEqual(error as? FlasherError, .writeWouldTouchBootloader(address: 0))
        }
    }

    func testWriteWithoutCableFailsSafely() throws {
        let url = try writeTempFirmware()
        defer { try? FileManager.default.removeItem(at: url) }

        let flasher = Flasher(ports: FixedPortListing(ports: []), requireExactFirmwareSize: true)
        XCTAssertThrowsError(try flasher.write(firmwareURL: url)) { error in
            XCTAssertEqual(error as? FlasherError, .noProgrammingCable)
        }
    }

    func testWriteWithMockCableProgramsApplicationFlash() throws {
        let url = try writeTempFirmware()
        defer { try? FileManager.default.removeItem(at: url) }

        let port = SerialPort(path: "/dev/cu.usbmodemTEST")
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        let flasher = Flasher(ports: FixedPortListing(ports: [port]), requireExactFirmwareSize: true)
        try flasher.write(firmwareURL: url, client: client)
        let dumped = try client.read(
            from: FlashLayout.applicationStart,
            length: FlashLayout.expectedFirmwareByteCount
        )
        XCTAssertEqual(dumped.count, FlashLayout.expectedFirmwareByteCount)
    }

    func testProgrammingCableDetection() {
        let ports = [
            SerialPort(path: "/dev/cu.Bluetooth-Incoming-Port"),
            SerialPort(path: "/dev/cu.usbmodem21401"),
            SerialPort(path: "/dev/cu.debug-console"),
        ]
        XCTAssertEqual(ports.programmingCables.map(\.path), ["/dev/cu.usbmodem21401"])
    }

    private func writeTempFirmware() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hp15c-fw-\(UUID().uuidString).bin")
        try Data(count: FlashLayout.expectedFirmwareByteCount).write(to: url)
        return url
    }
}
