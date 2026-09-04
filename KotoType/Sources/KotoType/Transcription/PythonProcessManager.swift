import Foundation
import Darwin

struct PythonLaunchCommand: Equatable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: String
    let mode: String
}

private struct BackendProcessGroupReadyMessage: Decodable {
    let type: String
    let processID: Int32
    let processGroupID: Int32

    enum CodingKeys: String, CodingKey {
        case type
        case processID = "process_id"
        case processGroupID = "process_group_id"
    }
}

final class PythonProcessManager: @unchecked Sendable {
    static let controlMessagePrefix = "__KOTOTYPE_CONTROL__:"
    private static let healthCheckRequestPrefix = "__KOTOTYPE_HEALTHCHECK__:"

    struct Runtime {
        var currentDirectoryPath: () -> String
        var bundlePath: () -> String
        var bundleResourcePath: () -> String?
        var fileExists: (String) -> Bool
        var findExecutable: (String) -> String?
    }

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var inputPipe: Pipe?
    private var stdoutBuffer: String = ""
    private let stateLock = NSLock()
    private let ioLock = NSLock()
    private let inputWriteLock = NSLock()
    private var processGeneration: UInt64 = 0
    private var isStoppingProcess = false
    private var processGroupID: Int32?
    private var outputReceivedHandler: ((String) -> Void)?
    private var processTerminatedHandler: ((Int32) -> Void)?
    private let runtime: Runtime

    var outputReceived: ((String) -> Void)? {
        get {
            stateLock.lock()
            let handler = outputReceivedHandler
            stateLock.unlock()
            return handler
        }
        set {
            stateLock.lock()
            outputReceivedHandler = newValue
            stateLock.unlock()
        }
    }

    var processTerminated: ((Int32) -> Void)? {
        get {
            stateLock.lock()
            let handler = processTerminatedHandler
            stateLock.unlock()
            return handler
        }
        set {
            stateLock.lock()
            processTerminatedHandler = newValue
            stateLock.unlock()
        }
    }

    init(runtime: Runtime = .live()) {
        self.runtime = runtime
    }

