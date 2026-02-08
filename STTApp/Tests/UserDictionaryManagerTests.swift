@testable import STTApp
import Foundation
import XCTest

final class UserDictionaryManagerTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var dictionaryURL: URL!
    private var manager: UserDictionaryManager!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let base = FileManager.default.temporaryDirectory
        tempDirectoryURL = base.appendingPathComponent("stt-simple-dict-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        dictionaryURL = tempDirectoryURL.appendingPathComponent("user_dictionary.json")
        manager = UserDictionaryManager(dictionaryURL: dictionaryURL)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        manager = nil
        dictionaryURL = nil
        tempDirectoryURL = nil

        try super.tearDownWithError()
    }

    func testLoadWordsReturnsEmptyWhenFileDoesNotExist() {
        XCTAssertEqual(manager.loadWords(), [])
    }

    func testSaveAndLoadNormalizesWords() {
        manager.saveWords(["  AI  ", "", "Whisper", "whisper", "音声 認識", "音声  認識"])

        let loaded = manager.loadWords()
        XCTAssertEqual(loaded, ["AI", "Whisper", "音声 認識"])
    }

    func testLoadSupportsLegacyArrayFormat() throws {
        let legacyWords = ["  TensorRT  ", "tensorrt", "  ", "MPS"]
        let data = try JSONEncoder().encode(legacyWords)
        try data.write(to: dictionaryURL)

        let loaded = manager.loadWords()
        XCTAssertEqual(loaded, ["TensorRT", "MPS"])
    }

    func testLoadInvalidJsonReturnsEmpty() throws {
        try Data("invalid json".utf8).write(to: dictionaryURL)
        XCTAssertEqual(manager.loadWords(), [])
    }

    func testSaveLimitsWordCount() {
        let words = (0..<250).map { "word-\($0)" }
        manager.saveWords(words)
        XCTAssertEqual(manager.loadWords().count, UserDictionaryManager.maxWordCount)
    }
}
