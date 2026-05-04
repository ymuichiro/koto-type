import AppKit
import XCTest
@testable import KotoType

@MainActor
final class SettingsWindowControllerLayoutTests: XCTestCase {
    func testWindowUsesMinimumSizeAndResizableStyle() throws {
        let controller = SettingsWindowController()
        let window: NSWindow = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertGreaterThanOrEqual(window.minSize.width, 600)
        XCTAssertGreaterThanOrEqual(window.minSize.height, 600)
    }

    func testWindowCloseWithoutUnsavedChangesAllowsClose() throws {
        let initialSnapshot = SettingsDraft(
            settings: AppSettings(),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot
        let controller = SettingsWindowController(
            draftBridge: SettingsDraftBridge(initialSnapshot: initialSnapshot),
            unsavedChangesPresenter: { _ in
                XCTFail("Presenter should not be called when there are no unsaved changes")
                return .cancel
            },
            resetDraftBridgeOnViewLoad: false
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(controller.shouldAllowWindowClose(for: window))
    }

    func testWindowCloseSaveChoiceAppliesChangesAndAllowsClose() throws {
        let initialSnapshot = SettingsDraft(
            settings: AppSettings(language: "auto"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot
        let bridge = SettingsDraftBridge(initialSnapshot: initialSnapshot)
        bridge.currentSnapshot = SettingsDraft(
            settings: AppSettings(language: "ja"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot

        var didApplyChanges = false
        bridge.applyChanges = {
            didApplyChanges = true
            bridge.markSaved(snapshot: bridge.currentSnapshot)
        }

        let controller = SettingsWindowController(
            draftBridge: bridge,
            unsavedChangesPresenter: { _ in .save },
            resetDraftBridgeOnViewLoad: false
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(controller.shouldAllowWindowClose(for: window))
        XCTAssertTrue(didApplyChanges)
        XCTAssertFalse(bridge.hasUnsavedChanges)
    }

    func testWindowCloseDiscardChoiceAllowsCloseWithoutApplyingChanges() throws {
        let initialSnapshot = SettingsDraft(
            settings: AppSettings(language: "auto"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot
        let bridge = SettingsDraftBridge(initialSnapshot: initialSnapshot)
        bridge.currentSnapshot = SettingsDraft(
            settings: AppSettings(language: "ja"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot

        var didApplyChanges = false
        bridge.applyChanges = {
            didApplyChanges = true
        }

        let controller = SettingsWindowController(
            draftBridge: bridge,
            unsavedChangesPresenter: { _ in .discard },
            resetDraftBridgeOnViewLoad: false
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(controller.shouldAllowWindowClose(for: window))
        XCTAssertFalse(didApplyChanges)
        XCTAssertTrue(bridge.hasUnsavedChanges)
    }

    func testWindowCloseCancelChoiceKeepsWindowOpen() throws {
        let initialSnapshot = SettingsDraft(
            settings: AppSettings(language: "auto"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot
        let bridge = SettingsDraftBridge(initialSnapshot: initialSnapshot)
        bridge.currentSnapshot = SettingsDraft(
            settings: AppSettings(language: "ja"),
            dictionaryWords: ["OpenAI"],
            voiceShortcuts: []
        ).snapshot

        let controller = SettingsWindowController(
            draftBridge: bridge,
            unsavedChangesPresenter: { _ in .cancel },
            resetDraftBridgeOnViewLoad: false
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertFalse(controller.shouldAllowWindowClose(for: window))
        XCTAssertTrue(bridge.hasUnsavedChanges)
    }
}
