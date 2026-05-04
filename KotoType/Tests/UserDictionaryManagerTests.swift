@testable import KotoType
import Foundation
import XCTest

final class UserDictionaryManagerTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var dictionaryURL: URL!
    private var manager: UserDictionaryManager!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let base = FileManager.default.temporaryDirectory
        tempDirectoryURL = base.appendingPathComponent("koto-type-dict-test-\(UUID().uuidString)")
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

    func testImportCSVAddsUniqueTermsAndSkipsDuplicatesAndBlanks() throws {
        let csv = """
        term
        OpenAI
        openai
        
          Whisper Turbo  
        """

        let result = try manager.importWords(
            fromCSVData: Data(csv.utf8),
            existingWords: ["Existing Term"]
        )

        XCTAssertEqual(result.words, ["Existing Term", "OpenAI", "Whisper Turbo"])
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(result.blankCount, 1)
        XCTAssertEqual(result.truncatedCount, 0)
    }

    func testImportCSVRejectsRowsWithMultipleColumns() {
        let csv = """
        term,alias
        OpenAI,test
        """

        XCTAssertThrowsError(
            try manager.importWords(fromCSVData: Data(csv.utf8), existingWords: [])
        ) { error in
            XCTAssertEqual(error as? UserDictionaryCSVError, .invalidFormat(row: 1))
        }
    }

    func testImportCSVTruncatesWhenLimitReached() throws {
        let existingWords = (0..<UserDictionaryManager.maxWordCount - 1).map { "existing-\($0)" }
        let csv = """
        term
        first-new
        second-new
        """

        let result = try manager.importWords(
            fromCSVData: Data(csv.utf8),
            existingWords: existingWords
        )

        XCTAssertEqual(result.words.count, UserDictionaryManager.maxWordCount)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.truncatedCount, 1)
    }

    func testCSVExportEscapesQuotesAndCommas() {
        let data = manager.csvData(for: ["OpenAI", "Hello, \"World\""])
        let csvString = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(
            csvString,
            "term\nOpenAI\n\"Hello, \"\"World\"\"\"\n"
        )
    }

    func testSaveUsesOwnerOnlyPermissions() throws {
        manager.saveWords(["secret"])

        let permissions = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: dictionaryURL.path)[.posixPermissions]) as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, LocalFileProtection.filePermissions)
    }
}
