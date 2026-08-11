import AppKit
import Dispatch
import Foundation
import os.log
import UniformTypeIdentifiers

@MainActor
private final class RecordingSessionContext {
    let id: Int
    let mode: RecordingRequestMode
    let translationTargetLanguage: String
    let batchTranscriptionManager: BatchTranscriptionManager
    let windowFocusTarget: WindowFocusTarget?
    var rawTranscription: String?
    var promptUsedFallback = false
    var liveTranscriptionPolicy: LiveTranscriptionPolicy?
    var finalizationReadyWorkItem: DispatchWorkItem?
    var completionTimeoutWorkItem: DispatchWorkItem?
    private var screenshotContext: String?

    init(
        id: Int,
        mode: RecordingRequestMode,
        translationTargetLanguage: String,
        windowFocusTarget: WindowFocusTarget?
    ) {
        self.id = id
        self.mode = mode
        self.translationTargetLanguage = translationTargetLanguage
        self.windowFocusTarget = windowFocusTarget
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

private enum DeferredRecordingStartupAction {
    case stop
    case cancel
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let initialSetupCompletedKey = "initialSetupCompleted"
    var menuBarController: MenuBarController?
    var hotkeyManager: HotkeyManager?
    var realtimeRecorder: RealtimeRecorder?
    var multiProcessManager: MultiProcessManager?
    private var appUpdater: AppUpdater?
    var settingsWindowController: SettingsWindowController?
    var historyWindowController: HistoryWindowController?
    var recordingIndicatorWindow: RecordingIndicatorWindow?
    var promptReviewWindow: PromptReviewWindow?
    var initialSetupWindowController: InitialSetupWindowController?
    var isRecording = false
    private var isImportingAudio = false
    private var isCancelingImportedAudioTranscription = false
    private var didSuspendRealtimeWorkersForImport = false
    private var pressedRecordingModes: Set<RecordingRequestMode> = []
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
    private let ignoredLateSegmentTTL: TimeInterval = 120.0
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var temporaryBatchCleanupTimer: DispatchSourceTimer?
    private var adaptiveWorkerCap: Int?
    private var currentRealtimeWorkerCount = 0
    private var pendingWorkerReconfigure = false
    private var pendingWorkerReconfigurePreloadModel = false
    private var pendingLiveRecordingProcessingMessage: String?
    private var startingRecordingSessionID: Int?
    private var deferredRecordingStartupAction: DeferredRecordingStartupAction?
    private let staleBatchFileMaxAge: TimeInterval = 6 * 60 * 60
    private let temporaryBatchCleanupInterval: TimeInterval = 10 * 60
    private let backendPreparationRetryDelay: TimeInterval = 0.25
    private let maxBackendPreparationRetries = 40
    private let initialSetupBackendPreparationTimeout: TimeInterval = 180
    private let permissionResetService: PermissionResetService

    init(permissionResetService: PermissionResetService = PermissionResetService()) {
        self.permissionResetService = permissionResetService
        super.init()
    }

    nonisolated static func resolvedWorkerCount(
        requested: Int,
        bundlePath: String = Bundle.main.bundlePath
    ) -> Int {
        max(1, requested)
    }

    nonisolated static func backendServerLimits(
        requestedWorkers: Int,
        bundlePath: String = Bundle.main.bundlePath
    ) -> (maxActiveServers: Int, maxParallelModelLoads: Int) {
        let workerCount = resolvedWorkerCount(
            requested: requestedWorkers,
            bundlePath: bundlePath
        )
        return (max(1, workerCount), 1)
    }

    // Dispatch source handlers run on their configured queue, so create a nonisolated
    // trampoline that captures queue-local state before hopping back to the main actor.
    nonisolated static func makeMainActorDispatchHandler(
        _ operation: @escaping @MainActor () -> Void
    ) -> @Sendable () -> Void {
        makeMainActorDispatchHandler(capture: { () }) { _ in
            operation()
        }
    }

    nonisolated static func makeMainActorDispatchHandler<State: Sendable>(
        capture value: @escaping @Sendable () -> State,
        _ operation: @escaping @MainActor (State) -> Void
    ) -> @Sendable () -> Void {
        {
            let capturedValue = value()
            Task { @MainActor in
                operation(capturedValue)
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("Application did finish launching", level: .info)
        serverScriptPath = Self.serverScriptPath()
        currentSettings = SettingsManager.shared.load()
        Logger.shared.log("Starting Python process at: \(serverScriptPath)", level: .info)

        let diagnosticsService = InitialSetupDiagnosticsService()
        let report = diagnosticsService.evaluate()

        if report.canStartApplication {
            permissionResetService.clearResetAttempt()
        } else if permissionResetService.resetPermissionsIfNeeded(for: report) {
            Logger.shared.log(
                "Application did finish launching: automatically reset required permissions and will relaunch",
                level: .info
            )
            if AppRelauncher.relaunchCurrentApp() {
                NSApp.terminate(nil)
                return
            }
            Logger.shared.log(
                "Application did finish launching: relaunch after automatic permission reset failed",
                level: .warning
            )
            permissionResetService.clearResetAttempt()
        }

        if UserDefaults.standard.bool(forKey: Self.initialSetupCompletedKey) && report.canStartApplication {
            continueSetup()
            return
        }

        showInitialSetupWindow(diagnosticsService: diagnosticsService)
    }

    private static func serverScriptPath(currentPath: String = FileManager.default.currentDirectoryPath) -> String {
        let root = currentPath.range(of: "/KotoType").map {
            String(currentPath[..<$0.lowerBound])
        } ?? currentPath
        return "\(root)/python/whisper_server.py"
    }

    private func showInitialSetupWindow(diagnosticsService: InitialSetupDiagnosticsService) {
        initialSetupWindowController = InitialSetupWindowController(
            diagnosticsService: diagnosticsService,
            prepareBackend: { [weak self] in
                guard let self else { return false }
                return await self.prepareBackendBeforeInitialSetup()
            }
        ) { [weak self] in
            guard let self else { return }
            await self.completeInitialSetup()
        }
        initialSetupWindowController?.showWindow(nil)
    }

    private func prepareBackendBeforeInitialSetup() async -> Bool {
        if TranscriptionBackendStatusStore.shared.currentStatus != nil {
            return true
        }

        currentSettings = SettingsManager.shared.load()
        guard currentSettings.keepBackendReadyInBackground else {
            return true
        }

        BackendPreparationProgressStore.shared.reset()
        ensureMultiProcessManagerCreatedIfNeeded()
        Logger.shared.log(
            "Initial setup: starting backend preparation before permission walkthrough",
            level: .info
        )
        ensureRealtimeWorkersInitialized(
            reason: "initial setup",
            preloadModel: true
        )
        return await waitForInitialBackendPreparation()
    }

    private func completeInitialSetup() async {
        UserDefaults.standard.set(true, forKey: Self.initialSetupCompletedKey)
        continueSetup()
        let prepared = currentSettings.keepBackendReadyInBackground
            ? await waitForInitialBackendPreparation()
            : true
        if prepared {
            Logger.shared.log(
                "Initial setup: backend preparation completed before setup finished",
                level: .info
            )
        } else {
            Logger.shared.log(
                "Initial setup: backend preparation is still running after timeout; continuing in background",
                level: .warning
            )
        }
        initialSetupWindowController?.close()
        initialSetupWindowController = nil
        showFirstRecordingGuideAlert()
    }
    
    private func continueSetup() {
        permissionResetService.clearResetAttempt()
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
        Logger.shared.log("MenuBarController created", level: .debug)
        appUpdater = AppUpdater()

        realtimeRecorder = makeRealtimeRecorder()
        Logger.shared.log("RealtimeRecorder created", level: .debug)
        ensureMultiProcessManagerCreatedIfNeeded()
        settingsWindowController = SettingsWindowController()
        historyWindowController = HistoryWindowController()
        recordingIndicatorWindow = RecordingIndicatorWindow { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelRecording()
            }
        }
        promptReviewWindow = PromptReviewWindow()
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
        settingsWindowController?.onSettingsChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleSettingsDidChange()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .transcriptionBackendStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let status = notification.object as? TranscriptionBackendStatus else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleBackendStatusChanged(status)
            }
        }

        ensureMultiProcessManagerCallbacks()
        currentSettings = SettingsManager.shared.load()
        if currentSettings.keepBackendReadyInBackground {
            ensureRealtimeWorkersInitialized(
                reason: "initial startup",
                preloadModel: true
            )
        }
        setupMemoryPressureMonitoring()
        cleanupStaleTemporaryBatchFiles()
        startTemporaryBatchCleanupTimer()
        _ = LaunchAtLoginManager.setEnabled(currentSettings.launchAtLogin)
        Logger.shared.log("Loaded settings: \(currentSettings)", level: .info)
        
        hotkeyManager = HotkeyManager()
        hotkeyManager?.hotkeyKeyDown = { [weak self] mode in
            self?.handleRecordingHotkeyPressed(mode)
        }
        hotkeyManager?.hotkeyKeyUp = { [weak self] mode in
            self?.handleRecordingHotkeyReleased(mode)
        }
        
        NotificationCenter.default.addObserver(forName: .hotkeySettingsChanged, object: nil, queue: .main) { [weak self] notification in
            let settings = notification.object as? AppSettings
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                if let settings {
                    Logger.shared.log(
                        "AppDelegate: Received hotkey settings notification: transcription=\(settings.hotkeyConfig.description), translation=\(settings.translationHotkeyConfig.description), translationTargetLanguage=\(settings.translationTargetLanguage)"
                    )
                }
            }
        }
    }

