import Foundation

final class MultiProcessManager: @unchecked Sendable {
    private var processes: [Int: PythonProcessManager] = [:]
    private var idleProcesses: Set<Int> = []
    private var segmentContextByProcess: [Int: SegmentContext] = [:]
    private var processLock = NSLock()
    private var scriptPath: String = ""
    private let maxRetryCount = 2
    private var isStopping = false
    
    var outputReceived: ((Int, String) -> Void)?
    var segmentComplete: ((Int, String) -> Void)?
    
    func initialize(count: Int, scriptPath: String) {
        Logger.shared.log("MultiProcessManager: initialize called - count=\(count), scriptPath=\(scriptPath)", level: .info)
        processLock.lock()
        defer { processLock.unlock() }
        
        self.scriptPath = scriptPath
        self.isStopping = false
        
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
            vadThreshold: context.settings.vadThreshold
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
            recoverProcess(processIndex: processIndex)
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
        idleProcesses.insert(processIndex)
        Logger.shared.log("MultiProcessManager: process \(processIndex) initialized", level: .debug)
    }

    private func recoverProcess(processIndex: Int) {
        var oldManager: PythonProcessManager?
        processLock.lock()
        if isStopping {
            processLock.unlock()
            return
        }

        oldManager = processes[processIndex]
        idleProcesses.remove(processIndex)
        segmentContextByProcess.removeValue(forKey: processIndex)
        processLock.unlock()

        oldManager?.outputReceived = nil
        oldManager?.processTerminated = nil
        oldManager?.stop()

        processLock.lock()
        if isStopping {
            processLock.unlock()
            return
        }
        createProcess(processIndex: processIndex)
        processLock.unlock()
    }
    
    func stop() {
        Logger.shared.log("MultiProcessManager: stop called", level: .info)
        processLock.lock()
        isStopping = true
        let allProcesses = processes
        processes.removeAll()
        idleProcesses.removeAll()
        segmentContextByProcess.removeAll()
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
