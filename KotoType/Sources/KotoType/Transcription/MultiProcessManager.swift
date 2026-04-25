import Foundation

final class MultiProcessManager: @unchecked Sendable {
    private var processes: [Int: any PythonProcessManaging] = [:]
    private var idleProcesses: Set<Int> = []
    private var segmentContextByProcess: [Int: SegmentContext] = [:]
    private var healthCheckContextByProcess: [Int: HealthCheckContext] = [:]
    private var lastHealthCheckAtByProcess: [Int: Date] = [:]
    private var processStartedAtByIndex: [Int: Date] = [:]
    private var recoveryInProgress: Set<Int> = []
    private var scheduledRecoveries: Set<Int> = []
    private var idleTerminationHistory: [Int: [Date]] = [:]
    private var startFailureHistory: [Int: [Date]] = [:]
    private var recoverySuppressedUntil: [Int: Date] = [:]
    private var watchdogTimer: DispatchSourceTimer?
    private var healthCheckSequence: UInt64 = 0
    private var processLock = NSLock()
    private var scriptPath: String = ""
    private let maxRetryCount = 2
    private let maxIdleTerminationsPerWindow = 3
    private let idleTerminationWindowSeconds: TimeInterval = 30
    private let idleRecoveryCooldownSeconds: TimeInterval = 60
    private let idleRecoveryBaseDelaySeconds: TimeInterval = 0.5
    private let fatalIdleTerminationCooldownSeconds: TimeInterval = 300
    private let maxStartFailuresPerWindow = 4
    private let startFailureWindowSeconds: TimeInterval = 30
    private let startFailureCooldownSeconds: TimeInterval = 300
    private let startFailureBaseDelaySeconds: TimeInterval = 0.5
    private let maxNoIdleQueueAttempts = 200
    private let segmentProcessingTimeoutSeconds: TimeInterval
    private let watchdogIntervalSeconds: TimeInterval
    private let healthCheckIntervalSeconds: TimeInterval
    private let healthCheckTimeoutSeconds: TimeInterval
    private let healthCheckStartupGraceSeconds: TimeInterval
    private let processManagerFactory: () -> any PythonProcessManaging
    private var isStopping = false

    private static let healthCheckRequestPrefix = "__KOTOTYPE_HEALTHCHECK__:"
    private static let healthCheckResponsePrefix = "__KOTOTYPE_HEALTHCHECK_OK__:"
    
    var outputReceived: ((Int, String) -> Void)?
    var segmentComplete: ((Int, String) -> Void)?

    static func shouldAutoRecoverIdleTermination(status: Int32) -> Bool {
        // Exit status 0 while idle usually means stdin was closed (EOF) and the server
        // shut down cleanly. Immediate recovery can create an endless restart loop.
        if status == 0 {
            return false
        }
        // SIGKILL indicates external termination (often memory pressure).
        // Auto-restarting immediately can amplify the pressure and create a restart storm.
        return status != 9
    }

    init(
        processManagerFactory: @escaping () -> any PythonProcessManaging = { PythonProcessManager() },
        segmentProcessingTimeoutSeconds: TimeInterval = 60.0,
        watchdogIntervalSeconds: TimeInterval = 2.0,
        healthCheckIntervalSeconds: TimeInterval = 30.0,
        healthCheckTimeoutSeconds: TimeInterval = 8.0,
        healthCheckStartupGraceSeconds: TimeInterval = 12.0
    ) {
        self.processManagerFactory = processManagerFactory
        self.segmentProcessingTimeoutSeconds = max(0.1, segmentProcessingTimeoutSeconds)
        self.watchdogIntervalSeconds = max(0.1, watchdogIntervalSeconds)
        self.healthCheckIntervalSeconds = max(0.1, healthCheckIntervalSeconds)
        self.healthCheckTimeoutSeconds = max(0.1, healthCheckTimeoutSeconds)
        self.healthCheckStartupGraceSeconds = max(0.1, healthCheckStartupGraceSeconds)
    }
    
