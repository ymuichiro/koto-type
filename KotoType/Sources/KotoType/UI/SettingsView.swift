import AppKit
import SwiftUI

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
    @State private var launchAtLogin: Bool
    @State private var recordingCompletionTimeout: Double
    @State private var dictionaryWords: [String]
    @State private var pendingDictionaryEntry: String
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
                storageSection
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
            return "Detecting backend availability..."
        }
        return "Current backend: CPU"
    }

    private var backendDetailText: String? {
        if let status = backendStatusStore.currentStatus {
            return status.detailText
        }
        if gpuAccelerationEnabled && TranscriptionRuntimeSupport.supportsGPUAcceleration() {
            return "KotoType checks the Python backend shortly after launch and warms the selected model in the background."
        }
        return "GPU acceleration is turned off in Settings."
    }

    private var displayedModelStatuses: [ManagedTranscriptionModelStatus] {
        let byKind = Dictionary(uniqueKeysWithValues: storageSnapshot.models.map { ($0.kind, $0) })
        return ManagedTranscriptionModelKind.allCases.map { kind in
            byKind[kind]
                ?? ManagedTranscriptionModelStatus(
                    kind: kind,
                    displayName: kind.displayName,
                    modelID: kind.modelID,
                    directoryPath: KotoTypeStoragePaths.managedModelDirectory(for: kind).path,
                    isDownloaded: false,
                    fileCount: 0,
                    byteCount: 0
                )
        }
    }

    private var isStorageBusy: Bool {
        isRefreshingStorage || activeModelOperation != nil
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
