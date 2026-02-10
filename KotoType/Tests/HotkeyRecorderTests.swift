@testable import KotoType
import XCTest
import AppKit

@MainActor
final class HotkeyRecorderTests: XCTestCase {
    func testConfigurationFromControlAndOptionDoesNotIncludeCommand() {
        let config = HotkeyRecorder.configuration(from: [.control, .option], keyCode: 0)

        XCTAssertFalse(config.useCommand)
        XCTAssertTrue(config.useOption)
        XCTAssertTrue(config.useControl)
        XCTAssertFalse(config.useShift)
        XCTAssertEqual(config.keyCode, 0)
    }

    func testConfigurationFromNoModifiersIsEmpty() {
        let config = HotkeyRecorder.configuration(from: [], keyCode: 0)

        XCTAssertFalse(config.useCommand)
        XCTAssertFalse(config.useOption)
        XCTAssertFalse(config.useControl)
        XCTAssertFalse(config.useShift)
        XCTAssertEqual(config.keyCode, 0)
    }

    func testConfigurationIncludesKeyCodeWhenPresent() {
        let config = HotkeyRecorder.configuration(from: [.shift], keyCode: 0x31)

        XCTAssertFalse(config.useCommand)
        XCTAssertFalse(config.useOption)
        XCTAssertFalse(config.useControl)
        XCTAssertTrue(config.useShift)
        XCTAssertEqual(config.keyCode, 0x31)
    }

    func testModifierCaptureDecisionCommitsPreviousOnFirstRelease() {
        let decision = HotkeyRecorder.modifierCaptureDecision(
            previous: [.control, .option],
            current: [.control],
            regularKeyPressed: false,
            modifierReleaseCommitted: false
        )

        XCTAssertEqual(decision, .commitPreviousAndLock)
    }

    func testModifierCaptureDecisionIgnoresFurtherChangesAfterCommitUntilAllReleased() {
        let decision = HotkeyRecorder.modifierCaptureDecision(
            previous: [.control],
            current: [.control],
            regularKeyPressed: false,
            modifierReleaseCommitted: true
        )

        XCTAssertEqual(decision, .none)
    }

    func testModifierCaptureDecisionResetsLockWhenAllModifiersReleased() {
        let decision = HotkeyRecorder.modifierCaptureDecision(
            previous: [.control],
            current: [],
            regularKeyPressed: false,
            modifierReleaseCommitted: true
        )

        XCTAssertEqual(decision, .resetLock)
    }
}