    func startPython(scriptPath: String) {
        Logger.shared.log("startPython called with scriptPath: \(scriptPath)", level: .debug)

        guard let launchCommand = Self.resolveLaunchCommand(scriptPath: scriptPath, runtime: runtime) else {
            let isAppBundleExecution = runtime.bundlePath().hasSuffix(".app")
            let message = isAppBundleExecution
                ? "Failed to resolve backend launch command. This app bundle is missing Resources/whisper_server."
                : "Failed to resolve backend launch command. Ensure bundled whisper_server exists, or install uv for auto setup."
            Logger.shared.log(message, level: .error)
            return
        }

        Logger.shared.log("Backend launch mode: \(launchCommand.mode)", level: .info)
        Logger.shared.log("Working directory: \(launchCommand.workingDirectory)", level: .debug)
        Logger.shared.log("Python binary: \(launchCommand.executablePath)", level: .debug)
        Logger.shared.log("Script args: \(launchCommand.arguments)", level: .debug)

        let newProcess = Process()
        let newOutputPipe = Pipe()
        let newErrorPipe = Pipe()
        let newInputPipe = Pipe()

        ioLock.lock()
        stdoutBuffer = ""
        ioLock.unlock()

        inputWriteLock.lock()
        defer { inputWriteLock.unlock() }
        stateLock.lock()
        if process?.isRunning == true {
            stateLock.unlock()
            Logger.shared.log("Python process is already running", level: .debug)
            return
        }
        processGeneration &+= 1
        let generation = processGeneration
        process = newProcess
        outputPipe = newOutputPipe
        errorPipe = newErrorPipe
        inputPipe = newInputPipe
        isStoppingProcess = false
        processGroupID = nil
        stateLock.unlock()

        newProcess.executableURL = URL(fileURLWithPath: launchCommand.executablePath)
        newProcess.arguments = launchCommand.arguments
        newProcess.standardOutput = newOutputPipe
        newProcess.standardError = newErrorPipe
        newProcess.standardInput = newInputPipe
        newProcess.currentDirectoryURL = URL(fileURLWithPath: launchCommand.workingDirectory)
        var environment = Self.runtimeEnvironment(
            base: ProcessInfo.processInfo.environment,
            bundlePath: runtime.bundlePath()
        )
        environment["KOTOTYPE_PARENT_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
        newProcess.environment = environment
        newProcess.terminationHandler = { [weak self] terminatedProcess in
            self?.handleTermination(of: terminatedProcess, generation: generation)
        }

        do {
            try newProcess.run()
            Logger.shared.log("Python process started successfully", level: .info)
            setupOutputHandler(for: newOutputPipe, generation: generation)
            setupErrorHandler(for: newErrorPipe, generation: generation)
        } catch {
            stateLock.lock()
            if processGeneration == generation {
                process = nil
                outputPipe = nil
                errorPipe = nil
                inputPipe = nil
            }
            stateLock.unlock()
            Logger.shared.log("Failed to start Python process: \(error)", level: .error)
        }
    }
    
    private func setupOutputHandler(for outputPipe: Pipe, generation: UInt64) {
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self.ioLock.lock()
                let lines = Self.extractOutputLines(buffer: &self.stdoutBuffer, chunk: output)
                self.ioLock.unlock()

                for line in lines {
                    guard self.isCurrentGeneration(generation) else { return }
                    if let handshake = Self.parseBackendProcessGroupHandshake(from: line) {
                        self.stateLock.lock()
                        if generation == self.processGeneration,
                           !self.isStoppingProcess,
                           Self.processGroupMatches(
                               launchedProcessID: self.process?.processIdentifier ?? 0,
                               backendProcessID: handshake.processID,
                               groupID: handshake.processGroupID
                           ) {
                            self.processGroupID = handshake.processGroupID
                        }
                        self.stateLock.unlock()
                        continue
                    }
                    Logger.shared.log(
                        "Python stdout line received (length=\(line.count))",
                        level: .debug
                    )
                    self.outputReceived?(line)
                }
            }
        }
        Logger.shared.log("Output handler set up", level: .debug)
    }
    
    private func setupErrorHandler(for errorPipe: Pipe, generation: UInt64) {
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, self?.isCurrentGeneration(generation) == true {
                    let isError = trimmed.contains("Error:") || trimmed.contains("Traceback") || trimmed.contains("Exception")
                    let level: Logger.LogLevel = isError ? .error : .info
                    Logger.shared.log(
                        "Python stderr received (length=\(trimmed.count))",
                        level: level
                    )
                }
            }
        }
        Logger.shared.log("Error handler set up", level: .debug)
    }

    private func handleTermination(of terminatedProcess: Process, generation: UInt64) {
        stateLock.lock()
        let activeProcess = process
        guard generation == processGeneration,
              Self.shouldHandleTermination(
                  activeProcess: activeProcess,
                  terminatedProcess: terminatedProcess
              ) else {
            stateLock.unlock()
            return
        }
        let wasStopping = isStoppingProcess
        let terminationHandler = processTerminatedHandler
        stateLock.unlock()

        if wasStopping {
            Logger.shared.log(
                "Python process terminated during normal stop: \(terminatedProcess.terminationStatus)",
                level: .debug
            )
            return
        }

        let reason = terminatedProcess.terminationReason == .exit ? "exit" : "uncaught-signal"
        Logger.shared.log(
            "Python process terminated with status: \(terminatedProcess.terminationStatus), reason: \(reason)",
            level: .warning
        )
        terminationHandler?(terminatedProcess.terminationStatus)
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        stateLock.lock()
        let isCurrent = generation == processGeneration
        stateLock.unlock()
        return isCurrent
    }

    func sendInput(
        _ text: String,
        language: String = "auto",
        autoPunctuation: Bool = true,
        qualityPreset: TranscriptionQualityPreset = .medium,
        gpuAccelerationEnabled: Bool = true,
        mode: RecordingRequestMode = .transcribe,
        translationTargetLanguage: String = AppSettings.defaultTranslationTargetLanguage,
        screenshotContext: String? = nil
    ) -> Bool {
        if text.hasPrefix(Self.healthCheckRequestPrefix) {
            return sendLine(text)
        }

        var payload: [String: Any] = [
            "type": "transcription_request",
            "audio_path": text,
            "language": language,
            "auto_punctuation": autoPunctuation,
            "quality_preset": qualityPreset.rawValue,
            "gpu_acceleration_enabled": gpuAccelerationEnabled,
            "mode": mode.rawValue,
            "translation_target_language": translationTargetLanguage,
        ]
        if let screenshotContext {
            payload["screenshot_context"] = screenshotContext
        }
        guard let input = Self.encodeJSONPayload(payload) else {
            Logger.shared.log("Failed to encode transcription request payload", level: .error)
            return false
        }
        Logger.shared.log(
            "Sending input to Python: audioPathLength=\(text.count), language=\(language), mode=\(mode.rawValue), translationTargetLanguage=\(translationTargetLanguage), qualityPreset=\(qualityPreset.rawValue), gpuEnabled=\(gpuAccelerationEnabled), screenshotContextLength=\(screenshotContext?.count ?? 0)",
            level: .debug
        )
        return sendLine(input)
    }

    func sendBackendProbe(gpuAccelerationEnabled: Bool, preloadModel: Bool) -> Bool {
        let payload: [String: Any] = [
            "type": "backend_probe",
            "gpu_acceleration_enabled": gpuAccelerationEnabled,
            "preload_model": preloadModel,
        ]
        guard let input = Self.encodeJSONPayload(payload) else {
            Logger.shared.log("Failed to encode backend probe payload", level: .error)
            return false
        }
        Logger.shared.log(
            "Sending backend probe: gpuEnabled=\(gpuAccelerationEnabled), preloadModel=\(preloadModel)",
            level: .debug
        )
        return sendLine(input)
    }

    func sendModelManagement(
        action: ManagedTranscriptionModelAction,
        modelKind: ManagedTranscriptionModelKind? = nil,
        requestID: UInt64
    ) -> Bool {
        var payload: [String: Any] = [
            "type": "model_management",
            "action": action.rawValue,
        ]
        if let modelKind {
            payload["model_kind"] = modelKind.rawValue
        }
        payload["request_id"] = requestID
        guard let input = Self.encodeJSONPayload(payload) else {
            Logger.shared.log("Failed to encode model management payload", level: .error)
            return false
        }
        Logger.shared.log(
            "Sending model management request: action=\(action.rawValue), modelKind=\(modelKind?.rawValue ?? "all")",
            level: .debug
        )
        return sendLine(input)
    }
    
    func isRunning() -> Bool {
        stateLock.lock()
        let running = process?.isRunning ?? false
        stateLock.unlock()
        return running
    }

    func stop() {
        Logger.shared.log("Stopping Python process", level: .info)
        inputWriteLock.lock()
        stateLock.lock()
        isStoppingProcess = true
        let outputPipeToStop = outputPipe
        let errorPipeToStop = errorPipe
        let processToStop = process
        let processGroupToStop = processGroupID
        process = nil
        processGroupID = nil
        outputPipe = nil
        errorPipe = nil
        inputPipe = nil
        stateLock.unlock()
        inputWriteLock.unlock()

        outputPipeToStop?.fileHandleForReading.readabilityHandler = nil
        errorPipeToStop?.fileHandleForReading.readabilityHandler = nil
        if let processGroupToStop {
            Self.terminateProcessGroup(groupID: processGroupToStop)
        } else if let rootPID = processToStop?.processIdentifier,
                  processToStop?.isRunning == true {
            Self.terminateProcessTree(rootPID: rootPID)
        } else if processToStop?.isRunning == true {
            processToStop?.terminate()
        }
        ioLock.lock()
        stdoutBuffer = ""
        ioLock.unlock()
    }

    static func resolveLaunchCommand(scriptPath: String, runtime: Runtime) -> PythonLaunchCommand? {
        let currentPath = runtime.currentDirectoryPath()
        let workingDirectory = repositoryRoot(currentPath: currentPath)
        let isAppBundleExecution = runtime.bundlePath().hasSuffix(".app")

        if let bundlePath = runtime.bundleResourcePath() {
            let bundledServer = "\(bundlePath)/whisper_server"
            if runtime.fileExists(bundledServer) {
                return PythonLaunchCommand(
                    executablePath: bundledServer,
                    arguments: [],
                    workingDirectory: workingDirectory,
                    mode: "bundled-binary"
                )
            }

            // Distribution builds must ship whisper_server and must not rely on user-side uv/Python.
            if isAppBundleExecution {
                return nil
            }
        }

        guard runtime.fileExists(scriptPath) else {
            return nil
        }

        if let uvPath = runtime.findExecutable("uv") {
            return PythonLaunchCommand(
                executablePath: uvPath,
                arguments: ["run", "--project", workingDirectory, "python", scriptPath],
                workingDirectory: workingDirectory,
                mode: "uv-run"
            )
        }

        let developmentPython = "\(workingDirectory)/.venv/bin/python"
        if runtime.fileExists(developmentPython) {
            return PythonLaunchCommand(
                executablePath: developmentPython,
                arguments: [scriptPath],
                workingDirectory: workingDirectory,
                mode: "venv-python"
            )
        }

        return nil
    }

    static func extractOutputLines(buffer: inout String, chunk: String) -> [String] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)
        var lines: [String] = []

        while let newlineIndex = buffer.firstIndex(where: { $0.isNewline }) {
            let line = String(buffer[..<newlineIndex])
            var consumeEnd = buffer.index(after: newlineIndex)

            if buffer[newlineIndex] == "\r",
               consumeEnd < buffer.endIndex,
               buffer[consumeEnd] == "\n" {
                consumeEnd = buffer.index(after: consumeEnd)
            }

            lines.append(line)
            buffer.removeSubrange(buffer.startIndex..<consumeEnd)
        }

        return lines
    }

    static func shouldHandleTermination(activeProcess: Process?, terminatedProcess: Process) -> Bool {
        activeProcess === terminatedProcess
    }

    static func parseBackendProcessGroupID(from output: String) -> Int32? {
        parseBackendProcessGroupHandshake(from: output)?.processGroupID
    }

    private static func parseBackendProcessGroupHandshake(
        from output: String
    ) -> (processID: Int32, processGroupID: Int32)? {
        guard let message = decodeControlMessage(BackendProcessGroupReadyMessage.self, from: output),
              message.type == "backend_process_group_ready",
              message.processID > 0,
              message.processGroupID > 1 else {
            return nil
        }
        return (message.processID, message.processGroupID)
    }

    private static func processGroupMatches(
        launchedProcessID: Int32,
        backendProcessID: Int32,
        groupID: Int32
    ) -> Bool {
        guard launchedProcessID > 0, backendProcessID > 0, groupID > 1,
              getpgid(backendProcessID) == groupID else {
            return false
        }
        return processIsDescendantOrSelf(
            processID: backendProcessID,
            ancestorProcessID: launchedProcessID
        )
    }

    private static func processIsDescendantOrSelf(
        processID: Int32,
        ancestorProcessID: Int32
    ) -> Bool {
        var currentProcessID = processID
        var visited: Set<Int32> = []
        for _ in 0..<64 {
            if currentProcessID == ancestorProcessID { return true }
            guard visited.insert(currentProcessID).inserted,
                  let parentProcessID = parentProcessID(of: currentProcessID),
                  parentProcessID > 0,
                  parentProcessID != currentProcessID else {
                return false
            }
            currentProcessID = parentProcessID
        }
        return false
    }

    private static func parentProcessID(of processID: Int32) -> Int32? {
        var processInfo = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(processID, PROC_PIDTBSDINFO, 0, &processInfo, expectedSize) == expectedSize else {
            return nil
        }
        return Int32(processInfo.pbi_ppid)
    }

    private static func decodeControlMessage<T: Decodable>(_ type: T.Type, from output: String) -> T? {
        guard output.hasPrefix(controlMessagePrefix) else {
            return nil
        }

        let payload = String(output.dropFirst(controlMessagePrefix.count))
        guard let data = payload.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    static func parseBackendStatus(from output: String) -> TranscriptionBackendStatus? {
        decodeControlMessage(TranscriptionBackendStatus.self, from: output)
    }

    static func parseBackendPreparationProgress(from output: String) -> BackendPreparationProgress? {
        guard let progress = decodeControlMessage(BackendPreparationProgress.self, from: output),
              progress.type == "backend_preparation_progress" else {
            return nil
        }
        return progress
    }

    static func parseManagedModelsResponse(from output: String) -> ManagedTranscriptionModelsResponse? {
        guard let response = decodeControlMessage(ManagedTranscriptionModelsResponse.self, from: output),
              response.type == "managed_models" else {
            return nil
        }
        return response
    }

    static func parseManagedModelResponse(from output: String) -> ManagedTranscriptionModelResponse? {
        guard let response = decodeControlMessage(ManagedTranscriptionModelResponse.self, from: output),
              response.type == "managed_model" else {
            return nil
        }
        return response
    }

    private func sendLine(_ input: String) -> Bool {
        guard let data = (input + "\n").data(using: .utf8) else {
            Logger.shared.log("Failed to encode input text", level: .error)
            return false
        }

        inputWriteLock.lock()
        defer { inputWriteLock.unlock() }

        stateLock.lock()
        let process = self.process
        let inputFileHandle = inputPipe?.fileHandleForWriting
        stateLock.unlock()

        guard let process, process.isRunning, let inputFileHandle else {
            Logger.shared.log("Cannot send input: Python process is not running", level: .error)
            return false
        }

        do {
            try inputFileHandle.write(contentsOf: data)
            Logger.shared.log("Input sent to Python successfully", level: .debug)
            return true
        } catch {
            Logger.shared.log("Failed to send input to Python: \(error)", level: .error)
            return false
        }
    }

    private static func encodeJSONPayload(_ payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    static func descendantProcessIdentifiers(rootPID: Int32, psOutput: String) -> [Int32] {
        var childrenByParent: [Int32: [Int32]] = [:]

        for rawLine in psOutput.split(whereSeparator: \.isNewline) {
            let columns = rawLine.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 2,
                  let pid = Int32(columns[0]),
                  let parentPID = Int32(columns[1]) else {
                continue
            }
            childrenByParent[parentPID, default: []].append(pid)
        }

        var descendants: [Int32] = []
        var stack = childrenByParent[rootPID] ?? []

        while let pid = stack.popLast() {
            descendants.append(pid)
            stack.append(contentsOf: childrenByParent[pid] ?? [])
        }

        return descendants
    }

    private static func terminateProcessTree(rootPID: Int32) {
        guard rootPID > 0 else { return }

        let psOutput = currentProcessList()
        let descendantPIDs = descendantProcessIdentifiers(rootPID: rootPID, psOutput: psOutput)
        let processTree = descendantPIDs + [rootPID]

        signalProcesses(processTree.reversed(), signal: SIGTERM)
        usleep(300_000)
        signalProcesses(processTree.reversed(), signal: SIGKILL)
    }

    private static func terminateProcessGroup(groupID: Int32) {
        guard groupID > 1 else { return }
        _ = Darwin.kill(-groupID, SIGTERM)
        usleep(300_000)
        _ = Darwin.kill(-groupID, SIGKILL)
    }

    private static func signalProcesses<S: Sequence>(_ pids: S, signal: Int32) where S.Element == Int32 {
        for pid in pids where pid > 0 {
            _ = Darwin.kill(pid, signal)
        }
    }

    private static func currentProcessList() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return ""
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func repositoryRoot(currentPath: String) -> String {
        currentPath.range(of: "/KotoType").map {
            String(currentPath[..<$0.lowerBound])
        } ?? currentPath
    }
}

extension PythonProcessManager.Runtime {
    static func live() -> PythonProcessManager.Runtime {
        PythonProcessManager.Runtime(
            currentDirectoryPath: { FileManager.default.currentDirectoryPath },
            bundlePath: { Bundle.main.bundlePath },
            bundleResourcePath: { Bundle.main.resourcePath },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            findExecutable: { name in PythonProcessManager.resolveExecutable(named: name) }
        )
    }
}

extension PythonProcessManager {
    static func runtimeEnvironment(base: [String: String], bundlePath: String) -> [String: String] {
        var environment = base
        environment.merge(KotoTypeStoragePaths.managedModelEnvironment()) { _, new in new }
        if bundlePath.hasSuffix(".app") {
            // Distribution runtime safety: never allow multi-server / multi-load overrides.
            environment["KOTOTYPE_MAX_ACTIVE_SERVERS"] = "1"
            environment["KOTOTYPE_MAX_PARALLEL_MODEL_LOADS"] = "1"
            environment["KOTOTYPE_MODEL_LOAD_WAIT_TIMEOUT_SECONDS"] = "120"
            environment["PATH"] = mergedSearchPath(
                basePath: environment["PATH"],
                prepending: ["/opt/homebrew/bin", "/usr/local/bin"]
            )
        }
        return environment
    }

    static func mergedSearchPath(basePath: String?, prepending directories: [String]) -> String {
        let existing = (basePath ?? "")
            .split(separator: ":")
            .map(String.init)

        var merged: [String] = []
        var seen: Set<String> = []

        for candidate in directories + existing {
            guard !candidate.isEmpty else { continue }
            if seen.insert(candidate).inserted {
                merged.append(candidate)
            }
        }

        return merged.joined(separator: ":")
    }

    static func resolveExecutable(named name: String) -> String? {
        let fallbackPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]

        for path in fallbackPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !output.isEmpty else {
                return nil
            }
            return output
        } catch {
            return nil
        }
    }
}
