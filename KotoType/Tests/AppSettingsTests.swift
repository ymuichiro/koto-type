@testable import KotoType
import Foundation
import XCTest

final class AppSettingsTests: XCTestCase {
    func testRetiredTranslationSettingsAreIgnoredWithoutLosingSettings() throws {
        // A retired field must neither overwrite the transcription shortcut nor
        // cause legacy settings to fall back to defaults, even if malformed.
        for retiredShortcut in ["{\"keyCode\":8}", "\"pt-br\"", "\"obsolete\"", "null"] {
            let json = """
            {"translationHotkeyConfig":\(retiredShortcut),"translationTargetLanguage":\(retiredShortcut),
             "hotkeyConfig":{"useCommand":false,"useOption":true,
                 "useControl":true,"useShift":false,"keyCode":49},
             "language":"ja","autoPunctuation":false,
             "keepBackendReadyInBackground":false,"recordingCompletionTimeout":480}
            """
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.hotkeyConfig.keyCode, 49)
            XCTAssertTrue(settings.hotkeyConfig.useOption)
            XCTAssertEqual(settings.language, "ja")
            XCTAssertFalse(settings.autoPunctuation)
            XCTAssertFalse(settings.keepBackendReadyInBackground)
            XCTAssertEqual(settings.recordingCompletionTimeout, 480)
            XCTAssertNil(settings.modelStorageDirectoryPath)
            let encoded = try JSONEncoder().encode(settings)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertNil(object["translationHotkeyConfig"])
            XCTAssertNil(object["translationTargetLanguage"])
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoded), settings)
        }
    }

    func testDefaultInitialization() {
        let settings = AppSettings()

        XCTAssertEqual(settings.hotkeyConfig, .default)
        XCTAssertEqual(settings.language, "auto")
        XCTAssertTrue(settings.autoPunctuation)
        XCTAssertEqual(settings.transcriptionQualityPreset, .high)
        XCTAssertTrue(settings.gpuAccelerationEnabled)
        XCTAssertFalse(settings.keepBackendReadyInBackground)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(
            settings.recordingCompletionTimeout,
            AppSettings.defaultRecordingCompletionTimeout
        )
        XCTAssertNil(settings.modelStorageDirectoryPath)
    }

    func testCustomInitialization() {
        let settings = AppSettings(
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
            recordingCompletionTimeout: 420.0
        )

        XCTAssertEqual(settings.hotkeyConfig.keyCode, 0x31)
        XCTAssertEqual(settings.language, "en")
        XCTAssertFalse(settings.autoPunctuation)
        XCTAssertEqual(settings.transcriptionQualityPreset, .high)
        XCTAssertFalse(settings.gpuAccelerationEnabled)
        XCTAssertFalse(settings.keepBackendReadyInBackground)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(settings.recordingCompletionTimeout, 420.0)
    }

    func testModelStorageDirectoryPathIsTrimmedAndStandardized() {
        let settings = AppSettings(modelStorageDirectoryPath: " /tmp/models/../speech-models ")

        XCTAssertEqual(settings.modelStorageDirectoryPath, "/tmp/speech-models")
        XCTAssertNil(AppSettings(modelStorageDirectoryPath: "  ").modelStorageDirectoryPath)
    }

    func testCodingAndDecodingRoundTrip() throws {
        let originalSettings = AppSettings(
            hotkeyConfig: HotkeyConfiguration(
                useCommand: true,
                useOption: false,
                useControl: true,
                useShift: true,
                commandSide: .right,
                optionSide: .either,
                controlSide: .left,
                shiftSide: .right,
                keyCode: 0x24
            ),
            language: "ja",
            autoPunctuation: false,
            transcriptionQualityPreset: .low,
            gpuAccelerationEnabled: false,
            keepBackendReadyInBackground: false,
            launchAtLogin: true,
            recordingCompletionTimeout: 540.0
        )

        let data = try JSONEncoder().encode(originalSettings)
        let decodedSettings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decodedSettings.hotkeyConfig, originalSettings.hotkeyConfig)
        XCTAssertEqual(decodedSettings.language, originalSettings.language)
        XCTAssertEqual(decodedSettings.autoPunctuation, originalSettings.autoPunctuation)
        XCTAssertEqual(
            decodedSettings.transcriptionQualityPreset,
            originalSettings.transcriptionQualityPreset
        )
        XCTAssertEqual(
            decodedSettings.gpuAccelerationEnabled,
            originalSettings.gpuAccelerationEnabled
        )
        XCTAssertEqual(
            decodedSettings.keepBackendReadyInBackground,
            originalSettings.keepBackendReadyInBackground
        )
        XCTAssertEqual(decodedSettings.launchAtLogin, originalSettings.launchAtLogin)
        XCTAssertEqual(
            decodedSettings.recordingCompletionTimeout,
            originalSettings.recordingCompletionTimeout
        )
    }

    func testLegacyDecodingPreservesUserFacingFieldsAndResetsRemovedRawFields() throws {
        let legacyJSON = """
        {
          "hotkeyConfig": {
            "useCommand": false,
            "useOption": true,
            "useControl": true,
            "useShift": false,
            "keyCode": 49
          },
          "language": "en",
          "autoPunctuation": false,
          "temperature": 0.8,
          "beamSize": 10,
          "noSpeechThreshold": 0.2,
          "compressionRatioThreshold": 3.2,
          "task": "translate",
          "bestOf": 9,
          "vadThreshold": 0.1,
          "batchInterval": 4.0,
          "silenceThreshold": -55.0,
          "silenceDuration": 2.0,
          "parallelism": 8,
          "autoGainEnabled": false,
          "autoGainWeakThresholdDbfs": -30.0,
          "autoGainTargetPeakDbfs": -12.0,
          "autoGainMaxDb": 4.0,
          "launchAtLogin": true,
          "recordingCompletionTimeout": 480.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        XCTAssertEqual(
            decoded.hotkeyConfig,
            HotkeyConfiguration(
                useCommand: false,
                useOption: true,
                useControl: true,
                useShift: false,
                commandSide: .either,
                optionSide: .either,
                controlSide: .either,
                shiftSide: .either,
                keyCode: 49
            )
        )
        XCTAssertEqual(decoded.language, "en")
        XCTAssertFalse(decoded.autoPunctuation)
        XCTAssertEqual(decoded.transcriptionQualityPreset, .high)
        XCTAssertTrue(decoded.gpuAccelerationEnabled)
        XCTAssertTrue(decoded.keepBackendReadyInBackground)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertEqual(decoded.recordingCompletionTimeout, 480.0)
    }

    func testRecordingCompletionTimeoutClampsToSupportedRange() {
        XCTAssertEqual(
            AppSettings(recordingCompletionTimeout: 9_999.0).recordingCompletionTimeout,
            AppSettings.maximumRecordingCompletionTimeout
        )
        XCTAssertEqual(
            AppSettings(recordingCompletionTimeout: 1.0).recordingCompletionTimeout,
            AppSettings.minimumRecordingCompletionTimeout
        )
        XCTAssertEqual(
            AppSettings(recordingCompletionTimeout: .infinity).recordingCompletionTimeout,
            AppSettings.defaultRecordingCompletionTimeout
        )
    }

    func testRecordingCompletionTimeoutSupportsExtendedMLXRange() {
        XCTAssertEqual(
            AppSettings(recordingCompletionTimeout: 3_600.0).recordingCompletionTimeout,
            3_600.0
        )
    }
}
