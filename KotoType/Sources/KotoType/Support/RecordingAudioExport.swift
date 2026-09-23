import Foundation

enum RecordingAudioExport {
    enum ExportError: Error { case sourceIsDestination }

    /// Called only after the user confirms a destination in NSSavePanel.
    /// Keep the working recording intact until the export succeeds.
    static func save(source: URL, destination: URL) throws {
        guard source.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else {
            throw ExportError.sourceIsDestination
        }
        let files = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".kototype-export-\(UUID().uuidString)", isDirectory: true)
        try LocalFileProtection.ensurePrivateDirectory(at: staging)
        defer { try? files.removeItem(at: staging) }
        let stagedFile = staging.appendingPathComponent("recording.wav")
        try LocalFileProtection.writeProtectedData(Data(contentsOf: source, options: .mappedIfSafe), to: stagedFile)
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: stagedFile, options: .usingNewMetadataOnly)
        } else {
            try files.moveItem(at: stagedFile, to: destination)
        }
    }
}
