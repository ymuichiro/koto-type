@testable import KotoType
import Foundation
import XCTest

final class SettingsManagerTests: XCTestCase {
    var settingsManager: SettingsManager!
    var settingsURL: URL!
    var originalSettingsData: Data?

    override func setUpWithError() throws {
        try super.setUpWithError()

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let settingsDir = appSupportURL.appendingPathComponent("koto-type")
        try fileManager.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        settingsURL = settingsDir.appendingPathComponent("settings.json")
        if fileManager.fileExists(atPath: settingsURL.path) {
            originalSettingsData = try Data(contentsOf: settingsURL)
            try fileManager.removeItem(at: settingsURL)
        } else {
            originalSettingsData = nil
        }

        settingsManager = SettingsManager.shared
    }

    override func tearDownWithError() throws {
        let fileManager = FileManager.default
        if let settingsURL {
            if fileManager.fileExists(atPath: settingsURL.path) {
                try fileManager.removeItem(at: settingsURL)
            }
            if let originalSettingsData {
                try originalSettingsData.write(to: settingsURL)
            }
        }
        try super.tearDownWithError()
    }

    func testDefaultSettings() {
        let settings = settingsManager.load()

        XCTAssertEqual(settings.language, "auto")
        XCTAssertTrue(settings.autoPunctuation)
        XCTAssertEqual(settings.transcriptionQualityPreset, .medium)
        XCTAssertTrue(settings.gpuAccelerationEnabled)
        XCTAssertTrue(settings.keepBackendReadyInBackground)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(
            settings.recordingCompletionTimeout,
            AppSettings.defaultRecordingCompletionTimeout
        )
    }

    func testSaveAndLoadUserFacingSettings() {
        let modifiedSettings = AppSettings(
            hotkeyConfig: HotkeyConfiguration(
                useCommand: false,
                useOption: true,
                useControl: true,
                useShift: false,
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
                keyCode: 36
            )
        )
        XCTAssertEqual(loadedSettings.language, "ja")
        XCTAssertFalse(loadedSettings.autoPunctuation)
        XCTAssertEqual(loadedSettings.transcriptionQualityPreset, .medium)
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
}
