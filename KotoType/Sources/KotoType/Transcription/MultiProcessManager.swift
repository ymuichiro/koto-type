import Foundation

final class MultiProcessManager: @unchecked Sendable {
    private var processes: [Int: PythonProcessManager] = [:]
    private var idleProcesses: Set<Int> = []
    private var segmentContextByProcess: [Int: SegmentContext] = [:]
    private var recoveryInProgress: Set<Int> = []
    private var scheduledRecoveries: Set<Int> = []
    private var idleTerminationHistory: [Int: [Date]] = [:]
    private var recoverySuppressedUntil: [Int: Date] = [:]
    private var processLock = NSLock()
    private var scriptPath: String = ""
    private let maxRetryCount = 2
    private let maxIdleTerminationsPerWindow = 3
    private let idleTerminationWindowSeconds: TimeInterval = 30
    private let idleRecoveryCooldownSeconds: TimeInterval = 60
    private let idleRecoveryBaseDelaySeconds: TimeInterval = 0.5
    private var isStopping = false
    
    var outputReceived: ((Int, String) -> Void)?
    var segmentComplete: ((Int, String) -> Void)?
    
    func initialize(count: Int, scriptPath: String) {
        Logger.shared.log("MultiProcessManager: initialize called - count=\(count), scriptPath=\(scriptPath)", level: .info)
        processLock.lock()
        defer { processLock.unlock() }
        
        self.scriptPath = scriptPath
        self.isStopping = false
        self.recoveryInProgress.removeAll()
        self.scheduledRecoveries.removeAll()
        self.idleTerminationHistory.removeAll()
        self.recoverySuppressedUntil.removeAll()
        
        for i in 0..<count {
            createProcess(processIndex: i)
        }
        
        Logger.shared.log("MultiProcessManager: initialized with \(processes.count) processes", level: .info)
    }
    
    func processFile(url: URL, index: Int, settings: AppSettings, retryCount: Int = 0) {
        Logger.shared.log("MultiProcessManager: processFile called - url=\(url.path), index=\(index)", level: .info)
        processLock.lock()
        if isStopping {
            processLock.unlock()
            Logger.shared.log("MultiProcessManager: ignoring processFile because manager is stopping", level: .warning)
            return
        }
        let availableProcess = idleProcesses.first
        processLock.unlock()
        
        guard let processIndex = availableProcess else {
            Logger.shared.log("MultiProcessManager: no idle process available, queuing file: \(url.path)", level: .warning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.processFile(url: url, index: index, settings: settings, retryCount: retryCount)
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
            )
        )
    }
    
    private func assignProcess(processIndex: Int, context: SegmentContext) {
        processLock.lock()
        idleProcesses.remove(processIndex)
        segmentContextByProcess[processIndex] = context
        processLock.unlock()
        
        guard let manager = processes[processIndex] else {
            Logger.shared.log("MultiProcessManager: process \(processIndex) not found", level: .error)
            handleProcessFailure(processIndex: processIndex, context: context, reason: "manager_not_found")
            return
        }
        
        guard manager.isRunning() else {
            Logger.shared.log("MultiProcessManager: process \(processIndex) is not running", level: .error)
            handleProcessFailure(processIndex: processIndex, context: context, reason: "process_not_running")
            return
        }
        
        Logger.shared.log(
            "MultiProcessManager: process \(processIndex) processing file \(context.index): \(context.url.path) (retry=\(context.retryCount))",
            level: .info
        )
        
        let sendSucceeded = manager.sendInput(
            context.url.path,
            language: context.settings.language,
            temperature: context.settings.temperature,
            beamSize: context.settings.beamSize,
            noSpeechThreshold: context.settings.noSpeechThreshold,
            compressionRatioThreshold: context.settings.compressionRatioThreshold,
            task: context.settings.task,
            bestOf: context.settings.bestOf,
            vadThreshold: context.settings.vadThreshold,
            autoPunctuation: context.settings.autoPunctuation,
            autoGainEnabled: context.settings.autoGainEnabled,
            autoGainWeakThresholdDbfs: context.settings.autoGainWeakThresholdDbfs,
            autoGainTargetPeakDbfs: context.settings.autoGainTargetPeakDbfs,
            autoGainMaxDb: context.settings.autoGainMaxDb
        )

        if !sendSucceeded {
            handleProcessFailure(processIndex: processIndex, context: context, reason: "send_input_failed")
        }
    }
    
