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

    func testSnapshotReflectsTranscriptionShortcutChanges() {
        let baseline = SettingsDraft(
            settings: AppSettings(),
            dictionaryWords: [],
            voiceShortcuts: []
        ).snapshot
        let edited = SettingsDraft(
            settings: AppSettings(
                hotkeyConfig: HotkeyConfiguration(
                    useCommand: true,
                    useOption: false,
                    useControl: true,
                    useShift: false,
                    keyCode: 0x08
                )
            ),
            dictionaryWords: [],
            voiceShortcuts: []
        ).snapshot

        XCTAssertNotEqual(baseline, edited)
        XCTAssertEqual(edited.settings.hotkeyConfig.keyCode, 0x08)
    }

    func testDraftPreservesModelStorageDirectoryPath() {
        let draft = SettingsDraft(
            settings: AppSettings(modelStorageDirectoryPath: "/tmp/kototype-models"),
            dictionaryWords: [],
            voiceShortcuts: []
        )

        XCTAssertEqual(draft.appSettings.modelStorageDirectoryPath, "/tmp/kototype-models")
        XCTAssertEqual(draft.snapshot.settings.modelStorageDirectoryPath, "/tmp/kototype-models")
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
