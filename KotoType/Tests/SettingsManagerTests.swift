@testable import KotoType
import Foundation
import XCTest

final class SettingsManagerTests: XCTestCase {
    var settingsManager: SettingsManager!
    var settingsURL: URL!
    var testDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let fileManager = FileManager.default
        testDirectory = fileManager.temporaryDirectory.appendingPathComponent("kototype-settings-\(UUID().uuidString)")
        settingsURL = testDirectory.appendingPathComponent("settings.json")
        settingsManager = SettingsManager(settingsURL: settingsURL)
    }

    override func tearDownWithError() throws {
        if let testDirectory {
            try FileManager.default.removeItem(at: testDirectory)
        }
        try super.tearDownWithError()
    }

    func testDefaultSettings() {
        let settings = settingsManager.load()

        XCTAssertEqual(settings.language, AppSettings.defaultTranscriptionLanguage)
        XCTAssertTrue(settings.autoPunctuation)
        XCTAssertEqual(settings.transcriptionQualityPreset, .high)
        XCTAssertTrue(settings.gpuAccelerationEnabled)
        XCTAssertFalse(settings.keepBackendReadyInBackground)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(
            settings.recordingCompletionTimeout,
            AppSettings.defaultRecordingCompletionTimeout
        )
    }

    func testTranslationRemovalRoundTripsFileWithoutTouchingOtherData() throws {
        let kept = AppSettings(
            hotkeyConfig: HotkeyConfiguration(useCommand: false, useOption: true, useControl: true, useShift: false, keyCode: 49),
            language: "ja", autoPunctuation: false, transcriptionQualityPreset: .medium,
            gpuAccelerationEnabled: false, keepBackendReadyInBackground: false,
            launchAtLogin: true, recordingCompletionTimeout: 480
        )
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any])
        legacy["translationHotkeyConfig"] = "malformed retired shortcut"
        legacy["translationTargetLanguage"] = ["unexpected": "object"]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        try legacyData.write(to: settingsURL)
        let protectedFiles = ["history.json", "user_dictionary.json", "shortcuts.json", "recording.wav"]
        let sentinel = Data("unrelated user data must be unchanged".utf8)
        for name in protectedFiles {
            try sentinel.write(to: testDirectory.appendingPathComponent(name))
        }
        let loaded = settingsManager.load()
        XCTAssertEqual(loaded, kept)
        XCTAssertEqual(try Data(contentsOf: settingsURL), legacyData, "Loading must not rewrite the file")
        settingsManager.save(loaded)
        let reopened = SettingsManager(settingsURL: settingsURL)
        XCTAssertEqual(reopened.load(), kept)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        XCTAssertNil(saved["translationHotkeyConfig"])
        XCTAssertNil(saved["translationTargetLanguage"])
        for name in protectedFiles {
            XCTAssertEqual(try Data(contentsOf: testDirectory.appendingPathComponent(name)), sentinel)
        }
    }

    func testCorruptSavedSettingsPreserveLegacyBackendReadiness() throws {
        try Data("not-json".utf8).write(to: settingsURL)

        XCTAssertTrue(settingsManager.load().keepBackendReadyInBackground)
    }

    func testTranscriptionLanguageNormalizesLocaleAndInvalidValues() {
        XCTAssertEqual(AppSettings.normalizedTranscriptionLanguage(" JA-jp "), "ja")
        XCTAssertEqual(AppSettings.normalizedTranscriptionLanguage("en_US"), "en")
        XCTAssertEqual(AppSettings.normalizedTranscriptionLanguage("haw"), "haw")
        XCTAssertEqual(
            AppSettings.normalizedTranscriptionLanguage("xx"),
            AppSettings.defaultTranscriptionLanguage
        )
        XCTAssertEqual(
            AppSettings.normalizedTranscriptionLanguage("Japanese"),
            AppSettings.defaultTranscriptionLanguage
        )
        XCTAssertEqual(
            AppSettings.normalizedTranscriptionLanguage(" "),
            AppSettings.defaultTranscriptionLanguage
        )
    }

    func testLoadNormalizesLegacyTranscriptionLanguageLocale() throws {
        let json = """
        {
          "language": " ja-JP "
        }
        """.data(using: .utf8)!
        try json.write(to: settingsURL)

        XCTAssertEqual(settingsManager.load().language, "ja")
    }

    func testSaveAndLoadUserFacingSettings() {
        let modifiedSettings = AppSettings(
            hotkeyConfig: HotkeyConfiguration(
                useCommand: false,
                useOption: true,
                useControl: true,
                useShift: false,
                commandSide: .either,
                optionSide: .right,
                controlSide: .left,
                shiftSide: .either,
                keyCode: 0x31
            ),
            language: "en",
            autoPunctuation: false,
            transcriptionQualityPreset: .high,
            gpuAccelerationEnabled: false,
            keepBackendReadyInBackground: false,
            launchAtLogin: true,
            recordingCompletionTimeout: 480.0
        )

        settingsManager.save(modifiedSettings)
        let loadedSettings = settingsManager.load()

        XCTAssertEqual(loadedSettings.hotkeyConfig, modifiedSettings.hotkeyConfig)
        XCTAssertEqual(loadedSettings.language, "en")
        XCTAssertFalse(loadedSettings.autoPunctuation)
        XCTAssertEqual(loadedSettings.transcriptionQualityPreset, .high)
        XCTAssertFalse(loadedSettings.gpuAccelerationEnabled)
        XCTAssertFalse(loadedSettings.keepBackendReadyInBackground)
        XCTAssertTrue(loadedSettings.launchAtLogin)
        XCTAssertEqual(loadedSettings.recordingCompletionTimeout, 480.0)
    }

    func testSaveUsesOwnerOnlyPermissions() throws {
        settingsManager.save(AppSettings(language: "ja"))

        let permissions = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: settingsURL.path)[.posixPermissions]) as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, LocalFileProtection.filePermissions)
    }

    func testLegacySettingsFileMigratesRemovedRawFieldsToNewDefaults() throws {
        let legacyJSON = """
        {
          "hotkeyConfig": {
            "useCommand": true,
            "useOption": false,
            "useControl": true,
            "useShift": false,
            "keyCode": 36
          },
          "language": "ja",
          "autoPunctuation": false,
          "temperature": 0.7,
          "beamSize": 12,
          "noSpeechThreshold": 0.1,
          "compressionRatioThreshold": 5.0,
          "task": "translate",
          "bestOf": 8,
          "vadThreshold": 0.9,
          "parallelism": 4,
          "autoGainEnabled": false,
          "launchAtLogin": true,
          "recordingCompletionTimeout": 450.0
        }
        """.data(using: .utf8)!
        try legacyJSON.write(to: settingsURL)

        let loadedSettings = settingsManager.load()

        XCTAssertEqual(
            loadedSettings.hotkeyConfig,
            HotkeyConfiguration(
                useCommand: true,
                useOption: false,
                useControl: true,
                useShift: false,
                commandSide: .either,
                optionSide: .either,
                controlSide: .either,
                shiftSide: .either,
                keyCode: 36
            )
        )
        XCTAssertEqual(loadedSettings.language, "ja")
        XCTAssertFalse(loadedSettings.autoPunctuation)
        XCTAssertEqual(loadedSettings.transcriptionQualityPreset, .high)
        XCTAssertTrue(loadedSettings.gpuAccelerationEnabled)
        XCTAssertTrue(loadedSettings.keepBackendReadyInBackground)
        XCTAssertTrue(loadedSettings.launchAtLogin)
        XCTAssertEqual(loadedSettings.recordingCompletionTimeout, 450.0)
    }

    func testLoadClampsInvalidRecordingCompletionTimeout() throws {
        let invalidJSON = """
        {
          "recordingCompletionTimeout": 5
        }
        """.data(using: .utf8)!
        try invalidJSON.write(to: settingsURL)

        let loadedSettings = settingsManager.load()
        XCTAssertEqual(
            loadedSettings.recordingCompletionTimeout,
            AppSettings.minimumRecordingCompletionTimeout
        )
    }

    func testSaveAndLoadExtendedRecordingCompletionTimeout() {
        let modifiedSettings = AppSettings(recordingCompletionTimeout: 3_600.0)

        settingsManager.save(modifiedSettings)
        let loadedSettings = settingsManager.load()

        XCTAssertEqual(loadedSettings.recordingCompletionTimeout, 3_600.0)
    }
}
