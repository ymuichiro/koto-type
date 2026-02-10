@testable import KotoType
import XCTest
import Foundation

final class AppSettingsTests: XCTestCase {
    func testDefaultInitialization() throws {
        let settings = AppSettings()
        
        XCTAssertEqual(settings.hotkeyConfig.keyCode, HotkeyConfiguration.default.keyCode)
        XCTAssertEqual(settings.language, "auto")
        XCTAssertEqual(settings.autoPunctuation, true)
        XCTAssertEqual(settings.temperature, 0.0)
        XCTAssertEqual(settings.beamSize, 5)
        XCTAssertEqual(settings.noSpeechThreshold, 0.6)
        XCTAssertEqual(settings.compressionRatioThreshold, 2.4)
        XCTAssertEqual(settings.task, "transcribe")
        XCTAssertEqual(settings.bestOf, 5)
        XCTAssertEqual(settings.vadThreshold, 0.5)
        XCTAssertEqual(settings.launchAtLogin, false)
        XCTAssertEqual(settings.autoGainEnabled, true)
        XCTAssertEqual(settings.autoGainWeakThresholdDbfs, -18.0)
        XCTAssertEqual(settings.autoGainTargetPeakDbfs, -10.0)
        XCTAssertEqual(settings.autoGainMaxDb, 18.0)
    }

    func testCustomInitialization() throws {
        var customConfig = HotkeyConfiguration()
        customConfig.keyCode = 36
        customConfig.useCommand = false
        customConfig.useOption = true
        customConfig.useControl = false
        customConfig.useShift = false
        
        let settings = AppSettings(
            hotkeyConfig: customConfig,
            language: "en",
            autoPunctuation: false,
            temperature: 0.5,
            beamSize: 10,
            noSpeechThreshold: 0.8,
            compressionRatioThreshold: 3.0,
            task: "translate",
            bestOf: 3,
            vadThreshold: 0.3,
            launchAtLogin: true,
            autoGainEnabled: false,
            autoGainWeakThresholdDbfs: -24.0,
            autoGainTargetPeakDbfs: -8.0,
            autoGainMaxDb: 12.0
        )
        
        XCTAssertEqual(settings.hotkeyConfig.keyCode, 36)
        XCTAssertEqual(settings.language, "en")
        XCTAssertEqual(settings.autoPunctuation, false)
        XCTAssertEqual(settings.temperature, 0.5)
        XCTAssertEqual(settings.beamSize, 10)
        XCTAssertEqual(settings.noSpeechThreshold, 0.8)
        XCTAssertEqual(settings.compressionRatioThreshold, 3.0)
        XCTAssertEqual(settings.task, "translate")
        XCTAssertEqual(settings.bestOf, 3)
        XCTAssertEqual(settings.vadThreshold, 0.3)
        XCTAssertEqual(settings.launchAtLogin, true)
        XCTAssertEqual(settings.autoGainEnabled, false)
        XCTAssertEqual(settings.autoGainWeakThresholdDbfs, -24.0)
        XCTAssertEqual(settings.autoGainTargetPeakDbfs, -8.0)
        XCTAssertEqual(settings.autoGainMaxDb, 12.0)
    }

    func testCodingAndDecoding() throws {
        var customConfig = HotkeyConfiguration()
        customConfig.keyCode = 51
        customConfig.useCommand = true
        customConfig.useOption = false
        customConfig.useControl = true
        customConfig.useShift = false
        
        let originalSettings = AppSettings(
            hotkeyConfig: customConfig,
            language: "ja",
            autoPunctuation: false,
            temperature: 0.2,
            beamSize: 7,
            noSpeechThreshold: 0.7,
            compressionRatioThreshold: 2.5,
            task: "transcribe",
            bestOf: 6,
            vadThreshold: 0.4,
            launchAtLogin: true,
            autoGainEnabled: false,
            autoGainWeakThresholdDbfs: -23.0,
            autoGainTargetPeakDbfs: -7.0,
            autoGainMaxDb: 11.0
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalSettings)
        
        let decoder = JSONDecoder()
        let decodedSettings = try decoder.decode(AppSettings.self, from: data)
        
        XCTAssertEqual(decodedSettings.hotkeyConfig.keyCode, originalSettings.hotkeyConfig.keyCode)
        XCTAssertEqual(decodedSettings.hotkeyConfig.useCommand, originalSettings.hotkeyConfig.useCommand)
        XCTAssertEqual(decodedSettings.hotkeyConfig.useOption, originalSettings.hotkeyConfig.useOption)
        XCTAssertEqual(decodedSettings.hotkeyConfig.useControl, originalSettings.hotkeyConfig.useControl)
        XCTAssertEqual(decodedSettings.hotkeyConfig.useShift, originalSettings.hotkeyConfig.useShift)
        XCTAssertEqual(decodedSettings.language, originalSettings.language)
        XCTAssertEqual(decodedSettings.autoPunctuation, originalSettings.autoPunctuation)
        XCTAssertEqual(decodedSettings.temperature, originalSettings.temperature)
        XCTAssertEqual(decodedSettings.beamSize, originalSettings.beamSize)
        XCTAssertEqual(decodedSettings.noSpeechThreshold, originalSettings.noSpeechThreshold)
        XCTAssertEqual(decodedSettings.compressionRatioThreshold, originalSettings.compressionRatioThreshold)
        XCTAssertEqual(decodedSettings.task, originalSettings.task)
        XCTAssertEqual(decodedSettings.bestOf, originalSettings.bestOf)
        XCTAssertEqual(decodedSettings.vadThreshold, originalSettings.vadThreshold)
        XCTAssertEqual(decodedSettings.launchAtLogin, originalSettings.launchAtLogin)
        XCTAssertEqual(decodedSettings.autoGainEnabled, originalSettings.autoGainEnabled)
        XCTAssertEqual(decodedSettings.autoGainWeakThresholdDbfs, originalSettings.autoGainWeakThresholdDbfs)
        XCTAssertEqual(decodedSettings.autoGainTargetPeakDbfs, originalSettings.autoGainTargetPeakDbfs)
        XCTAssertEqual(decodedSettings.autoGainMaxDb, originalSettings.autoGainMaxDb)
    }

