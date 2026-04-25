import Foundation

enum LocalFileProtection {
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600

    static func ensurePrivateDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try setPermissions(
            directoryPermissions,
            for: url,
            fileManager: fileManager
        )
    }

    static func tightenFilePermissionsIfPresent(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try setPermissions(
            filePermissions,
            for: url,
            fileManager: fileManager
        )
    }

    static func writeProtectedData(
        _ data: Data,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(
            at: url.deletingLastPathComponent(),
            fileManager: fileManager
        )
        try data.write(to: url, options: [.atomic])
        try tightenFilePermissionsIfPresent(
            at: url,
            fileManager: fileManager
        )
    }

    private static func setPermissions(
        _ permissions: Int,
        for url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }
}