    func initialize(count: Int, scriptPath: String) {
        Logger.shared.log("MultiProcessManager: initialize called - count=\(count), scriptPath=\(scriptPath)", level: .info)
        stopWatchdog()

        var oldProcesses: [Int: any PythonProcessManaging] = [:]
        processLock.lock()
        oldProcesses = processes
        self.scriptPath = scriptPath
        self.isStopping = false
        self.processes.removeAll()
        self.idleProcesses.removeAll()
        self.segmentContextByProcess.removeAll()
        self.healthCheckContextByProcess.removeAll()
        self.lastHealthCheckAtByProcess.removeAll()
        self.processStartedAtByIndex.removeAll()
        self.healthCheckSequence = 0
        self.recoveryInProgress.removeAll()
        self.scheduledRecoveries.removeAll()
        self.idleTerminationHistory.removeAll()
        self.startFailureHistory.removeAll()
        self.recoverySuppressedUntil.removeAll()
        processLock.unlock()

        for (_, manager) in oldProcesses {
            manager.outputReceived = nil
            manager.processTerminated = nil
            manager.stop()
        }

        for i in 0..<count {
            createProcess(processIndex: i)
        }

        processLock.lock()
        let initializedCount = processes.count
        processLock.unlock()
        Logger.shared.log("MultiProcessManager: initialized with \(initializedCount) processes", level: .info)
        startWatchdog()
    }
    
    func processFile(url: URL, index: Int, settings: AppSettings, screenshotContext: String? = nil, retryCount: Int = 0, queueAttempt: Int = 0) {
        Logger.shared.log("MultiProcessManager: processFile called - url=\(url.path), index=\(index)", level: .info)
        processLock.lock()
        if isStopping {
            processLock.unlock()
            Logger.shared.log("MultiProcessManager: ignoring processFile because manager is stopping", level: .warning)
            return
        }
        let availableProcess = idleProcesses.first
        let processCount = processes.count
        processLock.unlock()
        
        guard let processIndex = availableProcess else {
            if processCount == 0 && queueAttempt >= maxNoIdleQueueAttempts {
                Logger.shared.log(
                    "MultiProcessManager: no workers available for segment \(index) after \(queueAttempt) attempts; completing with empty result",
                    level: .error
                )
                DispatchQueue.main.async { [weak self] in
                    self?.segmentComplete?(index, "")
                }
                return
            }

            Logger.shared.log("MultiProcessManager: no idle process available, queuing file: \(url.path)", level: .warning)
            if screenshotContext != nil {
                Logger.shared.log(
                    "MultiProcessManager: dropping queued screenshot context for segment \(index) to avoid retaining OCR text in memory",
                    level: .warning
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.processFile(
                    url: url,
                    index: index,
                    settings: settings,
                    screenshotContext: nil,
                    retryCount: retryCount,
                    queueAttempt: queueAttempt + 1
                )
            }
            return
        }
        
        Logger.shared.log("MultiProcessManager: assigning file to process \(processIndex)", level: .debug)
        assignProcess(
            processIndex: processIndex,
            context: SegmentContext(
                url: url,
                index: index,
                settings: settings,
                retryCount: retryCount
            ),
            screenshotContext: screenshotContext
        )
    }
    
    private func assignProcess(processIndex: Int, context: SegmentContext, screenshotContext: String?) {
        var assignedContext = context
        assignedContext.assignedAt = Date()

        processLock.lock()
        idleProcesses.remove(processIndex)
        healthCheckContextByProcess.removeValue(forKey: processIndex)
        segmentContextByProcess[processIndex] = assignedContext
        processLock.unlock()
        
        guard let manager = processes[processIndex] else {
            Logger.shared.log("MultiProcessManager: process \(processIndex) not found", level: .error)
            handleProcessFailure(processIndex: processIndex, context: assignedContext, reason: "manager_not_found")
            return
        }
        
        guard manager.isRunning() else {
            Logger.shared.log("MultiProcessManager: process \(processIndex) is not running", level: .error)
            handleProcessFailure(processIndex: processIndex, context: assignedContext, reason: "process_not_running")
            return
        }
        
        Logger.shared.log(
            "MultiProcessManager: process \(processIndex) processing file \(assignedContext.index): \(assignedContext.url.path) (retry=\(assignedContext.retryCount))",
            level: .info
        )
        
        let sendSucceeded = manager.sendInput(
            assignedContext.url.path,
            language: assignedContext.settings.language,
            autoPunctuation: assignedContext.settings.autoPunctuation,
            qualityPreset: assignedContext.settings.transcriptionQualityPreset,
            gpuAccelerationEnabled: assignedContext.settings.gpuAccelerationEnabled,
            screenshotContext: screenshotContext
        )

        if !sendSucceeded {
            handleProcessFailure(processIndex: processIndex, context: assignedContext, reason: "send_input_failed")
        }
    }
    
    private func handleOutput(processIndex: Int, output: String) {
        Logger.shared.log(
            "MultiProcessManager: handleOutput called - processIndex=\(processIndex), outputLength=\(output.count)",
            level: .info
        )
        let now = Date()
        
        processLock.lock()
        if let healthCheckContext = healthCheckContextByProcess.removeValue(forKey: processIndex) {
            idleProcesses.insert(processIndex)
            let expectedResponse = Self.healthCheckResponsePrefix + healthCheckContext.token
            if output == expectedResponse {
                idleTerminationHistory.removeValue(forKey: processIndex)
                recoverySuppressedUntil.removeValue(forKey: processIndex)
                lastHealthCheckAtByProcess[processIndex] = now
                processLock.unlock()
                Logger.shared.log("MultiProcessManager: health check passed for process \(processIndex)", level: .debug)
                return
            }
            processLock.unlock()
            Logger.shared.log(
                "MultiProcessManager: invalid health check response from process \(processIndex) (length=\(output.count))",
                level: .warning
            )
            recoverProcess(processIndex: processIndex)
            return
        }

        if let status = PythonProcessManager.parseBackendStatus(from: output) {
            lastHealthCheckAtByProcess[processIndex] = now
            processLock.unlock()
            TranscriptionBackendStatusStore.publishFromAnyThread(status)
            Logger.shared.log(
                "MultiProcessManager: backend status received from process \(processIndex): backend=\(status.effectiveBackend.rawValue), gpuRequested=\(status.gpuRequested), gpuAvailable=\(status.gpuAvailable), fallbackReason=\(status.fallbackReason ?? "none")",
                level: .debug
            )
            return
        }

        guard let context = segmentContextByProcess[processIndex] else {
            processLock.unlock()
            Logger.shared.log(
                "MultiProcessManager: stale output without in-flight segment from process \(processIndex); ignoring",
                level: .warning
            )
            return
        }
        segmentContextByProcess.removeValue(forKey: processIndex)
        idleProcesses.insert(processIndex)
        idleTerminationHistory.removeValue(forKey: processIndex)
        recoverySuppressedUntil.removeValue(forKey: processIndex)
        lastHealthCheckAtByProcess[processIndex] = now
        processLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.outputReceived?(processIndex, output)
            self?.segmentComplete?(context.index, output)
        }
    }