    func testModifyingSettings() throws {
        var settings = AppSettings()
        
        settings.language = "en"
        XCTAssertEqual(settings.language, "en")

        settings.autoPunctuation = false
        XCTAssertEqual(settings.autoPunctuation, false)
        
        settings.temperature = 1.0
        XCTAssertEqual(settings.temperature, 1.0)
        
        settings.beamSize = 20
        XCTAssertEqual(settings.beamSize, 20)
        
        settings.task = "translate"
        XCTAssertEqual(settings.task, "translate")

        settings.launchAtLogin = true
        XCTAssertEqual(settings.launchAtLogin, true)

        settings.autoGainEnabled = false
        XCTAssertEqual(settings.autoGainEnabled, false)
        settings.autoGainWeakThresholdDbfs = -25.0
        XCTAssertEqual(settings.autoGainWeakThresholdDbfs, -25.0)
        settings.autoGainTargetPeakDbfs = -6.0
        XCTAssertEqual(settings.autoGainTargetPeakDbfs, -6.0)
        settings.autoGainMaxDb = 9.0
        XCTAssertEqual(settings.autoGainMaxDb, 9.0)
    }

    func testLegacyDecodingDefaultsAutoGainFields() throws {
        let legacyJSON = """
        {
          "hotkeyConfig": {
            "useCommand": true,
            "useOption": true,
            "useControl": false,
            "useShift": false,
            "keyCode": 0
          },
          "language": "ja",
          "autoPunctuation": true,
          "temperature": 0.0,
          "beamSize": 5,
          "noSpeechThreshold": 0.6,
          "compressionRatioThreshold": 2.4,
          "task": "transcribe",
          "bestOf": 5,
          "vadThreshold": 0.5,
          "batchInterval": 10.0,
          "silenceThreshold": -40.0,
          "silenceDuration": 0.5,
          "parallelism": 2,
          "launchAtLogin": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertEqual(decoded.autoGainEnabled, true)
        XCTAssertEqual(decoded.autoGainWeakThresholdDbfs, -18.0)
        XCTAssertEqual(decoded.autoGainTargetPeakDbfs, -10.0)
        XCTAssertEqual(decoded.autoGainMaxDb, 18.0)
    }

    func testLanguageSettings() throws {
        let languages = ["auto", "ja", "en", "es", "fr", "de", "zh"]
        
        for lang in languages {
            let settings = AppSettings(language: lang)
            XCTAssertEqual(settings.language, lang)
        }
    }

    func testTemperatureRange() throws {
        let temperatures: [Double] = [0.0, 0.1, 0.5, 1.0, 2.0]
        
        for temp in temperatures {
            let settings = AppSettings(temperature: temp)
            XCTAssertEqual(settings.temperature, temp)
        }
    }

    func testBeamSizeRange() throws {
        let beamSizes = [1, 5, 10, 20, 50]
        
        for beam in beamSizes {
            let settings = AppSettings(beamSize: beam)
            XCTAssertEqual(settings.beamSize, beam)
        }
    }

    func testThresholds() throws {
        var settings = AppSettings()
        
        settings.noSpeechThreshold = 0.0
        XCTAssertEqual(settings.noSpeechThreshold, 0.0)
        
        settings.noSpeechThreshold = 1.0
        XCTAssertEqual(settings.noSpeechThreshold, 1.0)
        
        settings.compressionRatioThreshold = 0.0
        XCTAssertEqual(settings.compressionRatioThreshold, 0.0)
        
        settings.compressionRatioThreshold = 10.0
        XCTAssertEqual(settings.compressionRatioThreshold, 10.0)
        
        settings.vadThreshold = 0.0
        XCTAssertEqual(settings.vadThreshold, 0.0)
        
        settings.vadThreshold = 1.0
        XCTAssertEqual(settings.vadThreshold, 1.0)
    }

    func testTaskSettings() throws {
        let tasks = ["transcribe", "translate"]
        
        for task in tasks {
            let settings = AppSettings(task: task)
            XCTAssertEqual(settings.task, task)
        }
    }

    func testBestOfRange() throws {
        let bestOfValues = [1, 5, 10, 20, 50]
        
        for bestOf in bestOfValues {
            let settings = AppSettings(bestOf: bestOf)
            XCTAssertEqual(settings.bestOf, bestOf)
        }
    }

    func testHotkeyConfigurationIntegration() throws {
        var config = HotkeyConfiguration()
        config.keyCode = 40
        config.useCommand = false
        config.useOption = true
        config.useControl = false
        config.useShift = true
        
        let settings = AppSettings(hotkeyConfig: config)
        
        XCTAssertEqual(settings.hotkeyConfig.keyCode, 40)
        XCTAssertEqual(settings.hotkeyConfig.useCommand, false)
        XCTAssertEqual(settings.hotkeyConfig.useOption, true)
        XCTAssertEqual(settings.hotkeyConfig.useControl, false)
        XCTAssertEqual(settings.hotkeyConfig.useShift, true)
    }
}
