@testable import KotoType
import XCTest
import Foundation

final class SettingsManagerTests: XCTestCase {
    var settingsManager: SettingsManager!
    var settingsURL: URL!
    var originalSettingsData: Data?
    
    override func setUpWithError() throws {
        try super.setUpWithError()

        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    func testDefaultSettings() throws {
        let settings = settingsManager.load()
        
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
        XCTAssertEqual(
            settings.recordingCompletionTimeout,
            AppSettings.defaultRecordingCompletionTimeout
        )
    }

    func testSaveAndLoad() throws {
        let originalSettings = settingsManager.load()
        
        var modifiedSettings = AppSettings()
        modifiedSettings.hotkeyConfig.keyCode = 36
        modifiedSettings.hotkeyConfig.useCommand = false
        modifiedSettings.hotkeyConfig.useOption = true
        modifiedSettings.language = "en"
        modifiedSettings.autoPunctuation = false
        modifiedSettings.temperature = 0.5
        modifiedSettings.beamSize = 10
        modifiedSettings.noSpeechThreshold = 0.8
        modifiedSettings.compressionRatioThreshold = 3.0
        modifiedSettings.task = "translate"
        modifiedSettings.bestOf = 3
        modifiedSettings.vadThreshold = 0.3
        modifiedSettings.launchAtLogin = true
        modifiedSettings.autoGainEnabled = false
        modifiedSettings.autoGainWeakThresholdDbfs = -25.0
        modifiedSettings.autoGainTargetPeakDbfs = -7.0
        modifiedSettings.autoGainMaxDb = 10.0
        modifiedSettings.recordingCompletionTimeout = 480.0
        
        settingsManager.save(modifiedSettings)
        let loadedSettings = settingsManager.load()
        
        XCTAssertEqual(loadedSettings.hotkeyConfig.keyCode, 36)
        XCTAssertEqual(loadedSettings.language, "en")
        XCTAssertEqual(loadedSettings.autoPunctuation, false)
        XCTAssertEqual(loadedSettings.temperature, 0.5)
        XCTAssertEqual(loadedSettings.beamSize, 10)
        XCTAssertEqual(loadedSettings.noSpeechThreshold, 0.8)
        XCTAssertEqual(loadedSettings.compressionRatioThreshold, 3.0)
        XCTAssertEqual(loadedSettings.task, "translate")
        XCTAssertEqual(loadedSettings.bestOf, 3)
        XCTAssertEqual(loadedSettings.vadThreshold, 0.3)
        XCTAssertEqual(loadedSettings.launchAtLogin, true)
        XCTAssertEqual(loadedSettings.autoGainEnabled, false)
        XCTAssertEqual(loadedSettings.autoGainWeakThresholdDbfs, -25.0)
        XCTAssertEqual(loadedSettings.autoGainTargetPeakDbfs, -7.0)
        XCTAssertEqual(loadedSettings.autoGainMaxDb, 10.0)
        XCTAssertEqual(loadedSettings.recordingCompletionTimeout, 480.0)
        
        settingsManager.save(originalSettings)
    }

    func testMultipleSettingsChanges() throws {
        var settings = AppSettings()
        
        settings.language = "ja"
        settings.temperature = 0.2
        settingsManager.save(settings)
        
        var loaded1 = settingsManager.load()
        XCTAssertEqual(loaded1.language, "ja")
        XCTAssertEqual(loaded1.temperature, 0.2)
        
        loaded1.language = "en"
        loaded1.temperature = 0.8
        settingsManager.save(loaded1)
        
        let loaded2 = settingsManager.load()
        XCTAssertEqual(loaded2.language, "en")
        XCTAssertEqual(loaded2.temperature, 0.8)
        
        let defaultSettings = AppSettings()
        settingsManager.save(defaultSettings)
    }

    func testHotkeyConfigurationIntegration() throws {
        var settings = settingsManager.load()
        
        settings.hotkeyConfig.keyCode = 51
        settings.hotkeyConfig.useCommand = true
        settings.hotkeyConfig.useOption = false
        settings.hotkeyConfig.useControl = true
        settings.hotkeyConfig.useShift = false
        
        settingsManager.save(settings)
        let loadedSettings = settingsManager.load()
        
        XCTAssertEqual(loadedSettings.hotkeyConfig.keyCode, 51)
        XCTAssertEqual(loadedSettings.hotkeyConfig.useCommand, true)
        XCTAssertEqual(loadedSettings.hotkeyConfig.useOption, false)
        XCTAssertEqual(loadedSettings.hotkeyConfig.useControl, true)
        XCTAssertEqual(loadedSettings.hotkeyConfig.useShift, false)
        
        let defaultSettings = AppSettings()
        settingsManager.save(defaultSettings)
    }

    func testEdgeCaseValues() throws {
        var settings = AppSettings()
        
        settings.temperature = 1.0
        settings.beamSize = 1
        settings.noSpeechThreshold = 0.0
        settings.compressionRatioThreshold = 10.0
        settings.bestOf = 1
        settings.vadThreshold = 0.0
        
        settingsManager.save(settings)
        let loadedSettings = settingsManager.load()
        
        XCTAssertEqual(loadedSettings.temperature, 1.0)
        XCTAssertEqual(loadedSettings.beamSize, 1)
        XCTAssertEqual(loadedSettings.noSpeechThreshold, 0.0)
        XCTAssertEqual(loadedSettings.compressionRatioThreshold, 10.0)
        XCTAssertEqual(loadedSettings.bestOf, 1)
        XCTAssertEqual(loadedSettings.vadThreshold, 0.0)
        
        let defaultSettings = AppSettings()
        settingsManager.save(defaultSettings)
    }

    func testStringEncoding() throws {
        var settings = AppSettings()
        
        settings.language = "ja"
        settings.task = "transcribe"
        
        settingsManager.save(settings)
        let loadedSettings = settingsManager.load()
        
        XCTAssertEqual(loadedSettings.language, "ja")
        XCTAssertEqual(loadedSettings.task, "transcribe")
        
        let defaultSettings = AppSettings()
        settingsManager.save(defaultSettings)
    }
}
