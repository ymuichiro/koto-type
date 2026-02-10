import Foundation

struct AppSettings: Codable {
    var hotkeyConfig: HotkeyConfiguration
    var language: String
    var autoPunctuation: Bool
    var temperature: Double
    var beamSize: Int
    var noSpeechThreshold: Double
    var compressionRatioThreshold: Double
    var task: String
    var bestOf: Int
    var vadThreshold: Double
    var batchInterval: Double
    var silenceThreshold: Double
    var silenceDuration: Double
    var parallelism: Int
    var launchAtLogin: Bool
    var autoGainEnabled: Bool
    var autoGainWeakThresholdDbfs: Double
    var autoGainTargetPeakDbfs: Double
    var autoGainMaxDb: Double

    init(
        hotkeyConfig: HotkeyConfiguration = HotkeyConfiguration(),
        language: String = "auto",
        autoPunctuation: Bool = true,
        temperature: Double = 0.0,
        beamSize: Int = 5,
        noSpeechThreshold: Double = 0.6,
        compressionRatioThreshold: Double = 2.4,
        task: String = "transcribe",
        bestOf: Int = 5,
        vadThreshold: Double = 0.5,
        batchInterval: Double = 10.0,
        silenceThreshold: Double = -40.0,
        silenceDuration: Double = 0.5,
        parallelism: Int = 2,
        launchAtLogin: Bool = false,
        autoGainEnabled: Bool = true,
        autoGainWeakThresholdDbfs: Double = -18.0,
        autoGainTargetPeakDbfs: Double = -10.0,
        autoGainMaxDb: Double = 18.0
    ) {
        self.hotkeyConfig = hotkeyConfig
        self.language = language
        self.autoPunctuation = autoPunctuation
        self.temperature = temperature
        self.beamSize = beamSize
        self.noSpeechThreshold = noSpeechThreshold
        self.compressionRatioThreshold = compressionRatioThreshold
        self.task = task
        self.bestOf = bestOf
        self.vadThreshold = vadThreshold
        self.batchInterval = batchInterval
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.parallelism = parallelism
        self.launchAtLogin = launchAtLogin
        self.autoGainEnabled = autoGainEnabled
        self.autoGainWeakThresholdDbfs = autoGainWeakThresholdDbfs
        self.autoGainTargetPeakDbfs = autoGainTargetPeakDbfs
        self.autoGainMaxDb = autoGainMaxDb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyConfig = try container.decodeIfPresent(HotkeyConfiguration.self, forKey: .hotkeyConfig) ?? HotkeyConfiguration()
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        autoPunctuation = try container.decodeIfPresent(Bool.self, forKey: .autoPunctuation) ?? true
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.0
        beamSize = try container.decodeIfPresent(Int.self, forKey: .beamSize) ?? 5
        noSpeechThreshold = try container.decodeIfPresent(Double.self, forKey: .noSpeechThreshold) ?? 0.6
        compressionRatioThreshold = try container.decodeIfPresent(Double.self, forKey: .compressionRatioThreshold) ?? 2.4
        task = try container.decodeIfPresent(String.self, forKey: .task) ?? "transcribe"
        bestOf = try container.decodeIfPresent(Int.self, forKey: .bestOf) ?? 5
        vadThreshold = try container.decodeIfPresent(Double.self, forKey: .vadThreshold) ?? 0.5
        batchInterval = try container.decodeIfPresent(Double.self, forKey: .batchInterval) ?? 10.0
        silenceThreshold = try container.decodeIfPresent(Double.self, forKey: .silenceThreshold) ?? -40.0
        silenceDuration = try container.decodeIfPresent(Double.self, forKey: .silenceDuration) ?? 0.5
        parallelism = try container.decodeIfPresent(Int.self, forKey: .parallelism) ?? 2
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        autoGainEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoGainEnabled) ?? true
        autoGainWeakThresholdDbfs = try container.decodeIfPresent(Double.self, forKey: .autoGainWeakThresholdDbfs) ?? -18.0
        autoGainTargetPeakDbfs = try container.decodeIfPresent(Double.self, forKey: .autoGainTargetPeakDbfs) ?? -10.0
        autoGainMaxDb = try container.decodeIfPresent(Double.self, forKey: .autoGainMaxDb) ?? 18.0
    }
}

final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()
    
    private let settingsKey = "appSettings"
    private let settingsURL: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let settingsDir = appSupportURL.appendingPathComponent("koto-type")
        try? fileManager.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        settingsURL = settingsDir.appendingPathComponent("settings.json")
    }
    
    func save(_ settings: AppSettings) {
        Logger.shared.log("SettingsManager.save: saving to \(settingsURL.path)")
        Logger.shared.log("SettingsManager.save: hotkey=\(settings.hotkeyConfig.description), lang=\(settings.language), punctuation=\(settings.autoPunctuation), temp=\(settings.temperature), beam=\(settings.beamSize), noSpeech=\(settings.noSpeechThreshold), compression=\(settings.compressionRatioThreshold), task=\(settings.task), bestOf=\(settings.bestOf), vad=\(settings.vadThreshold), launchAtLogin=\(settings.launchAtLogin), autoGainEnabled=\(settings.autoGainEnabled), autoGainWeakThresholdDbfs=\(settings.autoGainWeakThresholdDbfs), autoGainTargetPeakDbfs=\(settings.autoGainTargetPeakDbfs), autoGainMaxDb=\(settings.autoGainMaxDb)")
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
        Logger.shared.log("SettingsManager.load: hotkey=\(settings.hotkeyConfig.description), lang=\(settings.language), punctuation=\(settings.autoPunctuation), temp=\(settings.temperature), beam=\(settings.beamSize), noSpeech=\(settings.noSpeechThreshold), compression=\(settings.compressionRatioThreshold), task=\(settings.task), bestOf=\(settings.bestOf), vad=\(settings.vadThreshold), launchAtLogin=\(settings.launchAtLogin), autoGainEnabled=\(settings.autoGainEnabled), autoGainWeakThresholdDbfs=\(settings.autoGainWeakThresholdDbfs), autoGainTargetPeakDbfs=\(settings.autoGainTargetPeakDbfs), autoGainMaxDb=\(settings.autoGainMaxDb)")
        return settings
    }
}
