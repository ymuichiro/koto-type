@testable import KotoType
import XCTest
import Foundation

final class LoggerTests: XCTestCase {
    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }

    func testSharedLoggerInstance() throws {
        let logger1 = Logger.shared
        let logger2 = Logger.shared
        
        XCTAssertTrue(logger1 === logger2, "Logger.shared should return the same instance")
    }

    func testLogLevelInitialization() throws {
        let logger = Logger.shared
        
        let levels: [Logger.LogLevel] = [.debug, .info, .warning, .error]
        
        for level in levels {
            logger.log("Test message at \(level) level", level: level)
        }
        
        XCTAssertTrue(true, "All log levels should be accepted without errors")
    }

    func testEmptyMessage() throws {
        let logger = Logger.shared
        
        logger.log("", level: .info)
        logger.log("   ", level: .info)
        
        XCTAssertTrue(true, "Empty or whitespace messages should be handled")
    }

    func testSanitizedMessageRedactsAbsolutePaths() {
        let message = "failed to process /Users/example/recordings/sample.wav, /private/tmp/kototype.wav, and /usr/local/bin/ffmpeg"

        let sanitized = Logger.sanitizedMessage(message)

        XCTAssertFalse(sanitized.contains("/Users/example"))
        XCTAssertFalse(sanitized.contains("/private/tmp"))
        XCTAssertFalse(sanitized.contains("/usr/local"))
        XCTAssertEqual(sanitized, "failed to process <path>, <path>, and <path>")
    }

    func testSanitizedMessageRedactsQuotedPathsWithSpaces() {
        let message = "script=\"/Users/example/Library/Application Support/koto-type/server.py\""

        let sanitized = Logger.sanitizedMessage(message)

        XCTAssertEqual(sanitized, "script=\"<path>\"")
    }

    func testSanitizedMessageRedactsFileURLsAndSmartQuotedPaths() {
        let message = "url=file:///Users/example/Library/Application%20Support/koto-type/server.py, error=The file “/Users/example/recording.wav” could not be saved"

        let sanitized = Logger.sanitizedMessage(message)

        XCTAssertEqual(
            sanitized,
            "url=<path>, error=The file “<path>” could not be saved"
        )
    }

    func testLongMessage() throws {
        let logger = Logger.shared
        
        let longMessage = String(repeating: "Test message ", count: 100)
        logger.log(longMessage, level: .info)
        
        XCTAssertTrue(true, "Long messages should be handled")
    }

    func testSpecialCharacters() throws {
        let logger = Logger.shared
        
        let specialMessages = [
            "Test with 日本語 characters",
            "Test with émojis 🎉",
            "Test with \\n\\r\\t special characters",
            "Test with \"quotes\" and 'apostrophes'"
        ]
        
        for message in specialMessages {
            logger.log(message, level: .info)
        }
        
        XCTAssertTrue(true, "Special characters should be handled")
    }

    func testUnicodeEmojis() throws {
        let logger = Logger.shared
        
        let emojiMessages = [
            "🎉 Success!",
            "⚠️ Warning!",
            "❌ Error!",
            "✅ Info!",
            "🔍 Debug!"
        ]
        
        for message in emojiMessages {
            logger.log(message, level: .info)
        }
        
        XCTAssertTrue(true, "Emoji messages should be handled")
    }

    func testLogFileUsesOwnerOnlyPermissions() throws {
        let logger = Logger.shared
        logger.log("permission check", level: .info)

        let permissions = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: logger.logPath)[.posixPermissions]) as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, LocalFileProtection.filePermissions)
    }

    func testConcurrentLoggingKeepsEachFileEntryIntact() throws {
        let logger = Logger.shared
        let marker = "logger-concurrency-" + UUID().uuidString + "-"
        let entryCount = 64

        DispatchQueue.concurrentPerform(iterations: entryCount) { index in
            logger.log("\(marker)\(index)", level: .debug)
        }

        let contents = try String(contentsOf: URL(fileURLWithPath: logger.logPath), encoding: .utf8)
        let matchingEntries = contents
            .components(separatedBy: .newlines)
            .filter { $0.contains(marker) }
        XCTAssertEqual(matchingEntries.count, entryCount)
    }
}
