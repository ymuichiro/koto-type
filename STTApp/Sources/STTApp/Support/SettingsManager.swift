import Foundation

struct AppSettings: Codable {
    var hotkeyConfig: HotkeyConfiguration = HotkeyConfiguration()
    var language: String = "ja"
    var temperature: Double = 0.0
    var beamSize: Int = 5
    var noSpeechThreshold: Double = 0.6
    var compressionRatioThreshold: Double = 2.4
    var task: String = "transcribe"
    var bestOf: Int = 5
    var vadThreshold: Double = 0.5
    var batchInterval: Double = 10.0
    var silenceThreshold: Double = -40.0
    var silenceDuration: Double = 0.5
    var parallelism: Int = 2
}

final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()
    
    private let settingsKey = "appSettings"
    private let settingsURL: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let settingsDir = appSupportURL.appendingPathComponent("stt-simple")
        try? fileManager.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        settingsURL = settingsDir.appendingPathComponent("settings.json")
    }
    
    func save(_ settings: AppSettings) {
        Logger.shared.log("SettingsManager.save: saving to \(settingsURL.path)")
        Logger.shared.log("SettingsManager.save: hotkey=\(settings.hotkeyConfig.description), lang=\(settings.language), temp=\(settings.temperature), beam=\(settings.beamSize), noSpeech=\(settings.noSpeechThreshold), compression=\(settings.compressionRatioThreshold), task=\(settings.task), bestOf=\(settings.bestOf), vad=\(settings.vadThreshold)")
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL)
            Logger.shared.log("Settings saved successfully to \(settingsURL.path)")
        } catch {
            Logger.shared.log("Failed to save settings: \(error)", level: .error)
        }
    }

    func load() -> AppSettings {
        Logger.shared.log("SettingsManager.load: trying to load from \(settingsURL.path)")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            Logger.shared.log("No saved settings found, returning defaults")
            return AppSettings()
        }
        Logger.shared.log("SettingsManager.load: hotkey=\(settings.hotkeyConfig.description), lang=\(settings.language), temp=\(settings.temperature), beam=\(settings.beamSize), noSpeech=\(settings.noSpeechThreshold), compression=\(settings.compressionRatioThreshold), task=\(settings.task), bestOf=\(settings.bestOf), vad=\(settings.vadThreshold)")
        return settings
    }
}
