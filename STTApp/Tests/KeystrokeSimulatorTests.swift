@testable import STTApp
import XCTest
import Foundation
import AppKit

final class KeystrokeSimulatorTests: XCTestCase {
    func testTypeTextEmptyString() throws {
        let expectation = XCTestExpectation(description: "Empty string typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextSingleCharacter() throws {
        let expectation = XCTestExpectation(description: "Single character typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("A")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextJapaneseText() throws {
        let expectation = XCTestExpectation(description: "Japanese text typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("こんにちは、今日はいい天気ですね。")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextEnglishText() throws {
        let expectation = XCTestExpectation(description: "English text typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("Hello, this is a test message.")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextWithNewlines() throws {
        let expectation = XCTestExpectation(description: "Text with newlines typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("First line\nSecond line\nThird line")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextWithSpecialCharacters() throws {
        let expectation = XCTestExpectation(description: "Text with special characters typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("Test: @#$%^&*()_+-=[]{}|;':\",./<>?")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextWithEmojis() throws {
        let expectation = XCTestExpectation(description: "Text with emojis typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("Test message 🎉✅❌⚠️")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextWithWhitespace() throws {
        let expectation = XCTestExpectation(description: "Text with whitespace typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("  Multiple   spaces\tand\ttabs  ")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextMixedContent() throws {
        let expectation = XCTestExpectation(description: "Mixed content typing should complete")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("日本語 English 日本語123 Special: !@#")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextVeryLongString() throws {
        let expectation = XCTestExpectation(description: "Very long string typing should complete")
        
        let longText = String(repeating: "Test message ", count: 100)
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText(longText)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextPasteboardIntegration() throws {
        let expectation = XCTestExpectation(description: "Pasteboard integration should work")
        
        let testText = "Pasteboard test content"
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText(testText)
            
            let pasteboard = NSPasteboard.general
            let pasteboardContent = pasteboard.string(forType: .string)
            
            XCTAssertEqual(pasteboardContent, testText, "Pasteboard should contain the typed text")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testTypeTextConsecutiveCalls() throws {
        let expectation = XCTestExpectation(description: "Consecutive typing calls should work")
        
        DispatchQueue.main.async {
            KeystrokeSimulator.typeText("First message")
            KeystrokeSimulator.typeText("Second message")
            KeystrokeSimulator.typeText("Third message")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