    private func makeRealtimeRecorder() -> RealtimeRecorder {
        let recorder = RealtimeRecorder()
        recorder.onAudioConfigurationChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.pendingLiveRecordingProcessingMessage = "Audio input was reset. Please try again."
                self.stopRecording()
            }
        }
        return recorder
    }

    private func waitForInitialBackendPreparation() async -> Bool {
        if TranscriptionBackendStatusStore.shared.currentStatus != nil {
            return true
        }

        let timeoutNanoseconds = UInt64(initialSetupBackendPreparationTimeout * 1_000_000_000)
        let notificationCenter = NotificationCenter.default

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in notificationCenter.notifications(
                    named: .transcriptionBackendStatusChanged
                ) {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
    
    func startRecording(mode: RecordingRequestMode = .transcribe) {
        guard !isImportingAudio else {
            Logger.shared.log("Recording request ignored because imported audio transcription is running", level: .warning)
            return
        }
        guard !isRecording else {
            Logger.shared.log("Recording request ignored because recording is already active", level: .debug)
            return
        }

        let windowFocusTarget = WindowFocusRestorer.capture()
        currentSettings = SettingsManager.shared.load()
        beginRecordingSession(mode: mode, windowFocusTarget: windowFocusTarget)
    }

    private func beginRecordingSession(
        mode: RecordingRequestMode,
        windowFocusTarget: WindowFocusTarget?
    ) {
        let session = createRecordingSession(
            mode: mode,
            translationTargetLanguage: currentSettings.translationTargetLanguage,
            windowFocusTarget: windowFocusTarget
        )
        let sessionID = session.id
        let liveTranscriptionPolicy = LiveTranscriptionPolicy.resolve(
            settings: currentSettings,
            latestStatus: TranscriptionBackendStatusStore.shared.currentStatus
        )
        session.liveTranscriptionPolicy = liveTranscriptionPolicy
        pendingLiveRecordingProcessingMessage = nil
        isRecording = true
        activeRecordingSessionID = sessionID
        indicatorPresentation.beginLiveSession(sessionID)
        Logger.shared.log(
            "Starting audio recording for session \(sessionID)... requestMode=\(session.mode.rawValue), translationTargetLanguage=\(session.translationTargetLanguage), backendMode=\(liveTranscriptionPolicy.mode.rawValue), reason=\(liveTranscriptionPolicy.logReason), recordingMaxDuration=\(Int(liveTranscriptionPolicy.recordingMaxDuration))s, processingTimeout=\(Int(liveTranscriptionPolicy.processingTimeout))s, finalizationTimeout=\(Int(liveTranscriptionPolicy.finalizationTimeout))s",
            level: .info
        )

        // Configure the manager callback before recording; the live recording is
        // intentionally submitted as one file after stop (Issue #65).
        ensureMultiProcessManagerCreatedIfNeeded()
        realtimeRecorder?.maxRecordingDuration = liveTranscriptionPolicy.recordingMaxDuration
        realtimeRecorder?.onInputLevelChanged = { [weak self] level in
            self?.recordingIndicatorWindow?.updateRecordingLevel(CGFloat(level))
        }
        realtimeRecorder?.onInputDeviceNameChanged = { [weak self] name in
            self?.recordingIndicatorWindow?.updateRecordingInputDeviceName(name)
        }
        realtimeRecorder?.onMaximumDurationReached = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleLiveRecordingMaximumDurationReached(
                    sessionID: sessionID,
                    policy: liveTranscriptionPolicy
                )
            }
        }
        recordingIndicatorWindow?.updateRecordingLevel(0)
        recordingIndicatorWindow?.updateRecordingInputDeviceName(nil)
        startingRecordingSessionID = sessionID
        deferredRecordingStartupAction = nil
        recordingIndicatorWindow?.showStartingRecording()

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
            let recordingDuration = self.realtimeRecorder?.lastRecordingDuration ?? 0
            let processingTimeout = currentSession.liveTranscriptionPolicy?.processingTimeout
            Logger.shared.log(
                "File created: \(url.path), localIndex=\(localIndex), globalIndex=\(globalIndex), session=\(sessionID), requestMode=\(currentSession.mode.rawValue), translationTargetLanguage=\(currentSession.translationTargetLanguage), backendMode=\(currentSession.liveTranscriptionPolicy?.mode.rawValue ?? "unknown"), recordingDuration=\(String(format: "%.1f", recordingDuration))s, processingTimeout=\(Int(processingTimeout ?? 0))s",
                level: .info
            )
            self.pendingSegmentFiles[globalIndex] = url
            currentSession.batchTranscriptionManager.addSegment(url: url, index: localIndex)
            let screenshotContext: String?
            if currentSession.mode == .prompt {
                // OCR is retained for Whisper vocabulary hints in ordinary modes only.
                // Never forward screen context implicitly to the prompt post-processor.
                currentSession.clearScreenshotContext()
                screenshotContext = nil
            } else {
                screenshotContext = currentSession.consumeScreenshotContext()
            }
            var requestSettings = self.currentSettings
            if currentSession.mode == .faithful {
                requestSettings.autoPunctuation = false
                requestSettings.transcriptionQualityPreset = .high
            }
            self.multiProcessManager?.processFile(
                url: url,
                index: globalIndex,
                settings: requestSettings,
                sessionID: sessionID,
                screenshotContext: screenshotContext,
                mode: currentSession.mode,
                translationTargetLanguage: currentSession.translationTargetLanguage,
                processingTimeout: processingTimeout
            )
        }

        // Start workers before the recorder so the completed recording can be
        // submitted immediately; model preparation remains asynchronous.
        ensureRealtimeWorkersInitialized(
            reason: "recording worker startup",
            preloadModel: false
        )
        startAudioRecordingAsync(sessionID: sessionID)
        // Model/backend preparation remains asynchronous and must not gate the hotkey.
        scheduleBackendPreparation(
            reason: "recording start",
            preloadModel: true
        )
    }

    private func startAudioRecordingAsync(sessionID: Int) {
        guard let recorder = realtimeRecorder else {
            handleRecordingStartupFinished(
                sessionID: sessionID,
                didStart: false,
                failureReason: nil,
                inputDeviceName: nil
            )
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak recorder] in
            let didStart = recorder?.startRecording() == true
            let failureReason = recorder?.lastStartFailureReason
            let inputDeviceName = recorder?.currentInputDeviceName

            Task { @MainActor [weak self] in
                self?.handleRecordingStartupFinished(
                    sessionID: sessionID,
                    didStart: didStart,
                    failureReason: failureReason,
                    inputDeviceName: inputDeviceName
                )
            }
        }
    }

    private func handleRecordingStartupFinished(
        sessionID: Int,
        didStart: Bool,
        failureReason: RecordingStartFailureReason?,
        inputDeviceName: String?
    ) {
        guard startingRecordingSessionID == sessionID else {
            if didStart {
                realtimeRecorder?.stopRecording(discardPendingAudio: true)
            }
            return
        }

        startingRecordingSessionID = nil
        let deferredAction = deferredRecordingStartupAction
        deferredRecordingStartupAction = nil

        guard isRecording, activeRecordingSessionID == sessionID, sessionByID[sessionID] != nil else {
            if didStart {
                realtimeRecorder?.stopRecording(discardPendingAudio: true)
            }
            return
        }

        guard didStart else {
            handleRecordingStartupFailure(sessionID: sessionID, failureReason: failureReason)
            return
        }

        Logger.shared.log("Recording started (session \(sessionID))", level: .info)
        recordingIndicatorWindow?.updateRecordingInputDeviceName(inputDeviceName)

        switch deferredAction {
        case .stop:
            stopRecording()
        case .cancel:
            cancelRecording()
        case nil:
            recordingIndicatorWindow?.show()
        }
    }

    private func handleRecordingStartupFailure(
        sessionID: Int,
        failureReason: RecordingStartFailureReason?
    ) {
        Logger.shared.log("Failed to start recording", level: .error)
        if failureReason == .noInputDevice {
            Logger.shared.log("Recording aborted: microphone input device is unavailable", level: .warning)
            showTransientRecordingAttention("Microphone not detected")
        }
        realtimeRecorder?.onInputLevelChanged = nil
        realtimeRecorder?.onInputDeviceNameChanged = nil
        realtimeRecorder?.onMaximumDurationReached = nil
        realtimeRecorder?.maxRecordingDuration = nil
        recordingIndicatorWindow?.updateRecordingLevel(0)
        recordingIndicatorWindow?.updateRecordingInputDeviceName(nil)
        isRecording = false
        activeRecordingSessionID = nil
        pendingLiveRecordingProcessingMessage = nil
        destroySession(sessionID: sessionID)
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

    private func handleRecordingHotkeyPressed(_ mode: RecordingRequestMode) {
        pressedRecordingModes.insert(mode)
        startRecording(mode: mode)
    }

    private func handleRecordingHotkeyReleased(_ mode: RecordingRequestMode) {
        pressedRecordingModes.remove(mode)

        guard isRecording,
              let sessionID = activeRecordingSessionID,
              let session = sessionByID[sessionID],
              session.mode == mode else {
            return
        }

        stopRecording()
    }
    
    func stopRecording() {
        guard isRecording, let sessionID = activeRecordingSessionID, let session = sessionByID[sessionID] else {
            return
        }

        if startingRecordingSessionID == sessionID {
            deferredRecordingStartupAction = .stop
            Logger.shared.log(
                "Recording stop deferred until microphone startup completes (session \(sessionID))",
                level: .info
            )
            return
        }

        isRecording = false
        activeRecordingSessionID = nil
        if session.mode == .prompt {
            session.clearScreenshotContext()
        } else {
            session.setScreenshotContext(ScreenContextExtractor.captureScreenTextContext())
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sessionByID[sessionID]?.clearScreenshotContext()
        }
        Logger.shared.log(
            "Stopping audio recording for session \(sessionID)... requestMode=\(session.mode.rawValue), translationTargetLanguage=\(session.translationTargetLanguage)",
            level: .info
        )
        realtimeRecorder?.onInputLevelChanged = nil
        realtimeRecorder?.onInputDeviceNameChanged = nil
        realtimeRecorder?.onMaximumDurationReached = nil
        realtimeRecorder?.maxRecordingDuration = nil
        recordingIndicatorWindow?.updateRecordingLevel(0)
        recordingIndicatorWindow?.updateRecordingInputDeviceName(nil)
        let processingMessage = pendingLiveRecordingProcessingMessage
        pendingLiveRecordingProcessingMessage = nil
        recordingIndicatorWindow?.showProcessing(message: processingMessage)
        let finalizationTimeout = session.liveTranscriptionPolicy?.finalizationTimeout
            ?? currentSettings.recordingCompletionTimeout
        let recorder = realtimeRecorder
        guard let recorder else {
            completeRecordingStop(
                sessionID: sessionID,
                recorder: nil,
                timeoutInterval: finalizationTimeout,
                result: .notRecording
            )
            return
        }

        recorder.stopRecording { [weak self] result in
            Task { @MainActor [weak self] in
                self?.completeRecordingStop(
                    sessionID: sessionID,
                    recorder: recorder,
                    timeoutInterval: finalizationTimeout,
                    result: result
                )
            }
        }
    }

    private func completeRecordingStop(
        sessionID: Int,
        recorder: RealtimeRecorder?,
        timeoutInterval: TimeInterval,
        result: RecordingStopResult
    ) {
        guard sessionByID[sessionID] != nil else { return }

        switch result {
        case .stopped:
            Logger.shared.log(
                "Recording stopped (session \(sessionID)); waiting for transcription completion...",
                level: .info
            )
            enqueueSessionForFinalization(
                sessionID: sessionID,
                timeoutInterval: timeoutInterval
            )
            tryFinalizePendingSessionsIfNeeded()
        case .notRecording:
            Logger.shared.log(
                "Recording stop completed without an active recorder (session \(sessionID))",
                level: .warning
            )
            destroySession(sessionID: sessionID)
            if !isRecording {
                showTransientRecordingAttention("Audio input is not available")
            }
        case .timedOut:
            Logger.shared.log(
                "Recording stop timed out (session \(sessionID)); resetting the recorder",
                level: .error
            )
            destroySession(sessionID: sessionID)
            if let recorder, realtimeRecorder === recorder {
                realtimeRecorder = makeRealtimeRecorder()
            }
            if !isRecording {
                showTransientRecordingAttention("Audio input was reset. Please try again.")
            }
        }
    }

    private func handleLiveRecordingMaximumDurationReached(
        sessionID: Int,
        policy: LiveTranscriptionPolicy
    ) {
        guard isRecording, activeRecordingSessionID == sessionID else {
            return
        }
        pendingLiveRecordingProcessingMessage = policy.autoStopMessage
        Logger.shared.log(
            "Live recording auto-stop triggered for session \(sessionID): backendMode=\(policy.mode.rawValue), recordingMaxDuration=\(Int(policy.recordingMaxDuration))s",
            level: .info
        )
        stopRecording()
    }

    private func cancelRecording() {
        if isRecording,
           let sessionID = activeRecordingSessionID,
           startingRecordingSessionID == sessionID {
            deferredRecordingStartupAction = .cancel
            Logger.shared.log(
                "Recording cancel deferred until microphone startup completes (session \(sessionID))",
                level: .info
            )
            return
        }

        if isRecording, let sessionID = activeRecordingSessionID {
            Logger.shared.log("Canceling audio recording for session \(sessionID)...", level: .info)
            isRecording = false
            activeRecordingSessionID = nil
            realtimeRecorder?.stopRecording(discardPendingAudio: true)
            realtimeRecorder?.onInputLevelChanged = nil
            realtimeRecorder?.onInputDeviceNameChanged = nil
            realtimeRecorder?.onMaximumDurationReached = nil
            realtimeRecorder?.maxRecordingDuration = nil
            pendingLiveRecordingProcessingMessage = nil
            recordingIndicatorWindow?.updateRecordingLevel(0)
            recordingIndicatorWindow?.updateRecordingInputDeviceName(nil)
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

    private func createRecordingSession(
        mode: RecordingRequestMode,
        translationTargetLanguage: String,
        windowFocusTarget: WindowFocusTarget?
    ) -> RecordingSessionContext {
        let sessionID = nextRecordingSessionID
        nextRecordingSessionID += 1
        let session = RecordingSessionContext(
            id: sessionID,
            mode: mode,
            translationTargetLanguage: translationTargetLanguage,
            windowFocusTarget: windowFocusTarget
        )
        sessionByID[sessionID] = session
        return session
    }

    private func destroySession(sessionID: Int) {
        guard let session = sessionByID.removeValue(forKey: sessionID) else {
            return
        }
        multiProcessManager?.cancel(sessionID: sessionID)
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

        var finalOutput = output
        if let promptResult = PythonProcessManager.parsePromptResult(from: output) {
            session.rawTranscription = promptResult.rawTranscript
            session.promptUsedFallback = promptResult.usedFallback
            finalOutput = promptResult.promptMarkdown
            Logger.shared.log(
                "Prompt transformation received for session \(route.sessionID): rawLength=\(promptResult.rawTranscript.count), markdownLength=\(promptResult.promptMarkdown.count), fallback=\(promptResult.usedFallback)",
                level: promptResult.usedFallback ? .warning : .info
            )
        } else if session.mode == .prompt {
            session.rawTranscription = output
            session.promptUsedFallback = true
        }

        session.batchTranscriptionManager.completeSegment(index: route.localIndex, text: finalOutput)
        tryFinalizePendingSessionsIfNeeded()
    }

    private func enqueueSessionForFinalization(sessionID: Int, timeoutInterval: TimeInterval) {
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
        let normalizedTimeoutInterval = min(
            max(timeoutInterval, AppSettings.minimumRecordingCompletionTimeout),
            AppSettings.maximumRecordingCompletionTimeout
        )
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let session = self.sessionByID[sessionID] else { return }
            session.completionTimeoutWorkItem = nil
            self.finalizationQueue.markTimedOut(sessionID: sessionID)
            Logger.shared.log(
                "Transcription timeout reached for session \(sessionID) after \(Int(normalizedTimeoutInterval)) seconds. Finalizing with available text.",
                level: .warning
            )
            self.tryFinalizePendingSessionsIfNeeded()
        }
        session.completionTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + normalizedTimeoutInterval,
            execute: workItem
        )
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
        stopRealtimeWorkersIfNeededForOnDemand(reason: "realtime transcription finished")
    }

    private func finalizeSession(sessionID: Int) {
        guard let session = sessionByID.removeValue(forKey: sessionID) else {
            return
        }

        session.cancelCompletionTimeout()
        session.cancelFinalizationReadyWorkItem()

        let finalText = session.batchTranscriptionManager.finalize() ?? ""
        let rawText = session.rawTranscription ?? finalText
        let didInsertText: Bool
        if !finalText.isEmpty {
            Logger.shared.log(
                "Processing finalized live recording output (session \(sessionID), length=\(finalText.count))",
                level: .info
            )

            if session.mode == .prompt {
                TranscriptionHistoryManager.shared.addEntry(
                    text: finalText,
                    source: .liveRecording,
                    rawText: rawText
                )
                presentPromptReview(
                    rawText: rawText,
                    promptMarkdown: finalText,
                    usedFallback: session.promptUsedFallback,
                    windowFocusTarget: session.windowFocusTarget
                )
                didInsertText = true
            } else {
                if let windowFocusTarget = session.windowFocusTarget {
                    let restorationResult = WindowFocusRestorer.restoreIfNeeded(windowFocusTarget)
                    Logger.shared.log(
                        "Window focus restoration for session "
                            + String(sessionID)
                            + ": "
                            + restorationResult.logDescription,
                        level: restorationResult == .unavailable ? .warning : .debug
                    )
                }

                if let shortcut = VoiceShortcutManager.shared.resolve(input: finalText) {
                    Logger.shared.log(
                        "Voice shortcut matched for session \(sessionID) with action=\(shortcut.actionKind.rawValue) and inputLength=\(finalText.count)",
                        level: .info
                    )

                    if VoiceShortcutExecutor.execute(shortcut) {
                        Logger.shared.log(
                            "Voice shortcut executed successfully (session \(sessionID))",
                            level: .info
                        )
                        didInsertText = true
                    } else {
                        Logger.shared.log(
                            "Voice shortcut execution failed; falling back to text insertion (session \(sessionID))",
                            level: .warning
                        )
                        KeystrokeSimulator.typeText(finalText)
                        didInsertText = true
                    }
                } else {
                    KeystrokeSimulator.typeText(finalText)
                    Logger.shared.log("Text typing completed (session \(sessionID))", level: .info)
                    didInsertText = true
                }

                TranscriptionHistoryManager.shared.addEntry(
                    text: finalText,
                    source: .liveRecording
                )
            }
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

    private func presentPromptReview(
        rawText: String,
        promptMarkdown: String,
        usedFallback: Bool,
        windowFocusTarget: WindowFocusTarget?
    ) {
        guard let promptReviewWindow else {
            KeystrokeSimulator.copyText(promptMarkdown)
            showTransientRecordingAttention("Prompt copied; review window was unavailable")
            return
        }

        promptReviewWindow.present(
            rawTranscript: rawText,
            promptMarkdown: promptMarkdown,
            usedFallback: usedFallback
        ) { [weak self] action in
            guard let self else { return }
            switch action {
            case let .insert(text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                if let windowFocusTarget {
                    let restorationResult = WindowFocusRestorer.restoreIfNeeded(windowFocusTarget)
                    if restorationResult == .unavailable {
                        KeystrokeSimulator.copyText(text)
                        self.showTransientRecordingAttention("Target unavailable; prompt copied instead")
                    } else {
                        KeystrokeSimulator.typeText(text)
                    }
                } else {
                    KeystrokeSimulator.copyText(text)
                    self.showTransientRecordingAttention("No target field; prompt copied instead")
                }
            case let .copy(text):
                KeystrokeSimulator.copyText(text)
                if let windowFocusTarget {
                    _ = WindowFocusRestorer.restoreIfNeeded(windowFocusTarget)
                }
            case .cancel:
                Logger.shared.log("Prompt review canceled by user", level: .info)
                if let windowFocusTarget {
                    _ = WindowFocusRestorer.restoreIfNeeded(windowFocusTarget)
                }
            }
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
        pendingWorkerReconfigure = false
        pendingWorkerReconfigurePreloadModel = false
        currentSettings = SettingsManager.shared.load()
        if currentSettings.keepBackendReadyInBackground {
            reinitializeRealtimeWorkers(
                force: true,
                reason: "resume after imported audio",
                preloadModel: true
            )
        }
        applyPendingWorkerReconfigureIfPossible()
        stopRealtimeWorkersIfNeededForOnDemand(reason: "imported audio finished")
    }

    private func effectiveRealtimeWorkerCount(requested: Int) -> Int {
        var workerCount = Self.resolvedWorkerCount(requested: requested)
        if let adaptiveWorkerCap {
            workerCount = min(workerCount, max(1, adaptiveWorkerCap))
        }
        return max(1, workerCount)
    }

    private func reinitializeRealtimeWorkers(force: Bool, reason: String, preloadModel: Bool = false) {
        guard let multiProcessManager else { return }
        guard !serverScriptPath.isEmpty else { return }

        currentSettings = SettingsManager.shared.load()
        let requestedWorkerCount = preferredRealtimeWorkerCount()
        let bundleResolvedWorkerCount = Self.resolvedWorkerCount(requested: requestedWorkerCount)
        let effectiveWorkerCount = effectiveRealtimeWorkerCount(requested: requestedWorkerCount)
        let backendLimits = Self.backendServerLimits(requestedWorkers: effectiveWorkerCount)

        if !force && currentRealtimeWorkerCount == effectiveWorkerCount {
            return
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
            "MultiProcessManager initialized with \(effectiveWorkerCount) processes (\(reason)); backend=\(preferredRealtimeBackend().rawValue), backend limits activeServers=\(backendLimits.maxActiveServers), parallelModelLoads=\(backendLimits.maxParallelModelLoads)",
            level: .info
        )
        if preloadModel || !isRecording {
            scheduleBackendPreparation(reason: reason, preloadModel: preloadModel)
        }
    }

    private func scheduleBackendPreparation(
        reason: String,
        preloadModel: Bool,
        retryCount: Int = 0
    ) {
        guard let multiProcessManager else { return }
        guard !serverScriptPath.isEmpty else { return }

        if isImportingAudio || didSuspendRealtimeWorkersForImport {
            guard retryCount < maxBackendPreparationRetries else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + backendPreparationRetryDelay) { [weak self] in
                self?.scheduleBackendPreparation(
                    reason: reason,
                    preloadModel: preloadModel,
                    retryCount: retryCount + 1
                )
            }
            return
        }

        currentSettings = SettingsManager.shared.load()
        let sent = multiProcessManager.requestBackendProbe(
            gpuAccelerationEnabled: currentSettings.gpuAccelerationEnabled,
            preloadModel: preloadModel
        )
        if sent {
            Logger.shared.log(
                "Scheduled backend preparation succeeded (\(reason), preloadModel=\(preloadModel))",
                level: .info
            )
            return
        }

        guard retryCount < maxBackendPreparationRetries else {
            Logger.shared.log(
                "Backend preparation could not acquire an idle worker after \(maxBackendPreparationRetries) retries (\(reason))",
                level: .warning
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + backendPreparationRetryDelay) { [weak self] in
            self?.scheduleBackendPreparation(
                reason: reason,
                preloadModel: preloadModel,
                retryCount: retryCount + 1
            )
        }
    }

    private func preferredRealtimeBackend() -> EffectiveTranscriptionBackend {
        TranscriptionRuntimeSupport.preferredBackend(
            settings: currentSettings,
            latestStatus: TranscriptionBackendStatusStore.shared.currentStatus
        )
    }

    private func preferredRealtimeWorkerCount() -> Int {
        preferredRealtimeBackend().defaultWorkerCount
    }

    private func handleBackendStatusChanged(_ status: TranscriptionBackendStatus) {
        Logger.shared.log(
            "AppDelegate: backend status changed - backend=\(status.effectiveBackend.rawValue), gpuRequested=\(status.gpuRequested), gpuAvailable=\(status.gpuAvailable), fallbackReason=\(status.fallbackReason ?? "none")",
            level: .info
        )

        let preferredWorkerCount = status.effectiveBackend.defaultWorkerCount
        if currentRealtimeWorkerCount != preferredWorkerCount {
            pendingWorkerReconfigure = true
            pendingWorkerReconfigurePreloadModel = false
            applyPendingWorkerReconfigureIfPossible()
        }

    }

    private func setupMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: Self.makeMainActorDispatchHandler(capture: { source.data.rawValue }) { [weak self] rawValue in
            guard let self else { return }
            self.handleMemoryPressureEvent(.init(rawValue: rawValue))
        })
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.normal) && !event.contains(.warning) && !event.contains(.critical) {
            guard adaptiveWorkerCap != nil else {
                return
            }
            adaptiveWorkerCap = nil
            pendingWorkerReconfigure = true
            Logger.shared.log(
                "Memory pressure returned to normal; scheduling worker cap reset",
                level: .info
            )
            applyPendingWorkerReconfigureIfPossible()
            return
        }

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
        pendingWorkerReconfigurePreloadModel = false
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

        let preloadModel = pendingWorkerReconfigurePreloadModel
        pendingWorkerReconfigure = false
        pendingWorkerReconfigurePreloadModel = false
        if currentSettings.keepBackendReadyInBackground {
            reinitializeRealtimeWorkers(
                force: true,
                reason: "adaptive reconfiguration",
                preloadModel: preloadModel
            )
            return
        }

        stopRealtimeWorkers(reason: "on-demand setting change")
    }

    private func ensureMultiProcessManagerCreatedIfNeeded() {
        guard multiProcessManager == nil else {
            return
        }
        multiProcessManager = MultiProcessManager()
        Logger.shared.log("MultiProcessManager created", level: .debug)
        ensureMultiProcessManagerCallbacks()
    }

    private func ensureMultiProcessManagerCallbacks() {
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
    }

    private func ensureRealtimeWorkersInitialized(reason: String, preloadModel: Bool) {
        ensureMultiProcessManagerCreatedIfNeeded()
        guard !serverScriptPath.isEmpty else { return }

        currentSettings = SettingsManager.shared.load()
        let expectedWorkerCount = effectiveRealtimeWorkerCount(
            requested: preferredRealtimeWorkerCount()
        )
        let activeProcessCount = multiProcessManager?.getProcessCount() ?? 0
        if currentRealtimeWorkerCount == expectedWorkerCount && activeProcessCount == expectedWorkerCount {
            if preloadModel && TranscriptionBackendStatusStore.shared.currentStatus == nil {
                scheduleBackendPreparation(reason: reason, preloadModel: true)
            }
            return
        }

        reinitializeRealtimeWorkers(
            force: true,
            reason: reason,
            preloadModel: preloadModel
        )
    }

    private func handleSettingsDidChange() {
        let previousSettings = currentSettings
        currentSettings = SettingsManager.shared.load()
        Logger.shared.log(
            "AppDelegate: Reloaded settings - language=\(currentSettings.language), preset=\(currentSettings.transcriptionQualityPreset.rawValue), gpu=\(currentSettings.gpuAccelerationEnabled), keepBackendReady=\(currentSettings.keepBackendReadyInBackground)"
        )

        let keepBackendReadyChanged =
            currentSettings.keepBackendReadyInBackground != previousSettings.keepBackendReadyInBackground
        let gpuAccelerationChanged =
            currentSettings.gpuAccelerationEnabled != previousSettings.gpuAccelerationEnabled

        guard keepBackendReadyChanged || gpuAccelerationChanged else {
            return
        }

        pendingWorkerReconfigure = true
        pendingWorkerReconfigurePreloadModel = currentSettings.keepBackendReadyInBackground
        applyPendingWorkerReconfigureIfPossible()
    }

    private func stopRealtimeWorkers(reason: String) {
        guard let multiProcessManager else {
            currentRealtimeWorkerCount = 0
            return
        }
        guard multiProcessManager.getProcessCount() > 0 else {
            currentRealtimeWorkerCount = 0
            return
        }

        Logger.shared.log("Stopping realtime transcription workers (\(reason))", level: .info)
        multiProcessManager.stop()
        currentRealtimeWorkerCount = 0
    }

    private func stopRealtimeWorkersIfNeededForOnDemand(reason: String) {
        currentSettings = SettingsManager.shared.load()
        guard !currentSettings.keepBackendReadyInBackground else {
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

        stopRealtimeWorkers(reason: reason)
    }

    private func startTemporaryBatchCleanupTimer() {
        stopTemporaryBatchCleanupTimer()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + temporaryBatchCleanupInterval,
            repeating: temporaryBatchCleanupInterval
        )
        timer.setEventHandler(handler: Self.makeMainActorDispatchHandler { [weak self] in
            self?.cleanupStaleTemporaryBatchFiles()
        })
        timer.resume()
        temporaryBatchCleanupTimer = timer
    }

    private func stopTemporaryBatchCleanupTimer() {
        temporaryBatchCleanupTimer?.cancel()
        temporaryBatchCleanupTimer = nil
    }

    private func cleanupStaleTemporaryBatchFiles() {
        let fileManager = FileManager.default
        let directoryURL = KotoTypeStoragePaths.temporaryBatchDirectory(fileManager: fileManager)

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
        let sessionIDs = Array(sessionByID.keys)
        for session in sessionByID.values {
            session.cancelFinalizationReadyWorkItem()
            session.cancelCompletionTimeout()
        }
        for sessionID in sessionIDs {
            multiProcessManager?.cancel(sessionID: sessionID, recoverRunningWorker: false)
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
