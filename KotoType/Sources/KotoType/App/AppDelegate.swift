import AppKit
import Foundation
import os.log
import UniformTypeIdentifiers

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var hotkeyManager: HotkeyManager?
    var realtimeRecorder: RealtimeRecorder?
    var multiProcessManager: MultiProcessManager?
    var batchTranscriptionManager: BatchTranscriptionManager?
    var settingsWindowController: SettingsWindowController?
    var historyWindowController: HistoryWindowController?
    var recordingIndicatorWindow: RecordingIndicatorWindow?
    var initialSetupWindowController: InitialSetupWindowController?
    var isRecording = false
    private var isImportingAudio = false
    private var didSuspendRealtimeWorkersForImport = false
    private var importedAudioTranscriptionManager: ImportedAudioTranscriptionManager?
    private var serverScriptPath: String = ""
    private var currentSettings: AppSettings = AppSettings()
    private var lastTranscriptionText: String = ""
    private var pendingSegmentFiles: [Int: URL] = [:]

    nonisolated static func resolvedWorkerCount(
        requested: Int,
        bundlePath: String = Bundle.main.bundlePath
    ) -> Int {
        let normalizedRequested = max(1, requested)
        // Distribution app bundles are memory-sensitive during model boot.
        // Keep one worker to avoid cascading restarts from concurrent model loads.
        if bundlePath.hasSuffix(".app") {
            return 1
        }
        return normalizedRequested
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("Application did finish launching", level: .info)

        let diagnosticsService = InitialSetupDiagnosticsService()
        let report = diagnosticsService.evaluate()
        let setupState = InitialSetupStateManager.shared

        if setupState.hasCompletedInitialSetup && report.canStartApplication {
            continueSetup()
            return
        }

        showInitialSetupWindow(diagnosticsService: diagnosticsService)
    }

    private func showInitialSetupWindow(diagnosticsService: InitialSetupDiagnosticsService) {
        initialSetupWindowController = InitialSetupWindowController(
            diagnosticsService: diagnosticsService
        ) { [weak self] in
            guard let self else { return }
            InitialSetupStateManager.shared.markCompleted()
            self.initialSetupWindowController?.close()
            self.initialSetupWindowController = nil
            self.continueSetup()
        }
        initialSetupWindowController?.showWindow(nil)
    }
    
    private func continueSetup() {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
        Logger.shared.log("MenuBarController created", level: .debug)

        realtimeRecorder = RealtimeRecorder()
        Logger.shared.log("RealtimeRecorder created", level: .debug)
        multiProcessManager = MultiProcessManager()
        Logger.shared.log("MultiProcessManager created", level: .debug)
        batchTranscriptionManager = BatchTranscriptionManager()
        Logger.shared.log("BatchTranscriptionManager created", level: .debug)
        batchTranscriptionManager?.onTranscriptionComplete = { [weak self] text in
            guard let self = self else { return }
            if text.isEmpty {
                Logger.shared.log("BatchTranscriptionManager emitted empty ordered text chunk", level: .debug)
                return
            }
            self.lastTranscriptionText += text
            Logger.shared.log("Accumulated ordered transcription: '\(self.lastTranscriptionText)'", level: .info)
        }
        settingsWindowController = SettingsWindowController()
        historyWindowController = HistoryWindowController()
        recordingIndicatorWindow = RecordingIndicatorWindow()
        Logger.shared.log("RecordingIndicatorWindow created", level: .debug)
        
        menuBarController?.showSettings = { [weak self] in
            self?.settingsWindowController?.showSettings()
        }
        menuBarController?.showHistory = { [weak self] in
            self?.historyWindowController?.showHistory()
        }
        menuBarController?.importAudioFile = { [weak self] in
            self?.presentImportAudioPanel()
        }
        settingsWindowController?.onImportAudioRequested = { [weak self] in
            self?.presentImportAudioPanel()
        }
        settingsWindowController?.onShowHistoryRequested = { [weak self] in
            self?.historyWindowController?.showHistory()
        }
        
        let scriptPath = BackendLocator.serverScriptPath()
        serverScriptPath = scriptPath
        Logger.shared.log("Starting Python process at: \(scriptPath)", level: .info)

        currentSettings = SettingsManager.shared.load()
        let workerCount = Self.resolvedWorkerCount(requested: currentSettings.parallelism)
        if workerCount != currentSettings.parallelism {
            Logger.shared.log(
                "Worker count clamped from \(currentSettings.parallelism) to \(workerCount) for app-bundle execution",
                level: .warning
            )
        }
        multiProcessManager?.initialize(count: workerCount, scriptPath: scriptPath)
        Logger.shared.log("MultiProcessManager initialized with \(workerCount) processes", level: .info)
        _ = LaunchAtLoginManager.shared.setEnabled(currentSettings.launchAtLogin)

        multiProcessManager?.outputReceived = { [weak self] processIndex, output in
            guard self != nil else { return }
            Logger.shared.log("Transcription received from process \(processIndex): '\(output)'", level: .info)
            
            if output.isEmpty {
                Logger.shared.log("Empty transcription received, skipping", level: .warning)
            }
        }
        
        multiProcessManager?.segmentComplete = { [weak self] segmentIndex, output in
            guard let self = self else { return }
            Logger.shared.log("Segment complete - index=\(segmentIndex), output='\(output)'", level: .info)
            self.batchTranscriptionManager?.completeSegment(index: segmentIndex, text: output)
            self.cleanupSegmentFile(index: segmentIndex)
        }

        currentSettings = SettingsManager.shared.load()
        Logger.shared.log("Loaded settings: \(currentSettings)", level: .info)
        
        hotkeyManager = HotkeyManager()
        hotkeyManager?.hotkeyKeyDown = { [weak self] in
            self?.startRecording()
        }
        hotkeyManager?.hotkeyKeyUp = { [weak self] in
            self?.stopRecording()
        }
        
        NotificationCenter.default.addObserver(forName: .hotkeyConfigurationChanged, object: nil, queue: .main) { [weak self] notification in
            let config = notification.object as? HotkeyConfiguration
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let config = config {
                    Logger.shared.log("AppDelegate: Received hotkeyConfigurationChanged notification: \(config.description)")
                }
                self.currentSettings = SettingsManager.shared.load()
                Logger.shared.log("AppDelegate: Reloaded settings - language=\(self.currentSettings.language), temp=\(self.currentSettings.temperature), beam=\(self.currentSettings.beamSize)")
            }
        }
    }
    
    func startRecording() {
        guard !isImportingAudio else {
            Logger.shared.log("Recording request ignored because imported audio transcription is running", level: .warning)
            return
        }
        isRecording = true
        lastTranscriptionText = ""
        batchTranscriptionManager?.reset()
        cleanupAllPendingSegmentFiles()
        Logger.shared.log("Starting audio recording...", level: .info)

        currentSettings = SettingsManager.shared.load()
        realtimeRecorder?.batchInterval = currentSettings.batchInterval
        realtimeRecorder?.silenceThreshold = Float(currentSettings.silenceThreshold)
        realtimeRecorder?.silenceDuration = currentSettings.silenceDuration

        realtimeRecorder?.onFileCreated = { [weak self] url, index in
            guard let self = self else { return }
            Logger.shared.log("File created: \(url.path), index: \(index)", level: .info)
            self.pendingSegmentFiles[index] = url
            self.batchTranscriptionManager?.addSegment(url: url, index: index)
            self.multiProcessManager?.processFile(url: url, index: index, settings: self.currentSettings)
        }

        guard realtimeRecorder?.startRecording() == true else {
            Logger.shared.log("Failed to start recording", level: .error)
            isRecording = false
            return
        }
        Logger.shared.log("Recording started", level: .info)
        recordingIndicatorWindow?.show()
    }
    
    func stopRecording() {
        isRecording = false
        Logger.shared.log("Stopping audio recording...", level: .info)
        realtimeRecorder?.stopRecording()
        Logger.shared.log("Recording stopped", level: .info)
        Logger.shared.log("Waiting for transcription to complete...", level: .info)
        recordingIndicatorWindow?.showProcessing()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.waitForTranscriptionComplete(attempt: 0)
        }
    }

    private func waitForTranscriptionComplete(attempt: Int) {
        Logger.shared.log("Waiting for batch transcription to complete...", level: .info)
        
        let maxAttempts = 100
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let nextAttempt = attempt + 1
            
            if self.batchTranscriptionManager?.isComplete() == true {
                Logger.shared.log("All transcriptions completed", level: .info)
                self.completeTranscription()
            } else if nextAttempt >= maxAttempts {
                Logger.shared.log("Transcription timeout after \(maxAttempts) attempts", level: .warning)
                self.completeTranscription()
            } else {
                Logger.shared.log("Transcription still in progress, waiting... (attempt \(nextAttempt)/\(maxAttempts))", level: .debug)
                self.waitForTranscriptionComplete(attempt: nextAttempt)
            }
        }
    }

    private func completeTranscription() {
        Logger.shared.log("Completing transcription", level: .info)

        let finalText = batchTranscriptionManager?.finalize() ?? lastTranscriptionText

        if !finalText.isEmpty {
            Logger.shared.log("Typing text into active window: '\(finalText)'", level: .info)
            KeystrokeSimulator.typeText(finalText)
            Logger.shared.log("Text typing completed", level: .info)
            TranscriptionHistoryManager.shared.addEntry(
                text: finalText,
                source: .liveRecording
            )
        }

        cleanupAllPendingSegmentFiles()
        batchTranscriptionManager?.reset()
        lastTranscriptionText = ""

        recordingIndicatorWindow?.hide()
    }

    private func presentImportAudioPanel() {
        guard !isRecording else {
            Logger.shared.log("Cannot import audio while recording", level: .warning)
            return
        }

        guard !isImportingAudio else {
            Logger.shared.log("Import request ignored because transcription is already running", level: .warning)
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "wav"),
            UTType(filenameExtension: "mp3"),
        ].compactMap { $0 }
        panel.prompt = "Transcribe"
        panel.title = "Select Audio File"
        panel.message = "Please select a wav or mp3 file"
        NSApp.activate(ignoringOtherApps: true)

        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.transcribeImportedAudioFile(selectedURL)
            }
        }
    }

    private func transcribeImportedAudioFile(_ fileURL: URL) {
        guard !isImportingAudio else { return }
        suspendRealtimeTranscriptionWorkersForImportIfNeeded()
        if importedAudioTranscriptionManager == nil {
            importedAudioTranscriptionManager = ImportedAudioTranscriptionManager()
        }
        importedAudioTranscriptionManager?.configure(scriptPath: serverScriptPath)
        guard let importedAudioTranscriptionManager else { return }
        isImportingAudio = true
        currentSettings = SettingsManager.shared.load()
        recordingIndicatorWindow?.showProcessing()

        importedAudioTranscriptionManager.transcribe(fileURL: fileURL, settings: currentSettings) { [weak self] result in
            guard let self = self else { return }
            self.isImportingAudio = false
            self.recordingIndicatorWindow?.hide()
            self.resumeRealtimeTranscriptionWorkersAfterImportIfNeeded()

            switch result {
            case let .success(output):
                let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    Logger.shared.log("Imported audio transcription returned empty text", level: .warning)
                    return
                }
                TranscriptionHistoryManager.shared.addEntry(
                    text: text,
                    source: .importedFile,
                    audioFilePath: fileURL.path
                )
                self.historyWindowController?.showHistory()
                Logger.shared.log("Imported audio transcription completed and saved to history", level: .info)
            case let .failure(error):
                Logger.shared.log("Imported audio transcription failed: \(error)", level: .error)
            }
        }
    }

    private func suspendRealtimeTranscriptionWorkersForImportIfNeeded() {
        guard !didSuspendRealtimeWorkersForImport else { return }
        guard multiProcessManager?.getProcessCount() ?? 0 > 0 else { return }

        Logger.shared.log("Suspending realtime transcription workers for file import", level: .info)
        multiProcessManager?.stop()
        didSuspendRealtimeWorkersForImport = true
    }

    private func resumeRealtimeTranscriptionWorkersAfterImportIfNeeded() {
        guard didSuspendRealtimeWorkersForImport else { return }
        guard !serverScriptPath.isEmpty else { return }

        currentSettings = SettingsManager.shared.load()
        let workerCount = Self.resolvedWorkerCount(requested: currentSettings.parallelism)
        if workerCount != currentSettings.parallelism {
            Logger.shared.log(
                "Worker count clamped from \(currentSettings.parallelism) to \(workerCount) for app-bundle execution",
                level: .warning
            )
        }
        multiProcessManager?.initialize(count: workerCount, scriptPath: serverScriptPath)
        Logger.shared.log("Resumed realtime transcription workers after file import", level: .info)
        didSuspendRealtimeWorkersForImport = false
    }

    private func cleanupSegmentFile(index: Int) {
        guard let fileURL = pendingSegmentFiles.removeValue(forKey: index) else {
            return
        }
        removeAudioFileIfExists(fileURL)
    }

    private func cleanupAllPendingSegmentFiles() {
        for (_, fileURL) in pendingSegmentFiles {
            removeAudioFileIfExists(fileURL)
        }
        pendingSegmentFiles.removeAll()
    }

    private func removeAudioFileIfExists(_ fileURL: URL) {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                Logger.shared.log("Removed processed batch file: \(fileURL.path)", level: .debug)
            }
        } catch {
            Logger.shared.log("Failed to remove processed batch file: \(fileURL.path), error: \(error)", level: .warning)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.cleanup()
        multiProcessManager?.stop()
        importedAudioTranscriptionManager?.stop()
    }
}

@main
struct Main {
    static func main() {
        if CommandLine.arguments.contains("--diagnose-accessibility") {
            let snapshot = AccessibilityDiagnostics.collect()
            print(AccessibilityDiagnostics.renderJSON(snapshot))
            return
        }
        if CommandLine.arguments.contains("--diagnose-initial-setup") {
            let snapshot = AccessibilityDiagnostics.collectInitialSetup()
            print(AccessibilityDiagnostics.renderJSON(snapshot))
            return
        }

        print("Main: Starting application")
        let app = NSApplication.shared
        print("Main: Application created")
        app.setActivationPolicy(.accessory)
        print("Main: Activation policy set to accessory")
        
        let delegate = AppDelegate()
        print("Main: AppDelegate created")
        app.delegate = delegate
        print("Main: Delegate assigned")
        
        print("Main: Running application")
        app.run()
    }
}
