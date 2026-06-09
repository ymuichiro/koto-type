@testable import KotoType
import Foundation
import XCTest

final class AppSettingsTests: XCTestCase {
    func testDefaultInitialization() {
        let settings = AppSettings()

        XCTAssertEqual(settings.hotkeyConfig, .default)
        XCTAssertEqual(settings.translationHotkeyConfig, .unset)
        XCTAssertEqual(settings.language, "auto")
        XCTAssertEqual(
            settings.translationTargetLanguage,
            AppSettings.defaultTranslationTargetLanguage
        )
        XCTAssertTrue(settings.autoPunctuation)
        XCTAssertEqual(settings.transcriptionQualityPreset, .high)
        XCTAssertTrue(settings.gpuAccelerationEnabled)
        XCTAssertTrue(settings.keepBackendReadyInBackground)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(
            settings.recordingCompletionTimeout,
            AppSettings.defaultRecordingCompletionTimeout
        )
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
            translationHotkeyConfig: HotkeyConfiguration(
                useCommand: true,
                useOption: false,
                useControl: true,
                useShift: false,
                keyCode: 0x08
            ),
            language: "en",
            translationTargetLanguage: "PT-BR",
            autoPunctuation: false,
            transcriptionQualityPreset: .high,
            gpuAccelerationEnabled: false,
            keepBackendReadyInBackground: false,
            launchAtLogin: true,
            recordingCompletionTimeout: 420.0
        )

        XCTAssertEqual(settings.hotkeyConfig.keyCode, 0x31)
        XCTAssertEqual(settings.translationHotkeyConfig.keyCode, 0x08)
        XCTAssertEqual(settings.language, "en")
        XCTAssertEqual(settings.translationTargetLanguage, "pt-br")
        XCTAssertFalse(settings.autoPunctuation)
        XCTAssertEqual(settings.transcriptionQualityPreset, .high)
        XCTAssertFalse(settings.gpuAccelerationEnabled)
        XCTAssertFalse(settings.keepBackendReadyInBackground)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(settings.recordingCompletionTimeout, 420.0)
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
            translationHotkeyConfig: HotkeyConfiguration(
                useCommand: false,
                useOption: true,
                useControl: true,
                useShift: false,
                commandSide: .either,
                optionSide: .left,
                controlSide: .right,
                shiftSide: .either,
                keyCode: 0x31
            ),
            language: "ja",
            translationTargetLanguage: "PT-BR",
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
        XCTAssertEqual(
            decodedSettings.translationHotkeyConfig,
            originalSettings.translationHotkeyConfig
        )
        XCTAssertEqual(decodedSettings.language, originalSettings.language)
        XCTAssertEqual(decodedSettings.translationTargetLanguage, "pt-br")
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
        XCTAssertEqual(decoded.translationHotkeyConfig, .unset)
        XCTAssertEqual(decoded.language, "en")
        XCTAssertEqual(
            decoded.translationTargetLanguage,
            AppSettings.defaultTranslationTargetLanguage
        )
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

    func testTranslationTargetLanguageNormalizationDuringDecoding() throws {
        let invalidJSON = """
        {
          "translationTargetLanguage": "PT_BR"
        }
        """.data(using: .utf8)!
        let validJSON = """
        {
          "translationTargetLanguage": "PT-BR"
        }
        """.data(using: .utf8)!

        let invalidDecoded = try JSONDecoder().decode(AppSettings.self, from: invalidJSON)
        let validDecoded = try JSONDecoder().decode(AppSettings.self, from: validJSON)

        XCTAssertEqual(
            invalidDecoded.translationTargetLanguage,
            AppSettings.defaultTranslationTargetLanguage
        )
        XCTAssertEqual(validDecoded.translationTargetLanguage, "pt-br")
    }

    func testRecordingCompletionTimeoutSupportsExtendedMLXRange() {
        XCTAssertEqual(
            AppSettings(recordingCompletionTimeout: 3_600.0).recordingCompletionTimeout,
            3_600.0
        )
    }
}