    private func handleOutput(processIndex: Int, output: String) {
        Logger.shared.log("MultiProcessManager: handleOutput called - processIndex=\(processIndex), output='\(output)'", level: .info)
        
        processLock.lock()
        guard let context = segmentContextByProcess[processIndex] else {
            processLock.unlock()
            Logger.shared.log("MultiProcessManager: no segment index for process \(processIndex)", level: .error)
            return
        }
        segmentContextByProcess.removeValue(forKey: processIndex)
        idleProcesses.insert(processIndex)
        idleTerminationHistory.removeValue(forKey: processIndex)
        recoverySuppressedUntil.removeValue(forKey: processIndex)
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
        processLock.unlock()

        guard shouldHandle else {
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
        processLock.unlock()

        recoverProcess(processIndex: processIndex)
        retryOrCompleteWithEmpty(context: context)
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
                retryCount: nextRetry
            )
        }
    }

    private func createProcess(processIndex: Int) {
        let manager = PythonProcessManager()
        manager.outputReceived = { [weak self] output in
            self?.handleOutput(processIndex: processIndex, output: output)
        }
        manager.processTerminated = { [weak self] status in
            self?.handleProcessTermination(processIndex: processIndex, status: status)
        }
        manager.startPython(scriptPath: scriptPath)
        processes[processIndex] = manager
        if manager.isRunning() {
            idleProcesses.insert(processIndex)
            Logger.shared.log("MultiProcessManager: process \(processIndex) initialized", level: .debug)
            return
        }

        Logger.shared.log(
            "MultiProcessManager: process \(processIndex) failed to start; scheduling recovery",
            level: .error
        )
        scheduleRecovery(processIndex: processIndex, delay: idleRecoveryBaseDelaySeconds)
    }

    private func recoverProcess(processIndex: Int) {
        var oldManager: PythonProcessManager?
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

        oldManager = processes[processIndex]
        idleProcesses.remove(processIndex)
        segmentContextByProcess.removeValue(forKey: processIndex)
        processLock.unlock()

        oldManager?.outputReceived = nil
        oldManager?.processTerminated = nil
        oldManager?.stop()

        processLock.lock()
        if isStopping {
            recoveryInProgress.remove(processIndex)
            processLock.unlock()
            return
        }
        createProcess(processIndex: processIndex)
        recoveryInProgress.remove(processIndex)
        processLock.unlock()
    }

    private func handleIdleProcessTermination(processIndex: Int, status: Int32) {
        let now = Date()
        var historyCount = 0
        var shouldCooldown = false
        var isBlocked = false
        var delay = idleRecoveryBaseDelaySeconds

        processLock.lock()
        var history = idleTerminationHistory[processIndex] ?? []
        history.removeAll { now.timeIntervalSince($0) > idleTerminationWindowSeconds }
        history.append(now)
        idleTerminationHistory[processIndex] = history
        historyCount = history.count

        if let blockedUntil = recoverySuppressedUntil[processIndex], blockedUntil > now {
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
            let blocked = (self.recoverySuppressedUntil[processIndex] ?? .distantPast) > now
            self.processLock.unlock()

            if blocked {
                return
            }
            self.recoverProcess(processIndex: processIndex)
        }
    }
    
    func stop() {
        Logger.shared.log("MultiProcessManager: stop called", level: .info)
        processLock.lock()
        isStopping = true
        let allProcesses = processes
        processes.removeAll()
        idleProcesses.removeAll()
        segmentContextByProcess.removeAll()
        recoveryInProgress.removeAll()
        scheduledRecoveries.removeAll()
        idleTerminationHistory.removeAll()
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
}
