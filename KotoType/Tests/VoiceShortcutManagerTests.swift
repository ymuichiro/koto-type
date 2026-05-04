@testable import KotoType
import Foundation
import XCTest

final class VoiceShortcutManagerTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var storageURL: URL!
    private var manager: VoiceShortcutManager!

    override func setUpWithError() throws {
        try super.setUpWithError()

        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("koto-type-shortcuts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        storageURL = tempDirectoryURL.appendingPathComponent("shortcuts.json")
        manager = VoiceShortcutManager(storageURL: storageURL)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        manager = nil
        storageURL = nil
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testLoadShortcutsReturnsEmptyWhenFileDoesNotExist() {
        XCTAssertEqual(manager.loadShortcuts(), [])
    }

    func testSaveAndLoadNormalizesAndDeduplicatesShortcuts() {
        manager.saveShortcuts([
            VoiceShortcut(
                triggerPhrase: "  お疲れ様。 ",
                actionKind: .insertText,
                insertText: "ありがとうございます"
            ),
            VoiceShortcut(
                triggerPhrase: "「お疲れ様」",
                actionKind: .insertText,
                insertText: "duplicate should be skipped"
            ),
            VoiceShortcut(
                triggerPhrase: "Open Notes",
                actionKind: .keyCommand,
                keyCommand: HotkeyConfiguration(
                    useCommand: true,
                    useOption: false,
                    useControl: false,
                    useShift: false,
                    keyCode: 0x2D
                )
            ),
        ])

        let loaded = manager.loadShortcuts()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].triggerPhrase, "お疲れ様。")
        XCTAssertEqual(loaded[0].actionKind, .insertText)
        XCTAssertEqual(loaded[1].actionKind, .keyCommand)
        XCTAssertEqual(loaded[1].keyCommand?.keyCode, 0x2D)
    }

    func testResolveMatchesAfterNormalization() {
        manager.saveShortcuts([
            VoiceShortcut(
                triggerPhrase: "お疲れ様",
                actionKind: .insertText,
                insertText: "ありがとうございました。"
            )
        ])

        let resolved = manager.resolve(input: "「お疲れ様。」")
        XCTAssertEqual(resolved?.insertText, "ありがとうございました。")
    }

    func testResolveRequiresExactNormalizedMatch() {
        manager.saveShortcuts([
            VoiceShortcut(
                triggerPhrase: "お疲れ様",
                actionKind: .insertText,
                insertText: "ありがとうございました。"
            )
        ])

        XCTAssertNil(manager.resolve(input: "今日はお疲れ様"))
        XCTAssertNil(manager.resolve(input: "お疲れ様です"))
    }

    func testSaveLimitsShortcutCount() {
        let shortcuts = (0..<150).map { index in
            VoiceShortcut(
                triggerPhrase: "shortcut-\(index)",
                actionKind: .insertText,
                insertText: "value-\(index)"
            )
        }

        manager.saveShortcuts(shortcuts)
        XCTAssertEqual(manager.loadShortcuts().count, VoiceShortcutManager.maxShortcutCount)
    }

    func testSaveUsesOwnerOnlyPermissions() throws {
        manager.saveShortcuts([
            VoiceShortcut(
                triggerPhrase: "Open Notes",
                actionKind: .keyCommand,
                keyCommand: HotkeyConfiguration(
                    useCommand: true,
                    useOption: false,
                    useControl: false,
                    useShift: false,
                    keyCode: 0x2D
                )
            )
        ])

        let permissions = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: storageURL.path)[.posixPermissions]) as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, LocalFileProtection.filePermissions)
    }
}
