import Foundation

struct PythonLaunchCommand: Equatable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: String
    let mode: String
}

final class PythonProcessManager: @unchecked Sendable {
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
    private let ioLock = NSLock()
    private var isStoppingProcess = false
    private let runtime: Runtime
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?

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

        process = Process()
        outputPipe = Pipe()
        errorPipe = Pipe()
        inputPipe = Pipe()
        ioLock.lock()
        stdoutBuffer = ""
        ioLock.unlock()
        isStoppingProcess = false

        process?.executableURL = URL(fileURLWithPath: launchCommand.executablePath)
        process?.arguments = launchCommand.arguments
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        process?.standardInput = inputPipe
        process?.currentDirectoryURL = URL(fileURLWithPath: launchCommand.workingDirectory)
        process?.environment = Self.runtimeEnvironment(
            base: ProcessInfo.processInfo.environment,
            bundlePath: runtime.bundlePath()
        )
        process?.terminationHandler = { [weak self] terminatedProcess in
            guard let self = self else { return }
            if self.isStoppingProcess {
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
            self.processTerminated?(terminatedProcess.terminationStatus)
        }
        
        do {
            try process?.run()
            Logger.shared.log("Python process started successfully", level: .info)
            setupOutputHandler()
            setupErrorHandler()
        } catch {
            Logger.shared.log("Failed to start Python process: \(error)", level: .error)
        }
    }
    
    private func setupOutputHandler() {
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self.ioLock.lock()
                let lines = Self.extractOutputLines(buffer: &self.stdoutBuffer, chunk: output)
                self.ioLock.unlock()

                for line in lines {
                    Logger.shared.log("Python stdout line received: '\(line)'", level: .debug)
                    self.outputReceived?(line)
                }
            }
        }
        Logger.shared.log("Output handler set up", level: .debug)
    }
    
    private func setupErrorHandler() {
        errorPipe?.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let isError = trimmed.contains("Error:") || trimmed.contains("Traceback") || trimmed.contains("Exception")
                    let level: Logger.LogLevel = isError ? .error : .info
                    Logger.shared.log("Python stderr: \(trimmed)", level: level)
                }
            }
        }
        Logger.shared.log("Error handler set up", level: .debug)
    }
    
    func sendInput(
        _ text: String,
        language: String = "auto",
        temperature: Double = 0.0,
        beamSize: Int = 5,
        noSpeechThreshold: Double = 0.6,
        compressionRatioThreshold: Double = 2.4,
        task: String = "transcribe",
        bestOf: Int = 5,
        vadThreshold: Double = 0.5,
        autoPunctuation: Bool = true,
        autoGainEnabled: Bool = true,
        autoGainWeakThresholdDbfs: Double = -18.0,
        autoGainTargetPeakDbfs: Double = -10.0,
        autoGainMaxDb: Double = 18.0
    ) -> Bool {
        let punctuationFlag = autoPunctuation ? "1" : "0"
        let autoGainFlag = autoGainEnabled ? "1" : "0"
        let input = "\(text)|\(language)|\(temperature)|\(beamSize)|\(noSpeechThreshold)|\(compressionRatioThreshold)|\(task)|\(bestOf)|\(vadThreshold)|\(punctuationFlag)|\(autoGainFlag)|\(autoGainWeakThresholdDbfs)|\(autoGainTargetPeakDbfs)|\(autoGainMaxDb)"
        Logger.shared.log("Sending input to Python: \(input)", level: .debug)
        guard let process = process, process.isRunning else {
            Logger.shared.log("Cannot send input: Python process is not running", level: .error)
            return false
        }
        guard let data = (input + "\n").data(using: .utf8) else {
            Logger.shared.log("Failed to encode input text", level: .error)
            return false
        }

        do {
            try inputPipe?.fileHandleForWriting.write(contentsOf: data)
            Logger.shared.log("Input sent to Python successfully", level: .debug)
            return true
        } catch {
            Logger.shared.log("Failed to send input to Python: \(error)", level: .error)
            return false
        }
    }
    
    func isRunning() -> Bool {
        process?.isRunning ?? false
    }

    func stop() {
        Logger.shared.log("Stopping Python process", level: .info)
        isStoppingProcess = true
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        outputPipe = nil
        errorPipe = nil
        inputPipe = nil
        ioLock.lock()
        stdoutBuffer = ""
        ioLock.unlock()
    }

    static func resolveLaunchCommand(scriptPath: String, runtime: Runtime) -> PythonLaunchCommand? {
        let currentPath = runtime.currentDirectoryPath()
        let workingDirectory = BackendLocator.repositoryRoot(currentPath: currentPath)
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
        if bundlePath.hasSuffix(".app") {
            // Distribution runtime safety: never allow multi-server / multi-load overrides.
            environment["KOTOTYPE_MAX_ACTIVE_SERVERS"] = "1"
            environment["KOTOTYPE_MAX_PARALLEL_MODEL_LOADS"] = "1"
            environment["KOTOTYPE_MODEL_LOAD_WAIT_TIMEOUT_SECONDS"] = "120"
        }
        return environment
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
