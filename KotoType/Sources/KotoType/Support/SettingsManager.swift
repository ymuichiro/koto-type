import Foundation

enum TranscriptionQualityPreset: String, Codable, CaseIterable, Equatable, Sendable {
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

struct AppSettings: Codable, Equatable {
    static let defaultRecordingCompletionTimeout: Double = 600.0
    static let minimumRecordingCompletionTimeout: Double = 30.0
    static let maximumRecordingCompletionTimeout: Double = 3_600.0
    static let defaultTranscriptionLanguage = "auto"
    static let defaultTranslationTargetLanguage = "en"
    static let supportedTranscriptionLanguageCodes: Set<String> = Set(
        """
        auto af am ar as az ba be bg bn bo br bs ca cs cy da de el en es et eu fa fi fo fr
        gl gu ha haw he hi hr ht hu hy id is it ja jw ka kk km kn ko la lb ln lo lt lv
        mg mi mk ml mn mr ms mt my ne nl nn no oc pa pl ps pt ro ru sa sd si sk sl sn so
        sq sr su sv sw ta te tg th tk tl tr tt uk ur uz vi yi yo yue zh
        """.split(separator: " ").map(String.init)
    )

    var hotkeyConfig: HotkeyConfiguration
    var translationHotkeyConfig: HotkeyConfiguration
    var language: String
    var translationTargetLanguage: String
    var autoPunctuation: Bool
    var transcriptionQualityPreset: TranscriptionQualityPreset
    var gpuAccelerationEnabled: Bool
    var keepBackendReadyInBackground: Bool
    var launchAtLogin: Bool
    var recordingCompletionTimeout: Double

    init(
        hotkeyConfig: HotkeyConfiguration = HotkeyConfiguration(),
        translationHotkeyConfig: HotkeyConfiguration = .unset,
        language: String = AppSettings.defaultTranscriptionLanguage,
        translationTargetLanguage: String = AppSettings.defaultTranslationTargetLanguage,
        autoPunctuation: Bool = true,
        transcriptionQualityPreset: TranscriptionQualityPreset = .high,
        gpuAccelerationEnabled: Bool = true,
        keepBackendReadyInBackground: Bool = false,
        launchAtLogin: Bool = false,
        recordingCompletionTimeout: Double = AppSettings.defaultRecordingCompletionTimeout
    ) {
        self.hotkeyConfig = hotkeyConfig
        self.translationHotkeyConfig = translationHotkeyConfig
        self.language = Self.normalizedTranscriptionLanguage(language)
        self.translationTargetLanguage = Self.normalizedTranslationTargetLanguage(
            translationTargetLanguage
        )
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
        translationHotkeyConfig =
            try container.decodeIfPresent(HotkeyConfiguration.self, forKey: .translationHotkeyConfig)
            ?? .unset
        language = Self.normalizedTranscriptionLanguage(
            try container.decodeIfPresent(String.self, forKey: .language)
                ?? Self.defaultTranscriptionLanguage
        )
        translationTargetLanguage = Self.normalizedTranslationTargetLanguage(
            try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage)
                ?? Self.defaultTranslationTargetLanguage
        )
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

    static func normalizedTranscriptionLanguage(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty, normalized != defaultTranscriptionLanguage else {
            return defaultTranscriptionLanguage
        }

        let primaryCode = normalized.split { character in
            character == "-" || character == "_"
        }.first.map(String.init) ?? normalized
        guard supportedTranscriptionLanguageCodes.contains(primaryCode) else {
            return defaultTranscriptionLanguage
        }

        return primaryCode
    }

    private static func normalizedTranslationTargetLanguage(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty, normalized.count <= 10 else {
            return defaultTranslationTargetLanguage
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard normalized.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return defaultTranslationTargetLanguage
        }

        return normalized
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
            "SettingsManager.save: hotkey=\(settings.hotkeyConfig.description), translationHotkey=\(settings.translationHotkeyConfig.description), language=\(settings.language), translationTargetLanguage=\(settings.translationTargetLanguage), punctuation=\(settings.autoPunctuation), preset=\(settings.transcriptionQualityPreset.rawValue), gpu=\(settings.gpuAccelerationEnabled), keepBackendReady=\(settings.keepBackendReadyInBackground), launchAtLogin=\(settings.launchAtLogin), recordingCompletionTimeout=\(settings.recordingCompletionTimeout)"
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
        guard let data = try? Data(contentsOf: settingsURL) else {
            Logger.shared.log("No saved settings found, returning defaults")
            return AppSettings()
        }
        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            Logger.shared.log("Saved settings could not be decoded, preserving legacy backend readiness")
            return AppSettings(keepBackendReadyInBackground: true)
        }
        Logger.shared.log(
            "SettingsManager.load: hotkey=\(settings.hotkeyConfig.description), translationHotkey=\(settings.translationHotkeyConfig.description), language=\(settings.language), translationTargetLanguage=\(settings.translationTargetLanguage), punctuation=\(settings.autoPunctuation), preset=\(settings.transcriptionQualityPreset.rawValue), gpu=\(settings.gpuAccelerationEnabled), keepBackendReady=\(settings.keepBackendReadyInBackground), launchAtLogin=\(settings.launchAtLogin), recordingCompletionTimeout=\(settings.recordingCompletionTimeout)"
        )
        return settings
    }
}
