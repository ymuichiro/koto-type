@testable import KotoType
import Foundation
import XCTest

final class ManagedTranscriptionStorageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-storage-path-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testUnconfiguredStorageDirectoryUsesDefault() {
        XCTAssertEqual(
            KotoTypeStoragePaths.modelStorageDirectoryAvailability(directoryPath: nil),
            .usesDefault
        )
    }

    func testMissingStorageDirectoryIsReported() {
        let missingDirectory = temporaryDirectory.appendingPathComponent("missing", isDirectory: true)

        XCTAssertEqual(
            KotoTypeStoragePaths.modelStorageDirectoryAvailability(directoryPath: missingDirectory.path),
            .missing
        )
    }

    func testFileAtStoragePathIsReportedAsNotDirectory() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("not-a-folder")
        try Data("model".utf8).write(to: fileURL)

        XCTAssertEqual(
            KotoTypeStoragePaths.modelStorageDirectoryAvailability(directoryPath: fileURL.path),
            .notDirectory
        )
    }

    func testExistingWritableDirectoryIsAvailable() {
        XCTAssertEqual(
            KotoTypeStoragePaths.modelStorageDirectoryAvailability(directoryPath: temporaryDirectory.path),
            .available
        )
    }
}
