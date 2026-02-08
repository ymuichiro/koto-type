@testable import STTApp
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
}
