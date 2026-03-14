import AppKit
import Dispatch
import Foundation
import os.log
import UniformTypeIdentifiers

@MainActor
private final class RecordingSessionContext {
    let id: Int
    let batchTranscriptionManager: BatchTranscriptionManager
    var finalizationReadyWorkItem: DispatchWorkItem?
    var completionTimeoutWorkItem: DispatchWorkItem?
    private var screenshotContext: String?

    init(id: Int) {
        self.id = id
        self.batchTranscriptionManager = BatchTranscriptionManager()
    }

    func cancelCompletionTimeout() {
        completionTimeoutWorkItem?.cancel()
        completionTimeoutWorkItem = nil
    }

    func cancelFinalizationReadyWorkItem() {
        finalizationReadyWorkItem?.cancel()
        finalizationReadyWorkItem = nil
    }

    func setScreenshotContext(_ context: String?) {
        screenshotContext = context
    }

    func consumeScreenshotContext() -> String? {
        defer { screenshotContext = nil }
        return screenshotContext
    }

    func clearScreenshotContext() {
        screenshotContext = nil
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var hotkeyManager: HotkeyManager?
    var realtimeRecorder: RealtimeRecorder?
    var multiProcessManager: MultiProcessManager?
    private var appUpdater: AppUpdater?
    var settingsWindowController: SettingsWindowController?
    var historyWindowController: HistoryWindowController?
    var recordingIndicatorWindow: RecordingIndicatorWindow?
    var initialSetupWindowController: InitialSetupWindowController?
    var isRecording = false
    private var isImportingAudio = false
    private var isCancelingImportedAudioTranscription = false
    private var didSuspendRealtimeWorkersForImport = false
    private var importedAudioTranscriptionManager: ImportedAudioTranscriptionManager?
    private var serverScriptPath: String = ""
    private var currentSettings: AppSettings = AppSettings()
    private var nextRecordingSessionID = 0
    private var activeRecordingSessionID: Int?
    private var indicatorPresentation = IndicatorPresentationState()
    private var sessionByID: [Int: RecordingSessionContext] = [:]
    private var finalizationQueue = RecordingFinalizationQueue()
    private var pendingSegmentFiles: [Int: URL] = [:]
    private var segmentRouter = RecordingSegmentRouter()
    private var ignoredLateSegmentCompletions: [Int: Date] = [:]
    private let finalizationReadyDelay: TimeInterval = 0.35
    private let completionTimeoutInterval: TimeInterval = 50.0
    private let ignoredLateSegmentTTL: TimeInterval = 120.0
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var temporaryBatchCleanupTimer: DispatchSourceTimer?
    private var adaptiveWorkerCap: Int?
    private var currentRealtimeWorkerCount = 0
    private var pendingWorkerReconfigure = false
    private let temporaryBatchDirectoryName = "koto-type-batch-recordings"
    private let staleBatchFileMaxAge: TimeInterval = 6 * 60 * 60
    private let temporaryBatchCleanupInterval: TimeInterval = 10 * 60

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

    nonisolated static func backendServerLimits(
        requestedWorkers: Int,
        bundlePath: String = Bundle.main.bundlePath
    ) -> (maxActiveServers: Int, maxParallelModelLoads: Int) {
        let workerCount = resolvedWorkerCount(requested: requestedWorkers, bundlePath: bundlePath)
        return (max(1, workerCount), 1)
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
            self.showFirstRecordingGuideAlert()
        }
        initialSetupWindowController?.showWindow(nil)
    }
    
    private func continueSetup() {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
        Logger.shared.log("MenuBarController created", level: .debug)
        appUpdater = AppUpdater()

        realtimeRecorder = RealtimeRecorder()
        Logger.shared.log("RealtimeRecorder created", level: .debug)
        multiProcessManager = MultiProcessManager()
        Logger.shared.log("MultiProcessManager created", level: .debug)
        settingsWindowController = SettingsWindowController()
        historyWindowController = HistoryWindowController()
        recordingIndicatorWindow = RecordingIndicatorWindow { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelRecording()
            }
        }
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
        menuBarController?.checkForUpdates = { [weak self] in
            self?.appUpdater?.checkForUpdates()
        }
        menuBarController?.setCheckForUpdatesEnabled(appUpdater?.isConfigured == true)
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
        reinitializeRealtimeWorkers(force: true, reason: "initial startup")
        setupMemoryPressureMonitoring()
        cleanupStaleTemporaryBatchFiles()
        startTemporaryBatchCleanupTimer()
        _ = LaunchAtLoginManager.shared.setEnabled(currentSettings.launchAtLogin)

