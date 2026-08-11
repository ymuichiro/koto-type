import XCTest
@testable import KotoType

final class PromptTransformationTests: XCTestCase {
    func testPromptResultParserKeepsRawAndMarkdownSeparate() {
        let output = "__KOTOTYPE_PROMPT_RESULT__:{\"rawTranscript\":\"話した原文\",\"promptMarkdown\":\"# Goal\\n整理する\",\"usedFallback\":false}"

        XCTAssertEqual(
            PythonProcessManager.parsePromptResult(from: output),
            PromptTransformationResult(
                rawTranscript: "話した原文",
                promptMarkdown: "# Goal\n整理する",
                usedFallback: false
            )
        )
    }

    func testPromptResultParserRejectsOrdinaryTranscriptionOutput() {
        XCTAssertNil(PythonProcessManager.parsePromptResult(from: "ordinary transcript"))
    }

    @MainActor
    func testHotkeyValidationRejectsPromptShortcutCollision() {
        let hotkey = HotkeyConfiguration(
            useCommand: true,
            useOption: true,
            useControl: false,
            useShift: false,
            keyCode: 0
        )

        XCTAssertEqual(
            SettingsView.hotkeyValidationMessage(
                transcriptionHotkey: .unset,
                translationHotkey: .unset,
                faithfulHotkey: hotkey,
                promptHotkey: hotkey
            ),
            "Faithful transcription shortcut must differ from ai markdown prompt shortcut."
        )
    }
}
