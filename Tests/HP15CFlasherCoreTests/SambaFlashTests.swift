import Foundation
import HP15CFlasherCore
import XCTest

final class SambaClientTests: XCTestCase {
    func testConnectReadsVersion() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        XCTAssertTrue(client.version.contains("v1.1"))
    }

    func testReadAndWriteWord() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        XCTAssertEqual(try client.readWord(FlashCalw.chipidCIDR), 0xAB0A07E0)
        try client.writeWord(0x20000000, value: 0x11223344)
        XCTAssertEqual(try client.readWord(0x20000000), 0x11223344)
    }

    func testBlockReadWrite() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        let payload = Data((0..<1024).map { UInt8($0 & 0xFF) })
        try client.write(to: 0x20001000, data: payload)
        XCTAssertEqual(try client.read(from: 0x20001000, length: payload.count), payload)
    }
}

final class FlashCalwTests: XCTestCase {
    func testIdentifyATSAM4LC2C() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        let identity = try FlashCalw(samba: client).identify()
        XCTAssertEqual(identity.name, "ATSAM4LC2C")
        XCTAssertTrue(identity.isSupported15C)
    }

    func testRejectUnknownChip() throws {
        let mock = SimulatedCalculatorTransport()
        mock.storeWord(FlashCalw.chipidCIDR, 0xDEADBEEF)
        mock.storeWord(FlashCalw.chipidEXID, 0)
        let client = SambaClient(transport: mock)
        try client.connect()
        let identity = try FlashCalw(samba: client).identify()
        XCTAssertFalse(identity.isSupported15C)

        var image = Data(count: FlashLayout.expectedFirmwareByteCount)
        image[0] = 1
        XCTAssertThrowsError(try FlashCalw(samba: client).writeApplication(image)) { error in
            guard case .unsupportedDevice = error as? FlasherError else {
                return XCTFail("expected unsupportedDevice, got \(error)")
            }
        }
    }

    func testWriteApplicationVerifies() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        var image = Data(count: FlashLayout.expectedFirmwareByteCount)
        for i in stride(from: 0, to: image.count, by: 17) {
            image[i] = UInt8(i & 0xFF)
        }
        try FlashCalw(samba: client).writeApplication(image)
        XCTAssertEqual(
            try client.read(from: FlashLayout.applicationStart, length: image.count),
            image
        )
        XCTAssertEqual(mock.memory[0x0000] ?? 0xFF, 0xFF, "bootloader region must stay erased/untouched")
    }
}

final class SambaFlashAppletTests: XCTestCase {
    func testOfficialImageHasVectorTable() {
        XCTAssertEqual(SambaFlashApplet.image.count, 2652)
        let sp = UInt32(SambaFlashApplet.image[0])
            | UInt32(SambaFlashApplet.image[1]) << 8
            | UInt32(SambaFlashApplet.image[2]) << 16
            | UInt32(SambaFlashApplet.image[3]) << 24
        let reset = UInt32(SambaFlashApplet.image[4])
            | UInt32(SambaFlashApplet.image[5]) << 8
            | UInt32(SambaFlashApplet.image[6]) << 16
            | UInt32(SambaFlashApplet.image[7]) << 24
        XCTAssertEqual(sp, 0x2000_7FF0)
        XCTAssertEqual(reset, 0x2000_2809)
    }

    func testUploadVerifiesSRAMImage() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        try SambaFlashApplet(samba: client, goDelay: 0).upload()
        XCTAssertEqual(
            try client.read(from: SambaFlashApplet.loadAddress, length: SambaFlashApplet.image.count),
            SambaFlashApplet.image
        )
    }

    func testInitializeAndWriteOnePage() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        let applet = SambaFlashApplet(samba: client, goDelay: 0)
        let info = try applet.loadAndInitialize()
        XCTAssertEqual(info.memorySize, 0x20000)
        XCTAssertEqual(info.bufferSize, 0x200)
        XCTAssertEqual(info.pageSize, 0x200)
        XCTAssertEqual(info.appStartPage, 32)
        XCTAssertEqual(info.bufferAddress, 0x2000_2C00)
        XCTAssertEqual(try client.readWord(SambaFlashApplet.mailboxAddress), ~SambaAppletCommand.initialize.rawValue)

        let page = Data((0..<512).map { UInt8($0 & 0xFF) })
        XCTAssertEqual(try applet.write(flashOffset: 0x4000, data: page), 512)
        XCTAssertEqual(try client.readWord(SambaFlashApplet.mailboxAddress), ~SambaAppletCommand.write.rawValue)
        XCTAssertEqual(try client.read(from: 0x4000, length: 512), page)
        XCTAssertEqual(mock.memory[0x0000] ?? 0xFF, 0xFF)
    }

    func testWriteRejectsBootloaderOffset() throws {
        let mock = SimulatedCalculatorTransport()
        let client = SambaClient(transport: mock)
        try client.connect()
        let applet = SambaFlashApplet(samba: client, goDelay: 0)
        _ = try applet.loadAndInitialize()
        XCTAssertThrowsError(try applet.write(flashOffset: 0x3E00, data: Data(count: 512))) { error in
            XCTAssertEqual(error as? FlasherError, .writeWouldTouchBootloader(address: 0x3E00))
        }
    }
}
