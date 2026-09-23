import AppKit
import XCTest
@testable import KotoType

final class HotkeyStateTests: XCTestCase {
    func testModifierOnlyPressRepeatAndRelease() {
        var state = HotkeyState(configuration: .default)
        XCTAssertEqual(state.handle(type: .flagsChanged, keyCode: 0, modifiers: [.command, .option]), true)
        XCTAssertNil(state.handle(type: .flagsChanged, keyCode: 0, modifiers: [.command, .option]))
        XCTAssertNil(state.handle(type: .keyDown, keyCode: 49, modifiers: [.command, .option]))
        XCTAssertEqual(state.handle(type: .flagsChanged, keyCode: 0, modifiers: [.command]), false)
        XCTAssertNil(state.handle(type: .flagsChanged, keyCode: 0, modifiers: []))
    }

    func testKeyChordIgnoresOtherKeysAndReleasesOnModifierLoss() {
        var config = HotkeyConfiguration.default
        config.keyCode = 49
        var state = HotkeyState(configuration: config)
        XCTAssertNil(state.handle(type: .keyDown, keyCode: 48, modifiers: [.command, .option]))
        XCTAssertEqual(state.handle(type: .keyDown, keyCode: 49, modifiers: [.command, .option]), true)
        XCTAssertNil(state.handle(type: .keyDown, keyCode: 49, modifiers: [.command, .option]))
        XCTAssertNil(state.handle(type: .keyUp, keyCode: 48, modifiers: [.command, .option]))
        XCTAssertEqual(state.handle(type: .flagsChanged, keyCode: 0, modifiers: []), false)
        XCTAssertNil(state.handle(type: .keyUp, keyCode: 49, modifiers: []))
        XCTAssertEqual(state.handle(type: .keyDown, keyCode: 49, modifiers: [.command, .option]), true)
        XCTAssertEqual(state.handle(type: .keyUp, keyCode: 49, modifiers: [.command, .option]), false)
    }

    func testSettingsChangeReleasesOnceAndClearsPreviousModifiers() {
        var state = HotkeyState(configuration: .default)
        XCTAssertEqual(state.handle(type: .flagsChanged, keyCode: 0, modifiers: [.command, .option]), true)
        XCTAssertTrue(state.configure(.unset))
        XCTAssertFalse(state.configure(.default))
        XCTAssertEqual(state.handle(type: .flagsChanged, keyCode: 0, modifiers: [.command, .option]), true)
        XCTAssertTrue(state.configure(.unset))
        XCTAssertNil(state.handle(type: .flagsChanged, keyCode: 0, modifiers: [.command, .option]))
    }
}
