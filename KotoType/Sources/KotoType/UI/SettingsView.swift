import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var backendStatusStore = TranscriptionBackendStatusStore.shared

    @State private var hotkeyConfig: HotkeyConfiguration
    @State private var language: String
    @State private var autoPunctuation: Bool
    @State private var qualityPreset: TranscriptionQualityPreset
    @State private var gpuAccelerationEnabled: Bool
    @State private var launchAtLogin: Bool
    @State private var recordingCompletionTimeout: Double
    @State private var dictionaryWords: [String]
    @State private var pendingDictionaryEntry: String
    @State private var isShowingLicenses = false
    @Binding var isPresented: Bool

    let onHotkeyChanged: (HotkeyConfiguration) -> Void
    let onSettingsChanged: (() -> Void)?
    let onImportAudioRequested: (() -> Void)?
    let onShowHistoryRequested: (() -> Void)?

    let availableLanguages = [
        ("auto", "Auto Detect"),
        ("ja", "Japanese"),
        ("en", "English"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
    ]

    init(
        isPresented: Binding<Bool>,
        onHotkeyChanged: @escaping (HotkeyConfiguration) -> Void,
        onSettingsChanged: (() -> Void)? = nil,
        onImportAudioRequested: (() -> Void)? = nil,
        onShowHistoryRequested: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.onHotkeyChanged = onHotkeyChanged
        self.onSettingsChanged = onSettingsChanged
        self.onImportAudioRequested = onImportAudioRequested
        self.onShowHistoryRequested = onShowHistoryRequested

        let settings = SettingsManager.shared.load()
        let userDictionaryWords = UserDictionaryManager.shared.loadWords()
        self._hotkeyConfig = State(initialValue: settings.hotkeyConfig)
        self._language = State(initialValue: settings.language)
        self._autoPunctuation = State(initialValue: settings.autoPunctuation)
        self._qualityPreset = State(initialValue: settings.transcriptionQualityPreset)
        self._gpuAccelerationEnabled = State(initialValue: settings.gpuAccelerationEnabled)
        self._launchAtLogin = State(initialValue: settings.launchAtLogin)
        self._recordingCompletionTimeout = State(initialValue: settings.recordingCompletionTimeout)
        self._dictionaryWords = State(initialValue: userDictionaryWords)
        self._pendingDictionaryEntry = State(initialValue: "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hotkeySection
                transcriptionSection
                appSection
                quickActionsSection
                licensesSection
                buttonRow
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 620, alignment: .topLeading)
        .sheet(isPresented: $isShowingLicenses) {
            ThirdPartyLicensesView(isPresented: $isShowingLicenses)
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Hotkey")

            HotkeyRecorderView(initialConfig: hotkeyConfig) { config in
                hotkeyConfig = config
            }
            .frame(height: 40)

            Text("Current shortcut: \(hotkeyConfig.description.isEmpty ? "Not set" : hotkeyConfig.description)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Presets")
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                Button("⌘+⌥ (Default)") {
                    hotkeyConfig = HotkeyConfiguration(
                        useCommand: true,
                        useOption: true,
                        useControl: false,
                        useShift: false,
                        keyCode: 0
                    )
                }
                Button("⌘+⌃") {
                    hotkeyConfig = HotkeyConfiguration(
                        useCommand: true,
                        useOption: false,
                        useControl: true,
                        useShift: false,
                        keyCode: 0
                    )
                }
                Button("⌘+⌃+Space") {
                    hotkeyConfig = HotkeyConfiguration(
                        useCommand: true,
                        useOption: false,
                        useControl: true,
                        useShift: false,
                        keyCode: 0x31
                    )
                }
            }
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Transcription")

            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.subheadline)
                Picker("", selection: $language) {
                    ForEach(availableLanguages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }

            Toggle("Automatically improve punctuation", isOn: $autoPunctuation)

            VStack(alignment: .leading, spacing: 8) {
                Text("Quality preset")
                    .font(.subheadline)
                Picker("", selection: $qualityPreset) {
                    ForEach(TranscriptionQualityPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Text(qualityPreset.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Use GPU acceleration when available",
                    isOn: $gpuAccelerationEnabled
                )
                .disabled(!TranscriptionRuntimeSupport.supportsGPUAcceleration())

                Text(gpuToggleDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Backend")
                    .font(.subheadline)
                Text(backendSummaryText)
                if let backendDetailText {
                    Text(backendDetailText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            dictionarySection
        }
    }

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom terminology dictionary")
                .font(.subheadline)

            HStack {
                TextField("e.g. ctranslate2, Whisper large-v3-turbo", text: $pendingDictionaryEntry)
                    .onSubmit {
                        addDictionaryWord()
                    }
                Button("Add") {
                    addDictionaryWord()
                }
                .disabled(pendingDictionaryEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if dictionaryWords.isEmpty {
                Text("No terms registered")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dictionaryWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    removeDictionaryWord(word)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                HStack {
                    Spacer()
                    Button("Remove all", role: .destructive) {
                        dictionaryWords.removeAll()
                    }
                }
            }

            Text("Up to 200 terms. Changes apply from the next transcription after saving.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var appSection: some View {
        let canManageLaunchAtLogin = LaunchAtLoginManager.canManageLaunchAtLogin()

        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("App")

            Toggle("Launch at login", isOn: $launchAtLogin)
                .disabled(!canManageLaunchAtLogin)

            Text(
                canManageLaunchAtLogin
                    ? "When enabled, KotoType launches automatically when you sign in to macOS."
                    : "Launch at login can only be configured from an installed app in /Applications or ~/Applications."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Post-recording finalize timeout")
                    .font(.subheadline)
                Slider(
                    value: $recordingCompletionTimeout,
                    in: AppSettings.minimumRecordingCompletionTimeout...AppSettings.maximumRecordingCompletionTimeout,
                    step: 30.0
                )

                Text(recordingCompletionTimeoutDescription(recordingCompletionTimeout))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Quick Actions")

            Button("Import audio file...") {
                onImportAudioRequested?()
            }
            .disabled(onImportAudioRequested == nil)

            Button("Open transcription history...") {
                onShowHistoryRequested?()
            }
            .disabled(onShowHistoryRequested == nil)
        }
    }

    private var licensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Licenses")

            Text("Review open-source licenses bundled with KotoType and the MLX Whisper model attribution.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Open-source licenses…") {
                isShowingLicenses = true
            }
        }
    }

    private var buttonRow: some View {
        HStack {
            Spacer()
            Button("Save") {
                applySettings()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel") {
                isPresented = false
            }
        }
    }

    private var gpuToggleDescription: String {
        if !TranscriptionRuntimeSupport.supportsGPUAcceleration() {
            return "Requires Apple Silicon and bundled MLX runtime."
        }
        return "When off, KotoType always uses the CPU."
    }

    private var backendSummaryText: String {
        backendStatusStore.currentStatus?.summaryText
            ?? "Backend is selected automatically when transcription starts."
    }

    private var backendDetailText: String? {
        backendStatusStore.currentStatus?.detailText
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func applySettings() {
        Logger.shared.log("SettingsView.applySettings called: hotkey=\(hotkeyConfig.description)")
        let settings = AppSettings(
            hotkeyConfig: hotkeyConfig,
            language: language,
            autoPunctuation: autoPunctuation,
            transcriptionQualityPreset: qualityPreset,
            gpuAccelerationEnabled: gpuAccelerationEnabled,
            launchAtLogin: launchAtLogin,
            recordingCompletionTimeout: recordingCompletionTimeout
        )
        _ = LaunchAtLoginManager.shared.setEnabled(launchAtLogin)
        SettingsManager.shared.save(settings)
        UserDictionaryManager.shared.saveWords(dictionaryWords)
        onHotkeyChanged(hotkeyConfig)
        onSettingsChanged?()
    }

    private func addDictionaryWord() {
        let cleaned = pendingDictionaryEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        dictionaryWords = UserDictionaryManager.normalizedWords(dictionaryWords + [cleaned])
        pendingDictionaryEntry = ""
    }

    private func removeDictionaryWord(_ word: String) {
        dictionaryWords.removeAll { $0 == word }
    }

    private func recordingCompletionTimeoutDescription(_ seconds: Double) -> String {
        let minutes = seconds / 60.0
        if abs(minutes.rounded() - minutes) < 0.001 {
            return "\(Int(minutes.rounded())) min"
        }
        return String(format: "%.1f min", minutes)
    }
}
