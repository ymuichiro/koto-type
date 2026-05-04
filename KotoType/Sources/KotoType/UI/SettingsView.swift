import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum StorageConfirmationAction: Identifiable {
    case clearHistory
    case clearCaches
    case deleteModel(ManagedTranscriptionModelKind)

    var id: String {
        switch self {
        case .clearHistory:
            return "clear-history"
        case .clearCaches:
            return "clear-caches"
        case let .deleteModel(kind):
            return "delete-model-\(kind.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .clearHistory:
            return "Clear transcription history?"
        case .clearCaches:
            return "Clear caches?"
        case let .deleteModel(kind):
            return "Delete \(kind.displayName)?"
        }
    }

    var message: String {
        switch self {
        case .clearHistory:
            return "This removes saved transcription history entries from KotoType."
        case .clearCaches:
            return "This removes KotoType-managed temporary audio files and download cache metadata."
        case let .deleteModel(kind):
            return "This removes the downloaded \(kind.displayName.lowercased()) from KotoType-managed storage. It will be downloaded again if needed later."
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var backendStatusStore = TranscriptionBackendStatusStore.shared

    private let storageManagementService: StorageManagementService
    @State private var hotkeyConfig: HotkeyConfiguration
    @State private var language: String
    @State private var autoPunctuation: Bool
    @State private var qualityPreset: TranscriptionQualityPreset
    @State private var gpuAccelerationEnabled: Bool
    @State private var keepBackendReadyInBackground: Bool
    @State private var launchAtLogin: Bool
    @State private var recordingCompletionTimeout: Double
    @State private var dictionaryWords: [String]
    @State private var pendingDictionaryEntry: String
    @State private var dictionaryStatusMessage: String?
    @State private var dictionaryStatusMessageIsError = false
    @State private var voiceShortcuts: [VoiceShortcut]
    @State private var pendingVoiceShortcutTrigger: String
    @State private var pendingVoiceShortcutActionKind: VoiceShortcutActionKind
    @State private var pendingVoiceShortcutInsertText: String
    @State private var pendingVoiceShortcutKeyCommand: HotkeyConfiguration
    @State private var voiceShortcutStatusMessage: String?
    @State private var voiceShortcutStatusMessageIsError = false
    @State private var isShowingLicenses = false
    @State private var storageSnapshot = StorageManagementSnapshot(
        historyEntryCount: 0,
        historyPath: KotoTypeStoragePaths.transcriptionHistoryFile().path,
        historyByteCount: 0,
        caches: [],
        models: []
    )
    @State private var isRefreshingStorage = false
    @State private var activeModelOperation: ManagedTranscriptionModelKind?
    @State private var storageActionMessage: String?
    @State private var storageActionMessageIsError = false
    @State private var pendingStorageConfirmation: StorageConfirmationAction?
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
        storageManagementService: StorageManagementService = StorageManagementService(),
        onHotkeyChanged: @escaping (HotkeyConfiguration) -> Void,
        onSettingsChanged: (() -> Void)? = nil,
        onImportAudioRequested: (() -> Void)? = nil,
        onShowHistoryRequested: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.storageManagementService = storageManagementService
        self.onHotkeyChanged = onHotkeyChanged
        self.onSettingsChanged = onSettingsChanged
        self.onImportAudioRequested = onImportAudioRequested
        self.onShowHistoryRequested = onShowHistoryRequested

        let settings = SettingsManager.shared.load()
        let userDictionaryWords = UserDictionaryManager.shared.loadWords()
        let savedVoiceShortcuts = VoiceShortcutManager.shared.loadShortcuts()
        self._hotkeyConfig = State(initialValue: settings.hotkeyConfig)
        self._language = State(initialValue: settings.language)
        self._autoPunctuation = State(initialValue: settings.autoPunctuation)
        self._qualityPreset = State(initialValue: settings.transcriptionQualityPreset)
        self._gpuAccelerationEnabled = State(initialValue: settings.gpuAccelerationEnabled)
        self._keepBackendReadyInBackground = State(initialValue: settings.keepBackendReadyInBackground)
        self._launchAtLogin = State(initialValue: settings.launchAtLogin)
        self._recordingCompletionTimeout = State(initialValue: settings.recordingCompletionTimeout)
        self._dictionaryWords = State(initialValue: userDictionaryWords)
        self._pendingDictionaryEntry = State(initialValue: "")
        self._voiceShortcuts = State(initialValue: savedVoiceShortcuts)
        self._pendingVoiceShortcutTrigger = State(initialValue: "")
        self._pendingVoiceShortcutActionKind = State(initialValue: .insertText)
        self._pendingVoiceShortcutInsertText = State(initialValue: "")
        self._pendingVoiceShortcutKeyCommand = State(initialValue: VoiceShortcutManager.emptyKeyCommand())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hotkeySection
                transcriptionSection
                appSection
                storageSection
                quickActionsSection
                voiceShortcutsSection
                licensesSection
                buttonRow
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 620, alignment: .topLeading)
        .sheet(isPresented: $isShowingLicenses) {
            ThirdPartyLicensesView(isPresented: $isShowingLicenses)
        }
        .task {
            await refreshStorageSnapshot()
        }
        .alert(item: $pendingStorageConfirmation) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text("Continue")) {
                    Task {
                        await performStorageConfirmation(action)
                    }
                },
                secondaryButton: .cancel()
            )
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
                Toggle(
                    "Keep backend ready in background",
                    isOn: $keepBackendReadyInBackground
                )

                Text(backendReadinessDescription)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Custom terminology dictionary")
                    .font(.subheadline)
                Spacer()
                Text("\(normalizedDictionaryWords.count)/\(UserDictionaryManager.maxWordCount) terms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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

            HStack(spacing: 10) {
                Button("Import CSV…") {
                    importDictionaryCSV()
                }

                Button("Export CSV…") {
                    exportDictionaryCSV()
                }
                .disabled(normalizedDictionaryWords.isEmpty)
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
                        ForEach(Array(dictionaryWords.indices), id: \.self) { index in
                            HStack {
                                TextField(
                                    "Term",
                                    text: dictionaryWordBinding(for: index)
                                )
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    normalizeDictionaryWords()
                                }

                                Spacer()
                                Button {
                                    removeDictionaryWord(at: index)
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
                        dictionaryStatusMessage = nil
                    }
                }
            }

            Text("Up to 200 terms. CSV import/export uses a single `term` column. Changes apply from the next transcription after saving.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let dictionaryStatusMessage {
                Text(dictionaryStatusMessage)
                    .font(.caption)
                    .foregroundColor(dictionaryStatusMessageIsError ? .orange : .secondary)
            }
        }
    }

    private var voiceShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Voice Shortcuts")

            Text("Run a saved action only when the entire transcript matches a trigger phrase after normalization.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Trigger phrase", text: $pendingVoiceShortcutTrigger)

                Picker("Action", selection: $pendingVoiceShortcutActionKind) {
                    ForEach(VoiceShortcutActionKind.allCases) { actionKind in
                        Text(actionKind.displayName).tag(actionKind)
                    }
                }
                .pickerStyle(.segmented)

                if pendingVoiceShortcutActionKind == .insertText {
                    TextField(
                        "Text to insert",
                        text: $pendingVoiceShortcutInsertText,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                } else {
                    HotkeyRecorderView(initialConfig: pendingVoiceShortcutKeyCommand) { config in
                        pendingVoiceShortcutKeyCommand = config
                    }
                    .frame(height: 40)

                    Text(
                        "Current command: \(pendingVoiceShortcutKeyCommand.description.isEmpty ? "Not set" : pendingVoiceShortcutKeyCommand.description)"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Add shortcut") {
                        addVoiceShortcut()
                    }
                    .disabled(!canAddVoiceShortcut)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack(alignment: .firstTextBaseline) {
                Text("Saved shortcuts")
                    .font(.subheadline)
                Spacer()
                Text("\(normalizedVoiceShortcuts.count)/\(VoiceShortcutManager.maxShortcutCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if voiceShortcuts.isEmpty {
                Text("No shortcuts registered")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(voiceShortcuts.indices), id: \.self) { index in
                            VoiceShortcutRowView(
                                shortcut: voiceShortcutBinding(for: index),
                                onRemove: {
                                    removeVoiceShortcut(at: index)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }

            Text("Only exact matches after normalization trigger a shortcut. Changes apply after saving.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let voiceShortcutStatusMessage {
                Text(voiceShortcutStatusMessage)
                    .font(.caption)
                    .foregroundColor(voiceShortcutStatusMessageIsError ? .orange : .secondary)
            }
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

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Storage")

            Text("Manage local history, downloaded models, and KotoType-owned caches.")
                .font(.caption)
                .foregroundColor(.secondary)

            storageCard(
                title: "Transcription history",
                detail: "\(storageSnapshot.historyEntryCount) entr\(storageSnapshot.historyEntryCount == 1 ? "y" : "ies") • \(KotoTypeStoragePaths.formattedByteCount(storageSnapshot.historyByteCount))",
                path: storageSnapshot.historyPath
            ) {
                Button("Clear history", role: .destructive) {
                    pendingStorageConfirmation = .clearHistory
                }
                .disabled(isStorageBusy || storageSnapshot.historyEntryCount == 0)
            }

            storageCard(
                title: "Temporary and download caches",
                detail: "\(storageSnapshot.totalCacheFileCount) files • \(KotoTypeStoragePaths.formattedByteCount(storageSnapshot.totalCacheByteCount))",
                path: storageSnapshot.caches.map(\.path).joined(separator: "\n")
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(storageSnapshot.caches) { cache in
                        Text("\(cache.title): \(cache.fileCount) files • \(KotoTypeStoragePaths.formattedByteCount(cache.byteCount))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Clear caches", role: .destructive) {
                        pendingStorageConfirmation = .clearCaches
                    }
                    .disabled(isStorageBusy || storageSnapshot.totalCacheFileCount == 0)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Downloaded models")
                    .font(.subheadline)

                ForEach(displayedModelStatuses) { status in
                    storageCard(
                        title: status.displayName,
                        detail: modelDetailText(for: status),
                        path: status.directoryPath
                    ) {
                        HStack(spacing: 10) {
                            if activeModelOperation == status.kind {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button(status.isDownloaded ? "Delete" : "Download", role: status.isDownloaded ? .destructive : nil) {
                                if status.isDownloaded {
                                    pendingStorageConfirmation = .deleteModel(status.kind)
                                } else {
                                    Task {
                                        await downloadModel(status.kind)
                                    }
                                }
                            }
                            .disabled(isStorageBusy && activeModelOperation != status.kind)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Refresh storage status") {
                    Task {
                        await refreshStorageSnapshot()
                    }
                }
                .disabled(isStorageBusy)
            }

            if let storageActionMessage {
                Text(storageActionMessage)
                    .font(.caption)
                    .foregroundColor(storageActionMessageIsError ? .orange : .secondary)
            }
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
        if let status = backendStatusStore.currentStatus {
            return status.summaryText
        }
        if gpuAccelerationEnabled && TranscriptionRuntimeSupport.supportsGPUAcceleration() {
            if !keepBackendReadyInBackground {
                return "Backend detection runs when you start dictation."
            }
            return "Detecting backend availability..."
        }
        return "Current backend: CPU"
    }

    private var backendDetailText: String? {
        if let status = backendStatusStore.currentStatus {
            return status.detailText
        }
        if gpuAccelerationEnabled && TranscriptionRuntimeSupport.supportsGPUAcceleration() {
            if keepBackendReadyInBackground {
                return "KotoType checks the Python backend shortly after launch and keeps the selected model ready in the background."
            }
            return "KotoType starts the realtime backend when you begin dictation and stops it again after transcription work finishes."
        }
        return "GPU acceleration is turned off in Settings."
    }

    private var backendReadinessDescription: String {
        if keepBackendReadyInBackground {
            return "Recommended. KotoType keeps the realtime transcription worker alive and preloads the selected model after launch for the fastest first dictation."
        }
        return "Uses less background CPU and memory, but KotoType starts the realtime worker on demand and shuts it down again after use."
    }

    private var displayedModelStatuses: [ManagedTranscriptionModelStatus] {
        storageSnapshot.models
    }

    private var isStorageBusy: Bool {
        isRefreshingStorage || activeModelOperation != nil
    }

    private var normalizedDictionaryWords: [String] {
        UserDictionaryManager.normalizedWords(dictionaryWords)
    }

    private var normalizedVoiceShortcuts: [VoiceShortcut] {
        VoiceShortcutManager.normalizedShortcuts(voiceShortcuts)
    }

    private var canAddVoiceShortcut: Bool {
        let normalizedTrigger = VoiceShortcutManager.normalizedTrigger(pendingVoiceShortcutTrigger)
        guard !normalizedTrigger.isEmpty else {
            return false
        }

        switch pendingVoiceShortcutActionKind {
        case .insertText:
            return !pendingVoiceShortcutInsertText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .keyCommand:
            return pendingVoiceShortcutKeyCommand.keyCode > 0
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func storageCard<Content: View>(
        title: String,
        detail: String,
        path: String,
        @ViewBuilder actions: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(path)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            actions()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func applySettings() {
        Logger.shared.log("SettingsView.applySettings called: hotkey=\(hotkeyConfig.description)")
        normalizeDictionaryWords()
        normalizeVoiceShortcuts()
        let settings = AppSettings(
            hotkeyConfig: hotkeyConfig,
            language: language,
            autoPunctuation: autoPunctuation,
            transcriptionQualityPreset: qualityPreset,
            gpuAccelerationEnabled: gpuAccelerationEnabled,
            keepBackendReadyInBackground: keepBackendReadyInBackground,
            launchAtLogin: launchAtLogin,
            recordingCompletionTimeout: recordingCompletionTimeout
        )
        _ = LaunchAtLoginManager.shared.setEnabled(launchAtLogin)
        SettingsManager.shared.save(settings)
        UserDictionaryManager.shared.saveWords(dictionaryWords)
        VoiceShortcutManager.shared.saveShortcuts(voiceShortcuts)
        onHotkeyChanged(hotkeyConfig)
        onSettingsChanged?()
    }

    private func addDictionaryWord() {
        let cleaned = pendingDictionaryEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        dictionaryWords = UserDictionaryManager.normalizedWords(dictionaryWords + [cleaned])
        pendingDictionaryEntry = ""
        dictionaryStatusMessage = nil
    }

    private func removeDictionaryWord(at index: Int) {
        guard dictionaryWords.indices.contains(index) else {
            return
        }
        dictionaryWords.remove(at: index)
        dictionaryStatusMessage = nil
    }

    private func dictionaryWordBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard dictionaryWords.indices.contains(index) else {
                    return ""
                }
                return dictionaryWords[index]
            },
            set: { newValue in
                guard dictionaryWords.indices.contains(index) else {
                    return
                }
                dictionaryWords[index] = newValue
                dictionaryStatusMessage = nil
            }
        )
    }

    private func normalizeDictionaryWords() {
        dictionaryWords = UserDictionaryManager.normalizedWords(dictionaryWords)
    }

    private func importDictionaryCSV() {
        let panel = NSOpenPanel()
        panel.title = "Import terminology CSV"
        panel.message = "Choose a CSV file with a single `term` column."
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let result = try UserDictionaryManager.shared.importWords(
                fromCSVData: data,
                existingWords: dictionaryWords
            )
            dictionaryWords = result.words
            dictionaryStatusMessage = dictionaryImportMessage(from: result)
            dictionaryStatusMessageIsError = false
        } catch {
            dictionaryStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            dictionaryStatusMessageIsError = true
        }
    }

    private func exportDictionaryCSV() {
        let panel = NSSavePanel()
        panel.title = "Export terminology CSV"
        panel.message = "Choose where to save the current dictionary."
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "user_dictionary.csv"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = UserDictionaryManager.shared.csvData(for: dictionaryWords)
            try data.write(to: url, options: [.atomic])
            dictionaryStatusMessage = "Exported \(normalizedDictionaryWords.count) terms."
            dictionaryStatusMessageIsError = false
        } catch {
            dictionaryStatusMessage = error.localizedDescription
            dictionaryStatusMessageIsError = true
        }
    }

    private func dictionaryImportMessage(from result: UserDictionaryCSVImportResult) -> String {
        var message = "Imported \(result.importedCount) terms."
        if result.duplicateCount > 0 {
            message += " \(result.duplicateCount) duplicates skipped."
        }
        if result.blankCount > 0 {
            message += " \(result.blankCount) blank rows ignored."
        }
        if result.truncatedCount > 0 {
            message += " \(result.truncatedCount) terms exceeded the limit."
        }
        return message
    }

    private func addVoiceShortcut() {
        var shortcut = VoiceShortcut(
            triggerPhrase: pendingVoiceShortcutTrigger,
            actionKind: pendingVoiceShortcutActionKind,
            insertText: pendingVoiceShortcutInsertText,
            keyCommand: pendingVoiceShortcutActionKind == .keyCommand ? pendingVoiceShortcutKeyCommand : nil
        )

        if shortcut.actionKind == .insertText {
            shortcut.keyCommand = nil
        } else {
            shortcut.insertText = ""
        }

        voiceShortcuts.append(shortcut)
        normalizeVoiceShortcuts()
        pendingVoiceShortcutTrigger = ""
        pendingVoiceShortcutActionKind = .insertText
        pendingVoiceShortcutInsertText = ""
        pendingVoiceShortcutKeyCommand = VoiceShortcutManager.emptyKeyCommand()
        voiceShortcutStatusMessage = nil
    }

    private func removeVoiceShortcut(at index: Int) {
        guard voiceShortcuts.indices.contains(index) else {
            return
        }
        voiceShortcuts.remove(at: index)
        voiceShortcutStatusMessage = nil
    }

    private func voiceShortcutBinding(for index: Int) -> Binding<VoiceShortcut> {
        Binding(
            get: {
                guard voiceShortcuts.indices.contains(index) else {
                    return VoiceShortcut(
                        triggerPhrase: "",
                        actionKind: .insertText
                    )
                }
                return voiceShortcuts[index]
            },
            set: { newValue in
                guard voiceShortcuts.indices.contains(index) else {
                    return
                }
                voiceShortcuts[index] = newValue
                voiceShortcutStatusMessage = nil
            }
        )
    }

    private func normalizeVoiceShortcuts() {
        voiceShortcuts = VoiceShortcutManager.normalizedShortcuts(voiceShortcuts)
    }

    @MainActor
    private func refreshStorageSnapshot() async {
        isRefreshingStorage = true
        let snapshot = await storageManagementService.snapshot()
        storageSnapshot = snapshot
        isRefreshingStorage = false
    }

    @MainActor
    private func performStorageConfirmation(_ action: StorageConfirmationAction) async {
        switch action {
        case .clearHistory:
            storageManagementService.clearHistory()
            storageActionMessage = "Transcription history cleared."
            storageActionMessageIsError = false
        case .clearCaches:
            storageManagementService.clearCaches()
            storageActionMessage = "KotoType-managed caches cleared."
            storageActionMessageIsError = false
        case let .deleteModel(kind):
            activeModelOperation = kind
            let result = await storageManagementService.deleteModel(kind)
            activeModelOperation = nil
            if result != nil {
                storageActionMessage = "\(kind.displayName) deleted."
                storageActionMessageIsError = false
            } else {
                storageActionMessage = "KotoType could not delete the \(kind.displayName.lowercased())."
                storageActionMessageIsError = true
            }
        }

        await refreshStorageSnapshot()
    }

    @MainActor
    private func downloadModel(_ kind: ManagedTranscriptionModelKind) async {
        activeModelOperation = kind
        let result = await storageManagementService.downloadModel(kind)
        activeModelOperation = nil
        if result != nil {
            storageActionMessage = "\(kind.displayName) downloaded."
            storageActionMessageIsError = false
        } else {
            storageActionMessage = "KotoType could not download the \(kind.displayName.lowercased())."
            storageActionMessageIsError = true
        }
        await refreshStorageSnapshot()
    }

    private func modelDetailText(for status: ManagedTranscriptionModelStatus) -> String {
        if status.isDownloaded {
            return "\(status.modelID) • \(status.fileCount) files • \(KotoTypeStoragePaths.formattedByteCount(status.byteCount))"
        }
        return "\(status.modelID) • Not downloaded"
    }

    private func recordingCompletionTimeoutDescription(_ seconds: Double) -> String {
        let minutes = seconds / 60.0
        if abs(minutes.rounded() - minutes) < 0.001 {
            return "\(Int(minutes.rounded())) min"
        }
        return String(format: "%.1f min", minutes)
    }
}

private struct VoiceShortcutRowView: View {
    @Binding var shortcut: VoiceShortcut
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Toggle("Enabled", isOn: $shortcut.isEnabled)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            TextField("Trigger phrase", text: $shortcut.triggerPhrase)

            Picker("Action", selection: $shortcut.actionKind) {
                ForEach(VoiceShortcutActionKind.allCases) { actionKind in
                    Text(actionKind.displayName).tag(actionKind)
                }
            }
            .pickerStyle(.segmented)

            if shortcut.actionKind == .insertText {
                TextField("Text to insert", text: $shortcut.insertText, axis: .vertical)
                    .lineLimit(2...4)
            } else {
                HotkeyRecorderView(
                    initialConfig: shortcut.keyCommand ?? VoiceShortcutManager.emptyKeyCommand()
                ) { config in
                    shortcut.keyCommand = config
                }
                .frame(height: 40)

                Text(
                    "Current command: \((shortcut.keyCommand?.description ?? "").isEmpty ? "Not set" : (shortcut.keyCommand?.description ?? ""))"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onChange(of: shortcut.actionKind) { newActionKind in
            switch newActionKind {
            case .insertText:
                shortcut.keyCommand = nil
            case .keyCommand:
                if shortcut.keyCommand == nil {
                    shortcut.keyCommand = VoiceShortcutManager.emptyKeyCommand()
                }
            }
        }
    }
}
