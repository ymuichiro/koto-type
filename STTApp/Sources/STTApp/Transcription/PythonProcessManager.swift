import Foundation

final class PythonProcessManager: @unchecked Sendable {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var inputPipe: Pipe?
    private var stdoutBuffer: String = ""
    private let ioLock = NSLock()
    private var isStoppingProcess = false
    var outputReceived: ((String) -> Void)?
    var processTerminated: ((Int32) -> Void)?
    
    func startPython(scriptPath: String) {
        Logger.shared.log("startPython called with scriptPath: \(scriptPath)", level: .debug)
        
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let workingDirectory = BackendLocator.repositoryRoot(currentPath: currentPath)
        
        Logger.shared.log("Working directory: \(workingDirectory)", level: .debug)
        
        // Resources内のwhisper_serverバイナリを使用
        var serverBinary = "\(workingDirectory)/.venv/bin/python"
        var scriptArgs = [scriptPath]
        
        // リソース内のバイナリを試す
        if let bundlePath = Bundle.main.resourcePath {
            let bundledServer = "\(bundlePath)/whisper_server"
            if fileManager.fileExists(atPath: bundledServer) {
                serverBinary = bundledServer
                scriptArgs = []  // バイナリには引数不要
                Logger.shared.log("Using bundled server at: \(bundledServer)", level: .info)
            }
        }
        
        Logger.shared.log("Python binary: \(serverBinary)", level: .debug)
        Logger.shared.log("Script args: \(scriptArgs)", level: .debug)
        
        process = Process()
        outputPipe = Pipe()
        errorPipe = Pipe()
        inputPipe = Pipe()
        ioLock.lock()
        stdoutBuffer = ""
        ioLock.unlock()
        isStoppingProcess = false
        
        process?.executableURL = URL(fileURLWithPath: serverBinary)
        process?.arguments = scriptArgs
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        process?.standardInput = inputPipe
        process?.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process?.terminationHandler = { [weak self] terminatedProcess in
            guard let self = self else { return }
            if self.isStoppingProcess {
                Logger.shared.log(
                    "Python process terminated during normal stop: \(terminatedProcess.terminationStatus)",
                    level: .debug
                )
                return
            }
            Logger.shared.log(
                "Python process terminated with status: \(terminatedProcess.terminationStatus)",
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
    
    func sendInput(_ text: String, language: String = "ja", temperature: Double = 0.0, beamSize: Int = 5, noSpeechThreshold: Double = 0.6, compressionRatioThreshold: Double = 2.4, task: String = "transcribe", bestOf: Int = 5, vadThreshold: Double = 0.5, autoPunctuation: Bool = true) -> Bool {
        let punctuationFlag = autoPunctuation ? "1" : "0"
        let input = "\(text)|\(language)|\(temperature)|\(beamSize)|\(noSpeechThreshold)|\(compressionRatioThreshold)|\(task)|\(bestOf)|\(vadThreshold)|\(punctuationFlag)"
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
