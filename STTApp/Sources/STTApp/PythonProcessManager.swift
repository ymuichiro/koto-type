import Foundation

final class PythonProcessManager: @unchecked Sendable {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var inputPipe: Pipe?
    var outputReceived: ((String) -> Void)?
    
    func startPython(scriptPath: String) {
        Logger.shared.log("startPython called with scriptPath: \(scriptPath)", level: .debug)
        
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        var workingDirectory = currentPath
        if currentPath.contains("STTApp") {
            workingDirectory = currentPath.replacingOccurrences(of: "/STTApp", with: "")
        }
        
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
        
        process?.executableURL = URL(fileURLWithPath: serverBinary)
        process?.arguments = scriptArgs
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        process?.standardInput = inputPipe
        process?.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        
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
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                Logger.shared.log("Python stdout received: '\(output)' (trimmed: '\(trimmed)')", level: .debug)
                self?.outputReceived?(trimmed)
            }
        }
        Logger.shared.log("Output handler set up", level: .debug)
    }
    
    private func setupErrorHandler() {
        errorPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
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
    
    func sendInput(_ text: String, language: String = "ja", temperature: Double = 0.0, beamSize: Int = 5) {
        let input = "\(text)|\(language)|\(temperature)|\(beamSize)"
        Logger.shared.log("Sending input to Python: \(input)", level: .debug)
        guard let data = (input + "\n").data(using: .utf8) else {
            Logger.shared.log("Failed to encode input text", level: .error)
            return
        }
        
        do {
            try inputPipe?.fileHandleForWriting.write(contentsOf: data)
            Logger.shared.log("Input sent to Python successfully", level: .debug)
        } catch {
            Logger.shared.log("Failed to send input to Python: \(error)", level: .error)
        }
    }
    
    func stop() {
        Logger.shared.log("Stopping Python process", level: .info)
        process?.terminate()
        process = nil
        outputPipe = nil
        errorPipe = nil
        inputPipe = nil
    }
}
