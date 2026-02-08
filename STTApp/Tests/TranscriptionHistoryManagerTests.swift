@testable import STTApp
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
        manager.addEntry(text: "second text", source: .importedFile, audioFilePath: "/tmp/test.mp3")

        let entries = manager.loadEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "second text")
        XCTAssertEqual(entries[0].source, .importedFile)
        XCTAssertEqual(entries[0].audioFilePath, "/tmp/test.mp3")
        XCTAssertEqual(entries[1].text, "first text")
        XCTAssertEqual(entries[1].source, .liveRecording)
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
}
