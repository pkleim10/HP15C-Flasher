import Foundation

/// Numbered backup filenames for BATCH sessions (`hp15c-YYYYMMDD-HHMMSS-NNN.bin`).
public enum BatchBackupNaming {
    public static func filename(sessionStamp: String, unitNumber: Int) -> String {
        String(format: "hp15c-%@-%03d.bin", sessionStamp, unitNumber)
    }

    public static func fileURL(in folder: URL, sessionStamp: String, unitNumber: Int) -> URL {
        folder.appendingPathComponent(filename(sessionStamp: sessionStamp, unitNumber: unitNumber))
    }
}