    private func handleProcessTermination(processIndex: Int, status: Int32) {
        processLock.lock()
        let shouldHandle = !isStopping && processes[processIndex] != nil
        let context = segmentContextByProcess[processIndex]
        healthCheckContextByProcess.removeValue(forKey: processIndex)
        processStartedAtByIndex.removeValue(forKey: processIndex)
        lastHealthCheckAtByProcess.removeValue(forKey: processIndex)
        if context == nil {
            idleProcesses.remove(processIndex)
        }
        processLock.unlock()

        guard shouldHandle else {
            return
        }

        if !Self.shouldAutoRecoverIdleTermination(status: status) {
            handleFatalTermination(processIndex: processIndex, status: status, context: context)
            return
        }

        if let context {
            handleProcessFailure(
                processIndex: processIndex,
                context: context,
                reason: "process_terminated_status_\(status)"
            )
        } else {
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) terminated while idle, recovering",
                level: .warning
            )
            handleIdleProcessTermination(processIndex: processIndex, status: status)
        }
    }

    private func handleProcessFailure(processIndex: Int, context: SegmentContext, reason: String) {
        Logger.shared.log(
            "MultiProcessManager: process failure on \(processIndex), segment=\(context.index), reason=\(reason)",
            level: .error
        )

        processLock.lock()
        segmentContextByProcess.removeValue(forKey: processIndex)
        healthCheckContextByProcess.removeValue(forKey: processIndex)
        processStartedAtByIndex.removeValue(forKey: processIndex)
        lastHealthCheckAtByProcess.removeValue(forKey: processIndex)
        processLock.unlock()

        recoverProcess(processIndex: processIndex)
        retryOrCompleteWithEmpty(context: context)
    }

    private func handleFatalTermination(processIndex: Int, status: Int32, context: SegmentContext?) {
        let now = Date()
        var oldManager: (any PythonProcessManaging)?
        processLock.lock()
        oldManager = processes[processIndex]
        processes.removeValue(forKey: processIndex)
        idleProcesses.remove(processIndex)
        segmentContextByProcess.removeValue(forKey: processIndex)
        healthCheckContextByProcess.removeValue(forKey: processIndex)
        processStartedAtByIndex.removeValue(forKey: processIndex)
        lastHealthCheckAtByProcess.removeValue(forKey: processIndex)
        recoverySuppressedUntil[processIndex] = now.addingTimeInterval(fatalIdleTerminationCooldownSeconds)
        processLock.unlock()

        oldManager?.outputReceived = nil
        oldManager?.processTerminated = nil
        oldManager?.stop()

        if let context {
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) terminated with status \(status) while processing segment \(context.index); completing with empty result and delaying recovery for \(Int(fatalIdleTerminationCooldownSeconds))s",
                level: .error
            )
            DispatchQueue.main.async { [weak self] in
                self?.segmentComplete?(context.index, "")
            }
        } else {
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) terminated with status \(status) while idle; delaying recovery for \(Int(fatalIdleTerminationCooldownSeconds))s",
                level: .error
            )
        }

        scheduleRecovery(processIndex: processIndex, delay: fatalIdleTerminationCooldownSeconds)
    }

    private func retryOrCompleteWithEmpty(context: SegmentContext) {
        guard context.retryCount < maxRetryCount else {
            Logger.shared.log(
                "MultiProcessManager: max retry reached for segment \(context.index), completing with empty result",
                level: .error
            )
            DispatchQueue.main.async { [weak self] in
                self?.segmentComplete?(context.index, "")
            }
            return
        }

        let nextRetry = context.retryCount + 1
        Logger.shared.log(
            "MultiProcessManager: retrying segment \(context.index) (attempt \(nextRetry)/\(maxRetryCount))",
            level: .warning
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.processFile(
                url: context.url,
                index: context.index,
                settings: context.settings,
                screenshotContext: nil,
                retryCount: nextRetry,
                queueAttempt: 0
            )
        }
    }

    private func createProcess(processIndex: Int) {
        let now = Date()
        processLock.lock()
        if isStopping {
            processLock.unlock()
            return
        }
        let blockedUntil = recoverySuppressedUntil[processIndex]
        let currentScriptPath = scriptPath
        processLock.unlock()

        if let blockedUntil, blockedUntil > now {
            let remaining = blockedUntil.timeIntervalSince(now)
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) start suppressed for \(String(format: "%.1f", remaining))s",
                level: .error
            )
            scheduleRecovery(processIndex: processIndex, delay: remaining)
            return
        }

        let manager = processManagerFactory()
        manager.outputReceived = { [weak self] output in
            self?.handleOutput(processIndex: processIndex, output: output)
        }
        manager.processTerminated = { [weak self] status in
            self?.handleProcessTermination(processIndex: processIndex, status: status)
        }
        processLock.lock()
        if isStopping {
            processLock.unlock()
            manager.outputReceived = nil
            manager.processTerminated = nil
            manager.stop()
            return
        }
        processes[processIndex] = manager
        processLock.unlock()

        manager.startPython(scriptPath: currentScriptPath)

        processLock.lock()
        if isStopping {
            processes.removeValue(forKey: processIndex)
            idleProcesses.remove(processIndex)
            segmentContextByProcess.removeValue(forKey: processIndex)
            healthCheckContextByProcess.removeValue(forKey: processIndex)
            processStartedAtByIndex.removeValue(forKey: processIndex)
            lastHealthCheckAtByProcess.removeValue(forKey: processIndex)
            processLock.unlock()
            manager.outputReceived = nil
            manager.processTerminated = nil
            manager.stop()
            return
        }

        // Process termination can race with startup; if the termination handler already
        // removed this process entry, skip startup-failure recovery here.
        guard processes[processIndex] != nil else {
            processLock.unlock()
            return
        }

        if manager.isRunning() {
            idleProcesses.insert(processIndex)
            startFailureHistory.removeValue(forKey: processIndex)
            recoverySuppressedUntil.removeValue(forKey: processIndex)
            processStartedAtByIndex[processIndex] = now
            lastHealthCheckAtByProcess[processIndex] = now
            processLock.unlock()
            Logger.shared.log("MultiProcessManager: process \(processIndex) initialized", level: .debug)
            return
        }

        processes.removeValue(forKey: processIndex)
        idleProcesses.remove(processIndex)
        segmentContextByProcess.removeValue(forKey: processIndex)
        healthCheckContextByProcess.removeValue(forKey: processIndex)
        processStartedAtByIndex.removeValue(forKey: processIndex)
        lastHealthCheckAtByProcess.removeValue(forKey: processIndex)
        processLock.unlock()
        handleProcessStartFailure(processIndex: processIndex, now: now)
    }

    private func handleProcessStartFailure(processIndex: Int, now: Date) {
        processLock.lock()
        var history = startFailureHistory[processIndex] ?? []
        history.removeAll { now.timeIntervalSince($0) > startFailureWindowSeconds }
        history.append(now)
        startFailureHistory[processIndex] = history

        let failureCount = history.count
        if failureCount > maxStartFailuresPerWindow {
            let blockedUntil = now.addingTimeInterval(startFailureCooldownSeconds)
            recoverySuppressedUntil[processIndex] = blockedUntil
            processLock.unlock()
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) failed to start \(failureCount) times in \(Int(startFailureWindowSeconds))s; opening circuit breaker for \(Int(startFailureCooldownSeconds))s",
                level: .error
            )
            scheduleRecovery(processIndex: processIndex, delay: startFailureCooldownSeconds)
            return
        }

        let exponent = max(0, failureCount - 1)
        let delay = min(startFailureBaseDelaySeconds * pow(2.0, Double(exponent)), 5.0)
        processLock.unlock()
        Logger.shared.log(
            "MultiProcessManager: process \(processIndex) failed to start; scheduling recovery in \(String(format: "%.1f", delay))s (failures=\(failureCount)/\(maxStartFailuresPerWindow))",
            level: .error
        )
        scheduleRecovery(processIndex: processIndex, delay: delay)
    }

    private func recoverProcess(processIndex: Int) {
        var oldManager: (any PythonProcessManaging)?
        processLock.lock()
        if isStopping {
            processLock.unlock()
            return
        }
        if recoveryInProgress.contains(processIndex) {
            processLock.unlock()
            return
        }
        recoveryInProgress.insert(processIndex)

        oldManager = processes.removeValue(forKey: processIndex)
        idleProcesses.remove(processIndex)
        segmentContextByProcess.removeValue(forKey: processIndex)
        healthCheckContextByProcess.removeValue(forKey: processIndex)
        processStartedAtByIndex.removeValue(forKey: processIndex)
        lastHealthCheckAtByProcess.removeValue(forKey: processIndex)
        processLock.unlock()

        oldManager?.outputReceived = nil
        oldManager?.processTerminated = nil
        oldManager?.stop()

        var shouldCreate = false
        processLock.lock()
        if !isStopping {
            shouldCreate = true
        }
        processLock.unlock()

        if shouldCreate {
            createProcess(processIndex: processIndex)
        }

        processLock.lock()
        recoveryInProgress.remove(processIndex)
        processLock.unlock()
    }

    private func handleIdleProcessTermination(processIndex: Int, status: Int32) {
        let now = Date()
        var historyCount = 0
        var shouldCooldown = false
        var isBlocked = false
        var delay = idleRecoveryBaseDelaySeconds
        var shouldAutoRecover = true

        processLock.lock()
        var history = idleTerminationHistory[processIndex] ?? []
        history.removeAll { now.timeIntervalSince($0) > idleTerminationWindowSeconds }
        history.append(now)
        idleTerminationHistory[processIndex] = history
        historyCount = history.count

        if !Self.shouldAutoRecoverIdleTermination(status: status) {
            shouldAutoRecover = false
            recoverySuppressedUntil[processIndex] = now.addingTimeInterval(fatalIdleTerminationCooldownSeconds)
        } else if let blockedUntil = recoverySuppressedUntil[processIndex], blockedUntil > now {
            isBlocked = true
        } else if historyCount > maxIdleTerminationsPerWindow {
            shouldCooldown = true
            let blockedUntil = now.addingTimeInterval(idleRecoveryCooldownSeconds)
            recoverySuppressedUntil[processIndex] = blockedUntil
        } else {
            let exponent = max(0, historyCount - 1)
            delay = min(idleRecoveryBaseDelaySeconds * pow(2.0, Double(exponent)), 5.0)
        }
        processLock.unlock()

        if !shouldAutoRecover {
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) terminated with status \(status); auto-recovery disabled for \(Int(fatalIdleTerminationCooldownSeconds))s to prevent restart storm",
                level: .error
            )
            return
        }
        if isBlocked {
            Logger.shared.log(
                "MultiProcessManager: recovery suppressed for process \(processIndex); status=\(status)",
                level: .error
            )
            return
        }

        if shouldCooldown {
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) crashed \(historyCount) times in \(Int(idleTerminationWindowSeconds))s; cooling down for \(Int(idleRecoveryCooldownSeconds))s",
                level: .error
            )
            scheduleRecovery(processIndex: processIndex, delay: idleRecoveryCooldownSeconds)
            return
        }

        Logger.shared.log(
            "MultiProcessManager: scheduling recovery for process \(processIndex) in \(String(format: "%.1f", delay))s after idle termination status \(status)",
            level: .warning
        )
        scheduleRecovery(processIndex: processIndex, delay: delay)
    }

    private func scheduleRecovery(processIndex: Int, delay: TimeInterval) {
        processLock.lock()
        if isStopping || scheduledRecoveries.contains(processIndex) {
            processLock.unlock()
            return
        }
        scheduledRecoveries.insert(processIndex)
        processLock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            let now = Date()
            self.processLock.lock()
            self.scheduledRecoveries.remove(processIndex)
            let blockedUntil = self.recoverySuppressedUntil[processIndex] ?? .distantPast
            let blocked = blockedUntil > now
            self.processLock.unlock()

            if blocked {
                let remaining = blockedUntil.timeIntervalSince(now)
                if remaining > 0.1 {
                    self.scheduleRecovery(processIndex: processIndex, delay: remaining)
                }
                return
            }
            self.recoverProcess(processIndex: processIndex)
        }
    }

    private func startWatchdog() {
        processLock.lock()
        if watchdogTimer != nil {
            processLock.unlock()
            return
        }
        processLock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + watchdogIntervalSeconds, repeating: watchdogIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.runWatchdog()
        }
        timer.resume()

        processLock.lock()
        watchdogTimer = timer
        processLock.unlock()
    }

    private func stopWatchdog() {
        processLock.lock()
        let timer = watchdogTimer
        watchdogTimer = nil
        processLock.unlock()
        timer?.cancel()
    }

    private func runWatchdog() {
        let now = Date()
        var timedOutSegments: [(Int, SegmentContext)] = []
        var timedOutHealthChecks: [(Int, String)] = []
        var stoppedProcessesWithoutContext: [Int] = []
        var healthChecksToSend: [(Int, String)] = []

        processLock.lock()
        guard !isStopping else {
            processLock.unlock()
            return
        }

        for processIndex in Array(segmentContextByProcess.keys) {
            guard let context = segmentContextByProcess[processIndex] else { continue }
            if now.timeIntervalSince(context.assignedAt) >= segmentProcessingTimeoutSeconds {
                segmentContextByProcess.removeValue(forKey: processIndex)
                idleProcesses.remove(processIndex)
                timedOutSegments.append((processIndex, context))
            }
        }

        for processIndex in Array(healthCheckContextByProcess.keys) {
            guard let healthContext = healthCheckContextByProcess[processIndex] else { continue }
            if now.timeIntervalSince(healthContext.sentAt) >= healthCheckTimeoutSeconds {
                healthCheckContextByProcess.removeValue(forKey: processIndex)
                idleProcesses.remove(processIndex)
                timedOutHealthChecks.append((processIndex, healthContext.token))
            }
        }

        for (processIndex, manager) in processes {
            if segmentContextByProcess[processIndex] != nil || healthCheckContextByProcess[processIndex] != nil {
                continue
            }

            guard manager.isRunning() else {
                idleProcesses.remove(processIndex)
                stoppedProcessesWithoutContext.append(processIndex)
                continue
            }

            guard idleProcesses.contains(processIndex) else {
                continue
            }

            guard let startedAt = processStartedAtByIndex[processIndex] else {
                continue
            }
            guard now.timeIntervalSince(startedAt) >= healthCheckStartupGraceSeconds else {
                continue
            }

            let lastHealthCheckAt = lastHealthCheckAtByProcess[processIndex] ?? startedAt
            guard now.timeIntervalSince(lastHealthCheckAt) >= healthCheckIntervalSeconds else {
                continue
            }

            healthCheckSequence += 1
            let token = "\(processIndex)-\(healthCheckSequence)"
            healthCheckContextByProcess[processIndex] = HealthCheckContext(token: token, sentAt: now)
            idleProcesses.remove(processIndex)
            healthChecksToSend.append((processIndex, token))
        }
        processLock.unlock()

        for (processIndex, context) in timedOutSegments {
            Logger.shared.log(
                "MultiProcessManager: segment timeout on process \(processIndex), segment=\(context.index), age=\(String(format: "%.1f", now.timeIntervalSince(context.assignedAt)))s",
                level: .error
            )
            handleProcessFailure(
                processIndex: processIndex,
                context: context,
                reason: "segment_timeout"
            )
        }

        for (processIndex, token) in timedOutHealthChecks {
            Logger.shared.log(
                "MultiProcessManager: health check timeout on process \(processIndex), token=\(token)",
                level: .warning
            )
            recoverProcess(processIndex: processIndex)
        }

        for processIndex in stoppedProcessesWithoutContext {
            Logger.shared.log(
                "MultiProcessManager: process \(processIndex) is not running during watchdog probe; recovering",
                level: .warning
            )
            recoverProcess(processIndex: processIndex)
        }

        for (processIndex, token) in healthChecksToSend {
            let succeeded = sendHealthCheck(processIndex: processIndex, token: token)
            if succeeded {
                continue
            }

            processLock.lock()
            healthCheckContextByProcess.removeValue(forKey: processIndex)
            processLock.unlock()

            Logger.shared.log(
                "MultiProcessManager: failed to send health check to process \(processIndex), recovering",
                level: .warning
            )
            recoverProcess(processIndex: processIndex)
        }
    }

    private func sendHealthCheck(processIndex: Int, token: String) -> Bool {
        processLock.lock()
        let manager = processes[processIndex]
        processLock.unlock()

        guard let manager else {
            return false
        }

        let request = Self.healthCheckRequestPrefix + token
        return manager.sendInput(
            request,
            language: "auto",
            autoPunctuation: false,
            qualityPreset: .medium,
            gpuAccelerationEnabled: false,
            screenshotContext: nil
        )
    }
    
    func stop() {
        Logger.shared.log("MultiProcessManager: stop called", level: .info)
        stopWatchdog()

        processLock.lock()
        isStopping = true
        let allProcesses = processes
        processes.removeAll()
        idleProcesses.removeAll()
        segmentContextByProcess.removeAll()
        healthCheckContextByProcess.removeAll()
        lastHealthCheckAtByProcess.removeAll()
        processStartedAtByIndex.removeAll()
        recoveryInProgress.removeAll()
        scheduledRecoveries.removeAll()
        idleTerminationHistory.removeAll()
        startFailureHistory.removeAll()
        recoverySuppressedUntil.removeAll()
        processLock.unlock()
        
        for (index, manager) in allProcesses {
            manager.outputReceived = nil
            manager.processTerminated = nil
            manager.stop()
            Logger.shared.log("MultiProcessManager: process \(index) stopped", level: .debug)
        }
    }
    
    func getProcessCount() -> Int {
        processLock.lock()
        defer { processLock.unlock() }
        return processes.count
    }
    
    func getIdleProcessCount() -> Int {
        processLock.lock()
        defer { processLock.unlock() }
        return idleProcesses.count
    }
}

private struct SegmentContext {
    let url: URL
    let index: Int
    let settings: AppSettings
    let retryCount: Int
    var assignedAt: Date = .distantPast
}

private struct HealthCheckContext {
    let token: String
    let sentAt: Date
}
