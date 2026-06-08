import XCTest
@testable import KotoType

@MainActor
final class SettingsViewValidationTests: XCTestCase {
    func testHotkeyValidationRejectsMatchingTranslationShortcut() {
        let hotkey = HotkeyConfiguration(
            useCommand: true,
            useOption: false,
            useControl: true,
            useShift: false,
            keyCode: 0x31
        )

        XCTAssertEqual(
            SettingsView.hotkeyValidationMessage(
                transcriptionHotkey: hotkey,
                translationHotkey: hotkey
            ),
            "Translation shortcut must differ from transcription."
        )
    }

    func testHotkeyValidationAllowsUnsetOrDistinctTranslationShortcut() {
        let transcriptionHotkey = HotkeyConfiguration(
            useCommand: true,
            useOption: true,
            useControl: false,
            useShift: false,
            keyCode: 0x31
        )
        let translationHotkey = HotkeyConfiguration(
            useCommand: true,
            useOption: false,
            useControl: true,
            useShift: false,
            keyCode: 0x08
        )

        XCTAssertNil(
            SettingsView.hotkeyValidationMessage(
                transcriptionHotkey: transcriptionHotkey,
                translationHotkey: .unset
            )
        )
        XCTAssertNil(
            SettingsView.hotkeyValidationMessage(
                transcriptionHotkey: transcriptionHotkey,
                translationHotkey: translationHotkey
            )
        )
    }
}
