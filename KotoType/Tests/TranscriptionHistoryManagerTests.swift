@testable import KotoType
import Foundation
import XCTest

final class TranscriptionHistoryManagerTests: XCTestCase {
    private var historyURL: URL!
    private var manager: TranscriptionHistoryManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        historyURL = tempDir.appendingPathComponent("history.json")
        manager = TranscriptionHistoryManager(historyURL: historyURL, maxEntryCount: 3)
    }

    override func tearDownWithError() throws {
        if let historyURL {
            try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent())
        }
        historyURL = nil
        manager = nil
        try super.tearDownWithError()
    }

    func testAddAndLoadEntries() {
        manager.addEntry(text: "  first text  ", source: .liveRecording)
        manager.addEntry(text: "second text", source: .importedFile)

        let entries = manager.loadEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "second text")
        XCTAssertEqual(entries[0].source, .importedFile)
        XCTAssertNil(entries[0].audioFilePath)
        XCTAssertEqual(entries[1].text, "first text")
        XCTAssertEqual(entries[1].source, .liveRecording)
    }

    func testLegacyAudioPathIsRemovedWhenHistoryIsLoaded() throws {
        let legacyEntry = TranscriptionHistoryEntry(
            source: .importedFile,
            audioFilePath: "/Users/example/recording.wav",
            text: "legacy text"
        )
        let data = try JSONEncoder().encode([legacyEntry])
        try data.write(to: historyURL)

        let entries = manager.loadEntries()

        XCTAssertNil(entries.first?.audioFilePath)
        let rewrittenData = try Data(contentsOf: historyURL)
        XCTAssertFalse(String(decoding: rewrittenData, as: UTF8.self).contains("recording.wav"))
    }

    func testNewEntriesDoNotPersistAudioPathKey() throws {
        manager.addEntry(text: "imported text", source: .importedFile)

        let storedData = try Data(contentsOf: historyURL)
        XCTAssertFalse(String(decoding: storedData, as: UTF8.self).contains("audioFilePath"))
    }

    func testEmptyEntryIsIgnored() {
        manager.addEntry(text: "   \n", source: .liveRecording)
        XCTAssertTrue(manager.loadEntries().isEmpty)
    }

    func testEntryLimit() {
        manager.addEntry(text: "1", source: .liveRecording)
        manager.addEntry(text: "2", source: .liveRecording)
        manager.addEntry(text: "3", source: .liveRecording)
        manager.addEntry(text: "4", source: .liveRecording)

        let entries = manager.loadEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map { $0.text }, ["4", "3", "2"])
    }

    func testClear() {
        manager.addEntry(text: "abc", source: .liveRecording)
        XCTAssertFalse(manager.loadEntries().isEmpty)

        manager.clear()
        XCTAssertTrue(manager.loadEntries().isEmpty)
    }

    func testSavedHistoryUsesOwnerOnlyPermissions() throws {
        manager.addEntry(text: "sensitive", source: .liveRecording)

        let permissions = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: historyURL.path)[.posixPermissions]) as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, LocalFileProtection.filePermissions)
    }
}