        multiProcessManager?.outputReceived = { [weak self] processIndex, output in
            guard self != nil else { return }
            Logger.shared.log(
                "Transcription received from process \(processIndex) (length=\(output.count))",
                level: .info
            )
            
            if output.isEmpty {
                Logger.shared.log("Empty transcription received, skipping", level: .warning)
            }
        }
        
        multiProcessManager?.segmentComplete = { [weak self] segmentIndex, output in
            guard let self = self else { return }
            Logger.shared.log(
                "Segment complete - index=\(segmentIndex), outputLength=\(output.count)",
                level: .info
            )
            self.handleSegmentComplete(globalIndex: segmentIndex, output: output)
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
                let previousParallelism = self.currentSettings.parallelism
                self.currentSettings = SettingsManager.shared.load()
                Logger.shared.log("AppDelegate: Reloaded settings - language=\(self.currentSettings.language), temp=\(self.currentSettings.temperature), beam=\(self.currentSettings.beamSize)")
                if self.currentSettings.parallelism != previousParallelism {
                    self.pendingWorkerReconfigure = true
                    self.applyPendingWorkerReconfigureIfPossible()
                }
            }
        }
    }
    
    func startRecording() {
        guard !isImportingAudio else {
            Logger.shared.log("Recording request ignored because imported audio transcription is running", level: .warning)
            return
        }
        guard !isRecording else {
            Logger.shared.log("Recording request ignored because recording is already active", level: .debug)
            return
        }

        let session = createRecordingSession()
        let sessionID = session.id
        isRecording = true
        activeRecordingSessionID = sessionID
        indicatorPresentation.beginLiveSession(sessionID)
        Logger.shared.log("Starting audio recording for session \(sessionID)...", level: .info)

        currentSettings = SettingsManager.shared.load()
        realtimeRecorder?.batchInterval = currentSettings.batchInterval
        realtimeRecorder?.silenceThreshold = Float(currentSettings.silenceThreshold)
        realtimeRecorder?.silenceDuration = currentSettings.silenceDuration
        realtimeRecorder?.onInputLevelChanged = { [weak self] level in
            self?.recordingIndicatorWindow?.updateRecordingLevel(CGFloat(level))
        }
        recordingIndicatorWindow?.updateRecordingLevel(0)

        realtimeRecorder?.onFileCreated = { [weak self] url, localIndex in
            guard let self = self else { return }
            guard let currentSession = self.sessionByID[sessionID] else {
                Logger.shared.log(
                    "Discarding created file because session \(sessionID) is no longer active: \(url.path)",
                    level: .warning
                )
                self.removeAudioFileIfExists(url)
                return
            }

            let globalIndex = self.segmentRouter.register(sessionID: sessionID, localIndex: localIndex)
            Logger.shared.log(
                "File created: \(url.path), localIndex=\(localIndex), globalIndex=\(globalIndex), session=\(sessionID)",
                level: .info
            )
            self.pendingSegmentFiles[globalIndex] = url
            currentSession.batchTranscriptionManager.addSegment(url: url, index: localIndex)
            let screenshotContext = currentSession.consumeScreenshotContext()
            self.multiProcessManager?.processFile(
                url: url,
                index: globalIndex,
                settings: self.currentSettings,
                screenshotContext: screenshotContext
            )
        }

        guard realtimeRecorder?.startRecording() == true else {
            Logger.shared.log("Failed to start recording", level: .error)
            if realtimeRecorder?.lastStartFailureReason == .noInputDevice {
                Logger.shared.log("Recording aborted: microphone input device is unavailable", level: .warning)
                showTransientRecordingAttention("Microphone not detected")
            }
            realtimeRecorder?.onInputLevelChanged = nil
            recordingIndicatorWindow?.updateRecordingLevel(0)
            isRecording = false
            activeRecordingSessionID = nil
            destroySession(sessionID: sessionID)
            return
        }
        Logger.shared.log("Recording started (session \(sessionID))", level: .info)
        recordingIndicatorWindow?.show()
    }

    private func showTransientRecordingAttention(_ message: String) {
        indicatorPresentation.beginNonLivePresentation()
        recordingIndicatorWindow?.showAttention(message: message)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self = self else { return }
            guard !self.isRecording else { return }
            guard !self.isImportingAudio else { return }
            self.recordingIndicatorWindow?.hide()
        }
    }
    
    func stopRecording() {
        guard isRecording, let sessionID = activeRecordingSessionID, let session = sessionByID[sessionID] else {
            return
        }

        isRecording = false
        activeRecordingSessionID = nil
        session.setScreenshotContext(ScreenContextExtractor.captureScreenTextContext())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sessionByID[sessionID]?.clearScreenshotContext()
        }
        Logger.shared.log("Stopping audio recording for session \(sessionID)...", level: .info)
        realtimeRecorder?.stopRecording()
        realtimeRecorder?.onInputLevelChanged = nil
        recordingIndicatorWindow?.updateRecordingLevel(0)
        Logger.shared.log("Recording stopped (session \(sessionID))", level: .info)
        Logger.shared.log("Waiting for transcription completion (session \(sessionID))...", level: .info)
        recordingIndicatorWindow?.showProcessing()
        enqueueSessionForFinalization(sessionID: sessionID)
        tryFinalizePendingSessionsIfNeeded()
    }

    private func cancelRecording() {
        if isRecording, let sessionID = activeRecordingSessionID {
            Logger.shared.log("Canceling audio recording for session \(sessionID)...", level: .info)
            isRecording = false
            activeRecordingSessionID = nil
            realtimeRecorder?.stopRecording(discardPendingAudio: true)
            realtimeRecorder?.onInputLevelChanged = nil
            recordingIndicatorWindow?.updateRecordingLevel(0)
            destroySession(sessionID: sessionID)

            if indicatorPresentation.currentLiveSessionID == nil {
                recordingIndicatorWindow?.hide()
            } else {
                recordingIndicatorWindow?.showProcessing()
            }

            Logger.shared.log("Recording canceled (session \(sessionID))", level: .info)
            tryFinalizePendingSessionsIfNeeded()
            return
        }

        if let sessionID = indicatorPresentation.currentLiveSessionID {
            Logger.shared.log("Canceling pending transcription for session \(sessionID)...", level: .info)
            destroySession(sessionID: sessionID)

            if indicatorPresentation.currentLiveSessionID == nil {
                recordingIndicatorWindow?.hide()
            } else {
                recordingIndicatorWindow?.showProcessing()
            }

            Logger.shared.log("Pending transcription canceled (session \(sessionID))", level: .info)
            tryFinalizePendingSessionsIfNeeded()
            return
        }

        if isImportingAudio {
            Logger.shared.log("Canceling imported audio transcription...", level: .info)
            isImportingAudio = false
            isCancelingImportedAudioTranscription = true
            importedAudioTranscriptionManager?.stop()
            recordingIndicatorWindow?.hide()
            resumeRealtimeTranscriptionWorkersAfterImportIfNeeded()
            applyPendingWorkerReconfigureIfPossible()
            return
        }

        Logger.shared.log("Cancel request ignored because there is no active recording/transcription task", level: .debug)
    }

    private func createRecordingSession() -> RecordingSessionContext {
        let sessionID = nextRecordingSessionID
        nextRecordingSessionID += 1
        let session = RecordingSessionContext(id: sessionID)
        sessionByID[sessionID] = session
        return session
    }

    private func destroySession(sessionID: Int) {
        guard let session = sessionByID.removeValue(forKey: sessionID) else {
            return
        }
        session.cancelFinalizationReadyWorkItem()
        session.cancelCompletionTimeout()
        cleanupPendingSegmentFiles(forSessionID: sessionID)
        finalizationQueue.remove(sessionID: sessionID)
        if indicatorPresentation.currentLiveSessionID == sessionID {
            indicatorPresentation.setFallbackLiveSession(finalizationQueue.liveIndicatorFallbackSessionID)
        }
    }

    private func handleSegmentComplete(globalIndex: Int, output: String) {
        guard let route = segmentRouter.consume(globalIndex: globalIndex) else {
            if shouldIgnoreLateSegmentCompletion(globalIndex: globalIndex) {
                Logger.shared.log(
                    "Ignoring late segment completion for cleaned-up global index=\(globalIndex).",
                    level: .debug
                )
                cleanupSegmentFile(globalIndex: globalIndex)
                return
            }
            Logger.shared.log(
                "Received segment completion for unknown global index=\(globalIndex). Ignoring stale callback.",
                level: .warning
            )
            cleanupSegmentFile(globalIndex: globalIndex)
            return
        }

        cleanupSegmentFile(globalIndex: globalIndex)

        guard let session = sessionByID[route.sessionID] else {
            Logger.shared.log(
                "Session \(route.sessionID) no longer exists for segment \(globalIndex).",
                level: .warning
            )
            return
        }

        session.batchTranscriptionManager.completeSegment(index: route.localIndex, text: output)
        tryFinalizePendingSessionsIfNeeded()
    }

    private func enqueueSessionForFinalization(sessionID: Int) {
        guard let session = sessionByID[sessionID] else {
            return
        }
        finalizationQueue.enqueue(sessionID: sessionID)

        session.cancelFinalizationReadyWorkItem()
        let readyWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, let session = self.sessionByID[sessionID] else { return }
            session.finalizationReadyWorkItem = nil
            self.finalizationQueue.markReady(sessionID: sessionID)
            self.tryFinalizePendingSessionsIfNeeded()
        }
        session.finalizationReadyWorkItem = readyWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + finalizationReadyDelay, execute: readyWorkItem)

        session.cancelCompletionTimeout()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let session = self.sessionByID[sessionID] else { return }
            session.completionTimeoutWorkItem = nil
            self.finalizationQueue.markTimedOut(sessionID: sessionID)
            Logger.shared.log("Transcription timeout reached for session \(sessionID). Finalizing with available text.", level: .warning)
            self.tryFinalizePendingSessionsIfNeeded()
        }
        session.completionTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + completionTimeoutInterval, execute: workItem)
    }

    private func tryFinalizePendingSessionsIfNeeded() {
        guard !isRecording else {
            return
        }

        while let nextSessionID = finalizationQueue.nextPendingSessionID {
            guard let session = sessionByID[nextSessionID] else {
                finalizationQueue.remove(sessionID: nextSessionID)
                continue
            }

            let shouldFinalize = finalizationQueue.canFinalize(
                sessionID: nextSessionID,
                isComplete: session.batchTranscriptionManager.isComplete()
            )
            guard shouldFinalize else {
                break
            }

            finalizationQueue.remove(sessionID: nextSessionID)
            finalizeSession(sessionID: nextSessionID)
        }

        applyPendingWorkerReconfigureIfPossible()
    }

    private func finalizeSession(sessionID: Int) {
        guard let session = sessionByID.removeValue(forKey: sessionID) else {
            return
        }

        session.cancelCompletionTimeout()
        session.cancelFinalizationReadyWorkItem()

        let finalText = session.batchTranscriptionManager.finalize() ?? ""
        let didInsertText: Bool
        if !finalText.isEmpty {
            Logger.shared.log(
                "Typing text into active window (session \(sessionID), length=\(finalText.count))",
                level: .info
            )
            KeystrokeSimulator.typeText(finalText)
            Logger.shared.log("Text typing completed (session \(sessionID))", level: .info)
            TranscriptionHistoryManager.shared.addEntry(
                text: finalText,
                source: .liveRecording
            )
            didInsertText = true
        } else {
            didInsertText = false
        }

        cleanupPendingSegmentFiles(forSessionID: sessionID)
        session.batchTranscriptionManager.reset()

        guard indicatorPresentation.currentLiveSessionID == sessionID else {
            return
        }
        recordingIndicatorWindow?.showCompleted(success: didInsertText)
        let hideToken = indicatorPresentation.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self else { return }
            guard self.indicatorPresentation.canHideCompletedSession(
                sessionID: sessionID,
                token: hideToken,
                isRecording: self.isRecording,
                isImportingAudio: self.isImportingAudio
            ) else { return }
            self.recordingIndicatorWindow?.hide()
            self.indicatorPresentation.didHideCompletedSession(
                sessionID: sessionID,
                fallbackSessionID: self.finalizationQueue.liveIndicatorFallbackSessionID
            )
        }
    }

    private func showFirstRecordingGuideAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Setup complete. Run your first dictation."
        alert.informativeText = """
        1. Open any app and click a text field.
        2. Hold your hotkey (default: Command+Option) while speaking.
        3. Release the hotkey and wait for text insertion.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentImportAudioPanel() {
        guard !isRecording else {
            Logger.shared.log("Cannot import audio while recording", level: .warning)
            return
        }

        guard finalizationQueue.isEmpty else {
            Logger.shared.log(
                "Cannot import audio while live recording transcription is still processing",
                level: .warning
            )
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
        indicatorPresentation.beginNonLivePresentation()
        recordingIndicatorWindow?.showProcessing()

        importedAudioTranscriptionManager.transcribe(fileURL: fileURL, settings: currentSettings) { [weak self] result in
            guard let self = self else { return }
            self.isImportingAudio = false
            self.recordingIndicatorWindow?.hide()
            self.resumeRealtimeTranscriptionWorkersAfterImportIfNeeded()

            if self.isCancelingImportedAudioTranscription {
                self.isCancelingImportedAudioTranscription = false
                Logger.shared.log("Imported audio transcription canceled by user", level: .info)
                return
            }

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

        didSuspendRealtimeWorkersForImport = false
        reinitializeRealtimeWorkers(force: true, reason: "resume after imported audio")
        applyPendingWorkerReconfigureIfPossible()
    }

    private func effectiveRealtimeWorkerCount(requested: Int) -> Int {
        var workerCount = Self.resolvedWorkerCount(requested: requested)
        if let adaptiveWorkerCap {
            workerCount = min(workerCount, max(1, adaptiveWorkerCap))
        }
        return max(1, workerCount)
    }

    private func reinitializeRealtimeWorkers(force: Bool, reason: String) {
        guard let multiProcessManager else { return }
        guard !serverScriptPath.isEmpty else { return }

        currentSettings = SettingsManager.shared.load()
        let requestedWorkerCount = currentSettings.parallelism
        let bundleResolvedWorkerCount = Self.resolvedWorkerCount(requested: requestedWorkerCount)
        let effectiveWorkerCount = effectiveRealtimeWorkerCount(requested: requestedWorkerCount)
        let backendLimits = Self.backendServerLimits(requestedWorkers: effectiveWorkerCount)

        if !force && currentRealtimeWorkerCount == effectiveWorkerCount {
            return
        }

        if bundleResolvedWorkerCount != requestedWorkerCount {
            Logger.shared.log(
                "Worker count clamped from \(requestedWorkerCount) to \(bundleResolvedWorkerCount) for app-bundle execution",
                level: .warning
            )
        }
        if let adaptiveWorkerCap, effectiveWorkerCount != bundleResolvedWorkerCount {
            Logger.shared.log(
                "Worker count further limited by adaptive memory-pressure cap: \(bundleResolvedWorkerCount) -> \(effectiveWorkerCount) (cap=\(adaptiveWorkerCap))",
                level: .warning
            )
        }

        setenv("KOTOTYPE_MAX_ACTIVE_SERVERS", "\(backendLimits.maxActiveServers)", 1)
        setenv("KOTOTYPE_MAX_PARALLEL_MODEL_LOADS", "\(backendLimits.maxParallelModelLoads)", 1)

        multiProcessManager.initialize(count: effectiveWorkerCount, scriptPath: serverScriptPath)
        currentRealtimeWorkerCount = effectiveWorkerCount
        Logger.shared.log(
            "MultiProcessManager initialized with \(effectiveWorkerCount) processes (\(reason)); backend limits activeServers=\(backendLimits.maxActiveServers), parallelModelLoads=\(backendLimits.maxParallelModelLoads)",
            level: .info
        )
    }

    private func setupMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            Task { @MainActor [weak self] in
                self?.handleMemoryPressureEvent(event)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        guard event.contains(.warning) || event.contains(.critical) else {
            return
        }

        let eventDescription: String
        if event.contains(.critical) {
            eventDescription = "critical"
        } else if event.contains(.warning) {
            eventDescription = "warning"
        } else {
            eventDescription = "unknown"
        }

        let baselineWorkerCount = max(1, currentRealtimeWorkerCount)
        let targetCap = event.contains(.critical)
            ? 1
            : max(1, baselineWorkerCount - 1)

        if let currentCap = adaptiveWorkerCap, targetCap >= currentCap {
            Logger.shared.log(
                "Memory pressure event (\(eventDescription)) received, but worker cap already at \(currentCap)",
                level: .warning
            )
            return
        }

        adaptiveWorkerCap = targetCap
        pendingWorkerReconfigure = true
        Logger.shared.log(
            "Memory pressure event (\(eventDescription)) detected; scheduling worker cap update to \(targetCap)",
            level: .warning
        )
        applyPendingWorkerReconfigureIfPossible()
    }

    private func applyPendingWorkerReconfigureIfPossible() {
        guard pendingWorkerReconfigure else {
            return
        }
        guard !isRecording else {
            return
        }
        guard finalizationQueue.isEmpty else {
            return
        }
        guard !isImportingAudio else {
            return
        }
        guard !didSuspendRealtimeWorkersForImport else {
            return
        }

        pendingWorkerReconfigure = false
        reinitializeRealtimeWorkers(force: true, reason: "adaptive reconfiguration")
    }

    private func startTemporaryBatchCleanupTimer() {
        stopTemporaryBatchCleanupTimer()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + temporaryBatchCleanupInterval,
            repeating: temporaryBatchCleanupInterval
        )
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.cleanupStaleTemporaryBatchFiles()
            }
        }
        timer.resume()
        temporaryBatchCleanupTimer = timer
    }

    private func stopTemporaryBatchCleanupTimer() {
        temporaryBatchCleanupTimer?.cancel()
        temporaryBatchCleanupTimer = nil
    }

    private func cleanupStaleTemporaryBatchFiles() {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(temporaryBatchDirectoryName, isDirectory: true)

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let activePaths = Set(
            pendingSegmentFiles.values.map { $0.standardizedFileURL.path }
        )
        let now = Date()
        var removedCount = 0

        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )

            for fileURL in fileURLs {
                let standardizedPath = fileURL.standardizedFileURL.path
                if activePaths.contains(standardizedPath) {
                    continue
                }

                let values = try fileURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                ])
                guard values.isRegularFile == true else {
                    continue
                }

                let lastUpdatedAt = values.contentModificationDate ?? values.creationDate ?? .distantPast
                guard now.timeIntervalSince(lastUpdatedAt) >= staleBatchFileMaxAge else {
                    continue
                }

                do {
                    try fileManager.removeItem(at: fileURL)
                    removedCount += 1
                } catch {
                    Logger.shared.log(
                        "Failed to remove stale temporary batch file: \(fileURL.path), error: \(error)",
                        level: .warning
                    )
                }
            }

            if removedCount > 0 {
                Logger.shared.log(
                    "Removed \(removedCount) stale temporary batch file(s) from \(directoryURL.path)",
                    level: .info
                )
            }

            let remaining = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            if remaining.isEmpty {
                try fileManager.removeItem(at: directoryURL)
            }
        } catch {
            Logger.shared.log(
                "Failed to clean stale temporary batch directory \(directoryURL.path): \(error)",
                level: .warning
            )
        }
    }

    private func cleanupSegmentFile(globalIndex: Int) {
        guard let fileURL = pendingSegmentFiles.removeValue(forKey: globalIndex) else {
            return
        }
        removeAudioFileIfExists(fileURL)
    }

    private func cleanupPendingSegmentFiles(forSessionID sessionID: Int) {
        let indices = segmentRouter.removeAll(forSessionID: sessionID)
        rememberIgnoredLateSegmentCompletions(indices)
        for globalIndex in indices {
            cleanupSegmentFile(globalIndex: globalIndex)
        }
    }

    private func cleanupAllPendingSegmentFiles() {
        let indices = Array(pendingSegmentFiles.keys)
        rememberIgnoredLateSegmentCompletions(indices)
        for (_, fileURL) in pendingSegmentFiles {
            removeAudioFileIfExists(fileURL)
        }
        pendingSegmentFiles.removeAll()
        segmentRouter.reset()
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

    private func rememberIgnoredLateSegmentCompletions(_ globalIndices: [Int]) {
        guard !globalIndices.isEmpty else {
            return
        }
        pruneIgnoredLateSegmentCompletions()
        let now = Date()
        for index in globalIndices {
            ignoredLateSegmentCompletions[index] = now
        }
    }

    private func shouldIgnoreLateSegmentCompletion(globalIndex: Int) -> Bool {
        pruneIgnoredLateSegmentCompletions()
        guard ignoredLateSegmentCompletions.removeValue(forKey: globalIndex) != nil else {
            return false
        }
        return true
    }

    private func pruneIgnoredLateSegmentCompletions(now: Date = Date()) {
        ignoredLateSegmentCompletions = ignoredLateSegmentCompletions.filter { _, timestamp in
            now.timeIntervalSince(timestamp) <= ignoredLateSegmentTTL
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopTemporaryBatchCleanupTimer()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        for session in sessionByID.values {
            session.cancelFinalizationReadyWorkItem()
            session.cancelCompletionTimeout()
        }
        sessionByID.removeAll()
        finalizationQueue.reset()
        indicatorPresentation.reset()
        hotkeyManager?.cleanup()
        cleanupAllPendingSegmentFiles()
        cleanupStaleTemporaryBatchFiles()
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
