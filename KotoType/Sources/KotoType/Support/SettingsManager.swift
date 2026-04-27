import Foundation

enum TranscriptionQualityPreset: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }

    var summary: String {
        switch self {
        case .low:
            return "Fastest response"
        case .medium:
            return "Balanced speed and quality"
        case .high:
            return "Highest quality"
        }
    }
}

struct AppSettings: Codable {
    static let defaultRecordingCompletionTimeout: Double = 600.0
    static let minimumRecordingCompletionTimeout: Double = 30.0
    static let maximumRecordingCompletionTimeout: Double = 600.0

    var hotkeyConfig: HotkeyConfiguration
    var language: String
    var autoPunctuation: Bool
    var transcriptionQualityPreset: TranscriptionQualityPreset
    var gpuAccelerationEnabled: Bool
    var keepBackendReadyInBackground: Bool
    var launchAtLogin: Bool
    var recordingCompletionTimeout: Double

    init(
        hotkeyConfig: HotkeyConfiguration = HotkeyConfiguration(),
        language: String = "auto",
        autoPunctuation: Bool = true,
        transcriptionQualityPreset: TranscriptionQualityPreset = .high,
        gpuAccelerationEnabled: Bool = true,
        keepBackendReadyInBackground: Bool = true,
        launchAtLogin: Bool = false,
        recordingCompletionTimeout: Double = AppSettings.defaultRecordingCompletionTimeout
    ) {
        self.hotkeyConfig = hotkeyConfig
        self.language = language
        self.autoPunctuation = autoPunctuation
        self.transcriptionQualityPreset = transcriptionQualityPreset
        self.gpuAccelerationEnabled = gpuAccelerationEnabled
        self.keepBackendReadyInBackground = keepBackendReadyInBackground
        self.launchAtLogin = launchAtLogin
        self.recordingCompletionTimeout = Self.normalizedRecordingCompletionTimeout(
            recordingCompletionTimeout
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyConfig =
            try container.decodeIfPresent(HotkeyConfiguration.self, forKey: .hotkeyConfig)
            ?? HotkeyConfiguration()
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        autoPunctuation =
            try container.decodeIfPresent(Bool.self, forKey: .autoPunctuation) ?? true
        transcriptionQualityPreset =
            try container.decodeIfPresent(TranscriptionQualityPreset.self, forKey: .transcriptionQualityPreset)
            ?? .high
        gpuAccelerationEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .gpuAccelerationEnabled) ?? true
        keepBackendReadyInBackground =
            try container.decodeIfPresent(Bool.self, forKey: .keepBackendReadyInBackground) ?? true
        launchAtLogin =
            try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        recordingCompletionTimeout = Self.normalizedRecordingCompletionTimeout(
            try container.decodeIfPresent(Double.self, forKey: .recordingCompletionTimeout)
                ?? Self.defaultRecordingCompletionTimeout
        )
    }

    private static func normalizedRecordingCompletionTimeout(_ value: Double) -> Double {
        guard value.isFinite else {
            return defaultRecordingCompletionTimeout
        }

        return min(
            max(value, minimumRecordingCompletionTimeout),
            maximumRecordingCompletionTimeout
        )
    }
}

final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    private let settingsURL: URL

    private init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let settingsDir = appSupportURL.appendingPathComponent("koto-type")
        try? LocalFileProtection.ensurePrivateDirectory(at: settingsDir, fileManager: fileManager)
        settingsURL = settingsDir.appendingPathComponent("settings.json")
        try? LocalFileProtection.tightenFilePermissionsIfPresent(
            at: settingsURL,
            fileManager: fileManager
        )
    }

    func save(_ settings: AppSettings) {
        Logger.shared.log("SettingsManager.save: saving to \(settingsURL.path)")
        Logger.shared.log(
            "SettingsManager.save: hotkey=\(settings.hotkeyConfig.description), language=\(settings.language), punctuation=\(settings.autoPunctuation), preset=\(settings.transcriptionQualityPreset.rawValue), gpu=\(settings.gpuAccelerationEnabled), keepBackendReady=\(settings.keepBackendReadyInBackground), launchAtLogin=\(settings.launchAtLogin), recordingCompletionTimeout=\(settings.recordingCompletionTimeout)"
        )
        do {
            let data = try JSONEncoder().encode(settings)
            try LocalFileProtection.writeProtectedData(data, to: settingsURL)
            Logger.shared.log("Settings saved successfully to \(settingsURL.path)")
        } catch {
            Logger.shared.log("Failed to save settings: \(error)", level: .error)
        }
    }

    func load() -> AppSettings {
        Logger.shared.log("SettingsManager.load: trying to load from \(settingsURL.path)")
        guard let data = try? Data(contentsOf: settingsURL),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            Logger.shared.log("No saved settings found, returning defaults")
            return AppSettings()
        }
        Logger.shared.log(
            "SettingsManager.load: hotkey=\(settings.hotkeyConfig.description), language=\(settings.language), punctuation=\(settings.autoPunctuation), preset=\(settings.transcriptionQualityPreset.rawValue), gpu=\(settings.gpuAccelerationEnabled), keepBackendReady=\(settings.keepBackendReadyInBackground), launchAtLogin=\(settings.launchAtLogin), recordingCompletionTimeout=\(settings.recordingCompletionTimeout)"
        )
        return settings
    }
}
