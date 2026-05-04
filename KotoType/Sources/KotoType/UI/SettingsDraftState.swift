import Foundation

struct SettingsDraft: Equatable {
    var hotkeyConfig: HotkeyConfiguration
    var language: String
    var autoPunctuation: Bool
    var qualityPreset: TranscriptionQualityPreset
    var gpuAccelerationEnabled: Bool
    var keepBackendReadyInBackground: Bool
    var launchAtLogin: Bool
    var recordingCompletionTimeout: Double
    var dictionaryWords: [String]
    var voiceShortcuts: [VoiceShortcut]

    init(
        settings: AppSettings = SettingsManager.shared.load(),
        dictionaryWords: [String] = UserDictionaryManager.shared.loadWords(),
        voiceShortcuts: [VoiceShortcut] = VoiceShortcutManager.shared.loadShortcuts()
    ) {
        hotkeyConfig = settings.hotkeyConfig
        language = settings.language
        autoPunctuation = settings.autoPunctuation
        qualityPreset = settings.transcriptionQualityPreset
        gpuAccelerationEnabled = settings.gpuAccelerationEnabled
        keepBackendReadyInBackground = settings.keepBackendReadyInBackground
        launchAtLogin = settings.launchAtLogin
        recordingCompletionTimeout = settings.recordingCompletionTimeout
        self.dictionaryWords = dictionaryWords
        self.voiceShortcuts = voiceShortcuts
    }

    var normalizedDictionaryWords: [String] {
        UserDictionaryManager.normalizedWords(dictionaryWords)
    }

    var normalizedVoiceShortcuts: [VoiceShortcut] {
        VoiceShortcutManager.normalizedShortcuts(voiceShortcuts)
    }

    var appSettings: AppSettings {
        AppSettings(
            hotkeyConfig: hotkeyConfig,
            language: language,
            autoPunctuation: autoPunctuation,
            transcriptionQualityPreset: qualityPreset,
            gpuAccelerationEnabled: gpuAccelerationEnabled,
            keepBackendReadyInBackground: keepBackendReadyInBackground,
            launchAtLogin: launchAtLogin,
            recordingCompletionTimeout: recordingCompletionTimeout
        )
    }

    var snapshot: SettingsDraftSnapshot {
        SettingsDraftSnapshot(
            settings: appSettings,
            dictionaryWords: normalizedDictionaryWords,
            voiceShortcuts: normalizedVoiceShortcuts.map(ComparableVoiceShortcut.init)
        )
    }
}

struct SettingsDraftSnapshot: Equatable {
    let settings: AppSettings
    let dictionaryWords: [String]
    let voiceShortcuts: [ComparableVoiceShortcut]
}

struct ComparableVoiceShortcut: Equatable {
    let triggerPhrase: String
    let actionKind: VoiceShortcutActionKind
    let insertText: String
    let keyCommand: HotkeyConfiguration?
    let isEnabled: Bool

    init(shortcut: VoiceShortcut) {
        triggerPhrase = VoiceShortcutManager.normalizedTrigger(shortcut.triggerPhrase)
        actionKind = shortcut.actionKind
        insertText = shortcut.insertText
        keyCommand = shortcut.keyCommand
        isEnabled = shortcut.isEnabled
    }
}

@MainActor
final class SettingsDraftBridge {
    private(set) var lastSavedSnapshot: SettingsDraftSnapshot
    var currentSnapshot: SettingsDraftSnapshot
    var applyChanges: (() -> Void)?

    init(initialSnapshot: SettingsDraftSnapshot) {
        lastSavedSnapshot = initialSnapshot
        currentSnapshot = initialSnapshot
    }

    var hasUnsavedChanges: Bool {
        currentSnapshot != lastSavedSnapshot
    }

    func markSaved(snapshot: SettingsDraftSnapshot) {
        lastSavedSnapshot = snapshot
        currentSnapshot = snapshot
    }
}

enum SettingsCloseConfirmationChoice {
    case save
    case discard
    case cancel
}
