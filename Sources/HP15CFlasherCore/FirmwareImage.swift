import Foundation

public struct FirmwareImage: Equatable {
    public let url: URL
    public let data: Data

    public var byteCount: Int { data.count }

    public init(url: URL, data: Data) {
        self.url = url
        self.data = data
    }

    public static func load(from url: URL, requireExactSize: Bool = true) throws -> FirmwareImage {
        let resolved = url.standardizedFileURL
        guard FileManager.default.isReadableFile(atPath: resolved.path) else {
            throw FlasherError.firmwareNotFound(resolved)
        }

        let data = try Data(contentsOf: resolved)
        try validate(data, requireExactSize: requireExactSize)
        return FirmwareImage(url: resolved, data: data)
    }

    public static func validate(_ data: Data, requireExactSize: Bool = true) throws {
        if data.isEmpty {
            throw FlasherError.firmwareEmpty
        }
        if data.count > FlashLayout.expectedFirmwareByteCount {
            throw FlasherError.firmwareTooLarge(
                actual: data.count,
                maximum: FlashLayout.expectedFirmwareByteCount
            )
        }
        if requireExactSize, data.count != FlashLayout.expectedFirmwareByteCount {
            throw FlasherError.firmwareWrongSize(
                actual: data.count,
                expected: FlashLayout.expectedFirmwareByteCount
            )
        }
    }
}
