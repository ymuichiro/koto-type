@testable import KotoType
import XCTest

final class SettingsDraftStateTests: XCTestCase {
    func testSnapshotNormalizesDictionaryWordsBeforeComparison() {
        let saved = SettingsDraft(
            settings: AppSettings(),
            dictionaryWords: ["OpenAI", "Whisper Turbo"],
            voiceShortcuts: []
        ).snapshot
        let edited = SettingsDraft(
            settings: AppSettings(),
            dictionaryWords: ["  OpenAI  ", "openai", "Whisper   Turbo"],
            voiceShortcuts: []
        ).snapshot

        XCTAssertEqual(saved, edited)
    }

    func testSnapshotNormalizesVoiceShortcutsBeforeComparison() {
        let saved = SettingsDraft(
            settings: AppSettings(),
            dictionaryWords: [],
            voiceShortcuts: [
                VoiceShortcut(
                    triggerPhrase: "お疲れ様",
                    actionKind: .insertText,
                    insertText: "ありがとうございます"
                )
            ]
        ).snapshot
        let edited = SettingsDraft(
            settings: AppSettings(),
            dictionaryWords: [],
            voiceShortcuts: [
                VoiceShortcut(
                    triggerPhrase: "「お疲れ様。」",
                    actionKind: .insertText,
                    insertText: "ありがとうございます"
                )
            ]
        ).snapshot

        XCTAssertEqual(saved, edited)
    }

    @MainActor
    func testDraftBridgeTracksSavedState() {
        let initialSnapshot = SettingsDraft(
            settings: AppSettings(language: "auto"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot
        let bridge = SettingsDraftBridge(initialSnapshot: initialSnapshot)

        XCTAssertFalse(bridge.hasUnsavedChanges)

        bridge.currentSnapshot = SettingsDraft(
            settings: AppSettings(language: "ja"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot

        XCTAssertTrue(bridge.hasUnsavedChanges)

        bridge.markSaved(snapshot: bridge.currentSnapshot)
        XCTAssertFalse(bridge.hasUnsavedChanges)
    }
}
