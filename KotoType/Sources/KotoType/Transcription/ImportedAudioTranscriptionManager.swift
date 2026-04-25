import Foundation

enum ImportedAudioTranscriptionError: Error, Equatable {
    case managerBusy
    case processUnavailable
    case scriptPathNotConfigured
    case sendFailed
    case processTerminated(status: Int32)
}

protocol PythonProcessManaging: AnyObject {
    var outputReceived: ((String) -> Void)? { get set }
    var processTerminated: ((Int32) -> Void)? { get set }

    func startPython(scriptPath: String)
    func sendInput(
        _ text: String,
        language: String,
        autoPunctuation: Bool,
        qualityPreset: TranscriptionQualityPreset,
        gpuAccelerationEnabled: Bool,
        screenshotContext: String?
    ) -> Bool
    func sendBackendProbe(gpuAccelerationEnabled: Bool, preloadModel: Bool) -> Bool
    func isRunning() -> Bool
    func stop()
}

extension PythonProcessManager: PythonProcessManaging {}

final class ImportedAudioTranscriptionManager: @unchecked Sendable {
    private let processManager: any PythonProcessManaging
    private let lock = NSLock()
    private let keepProcessAlive: Bool

    private var scriptPath: String = ""
    private var pendingCompletion: ((Result<String, ImportedAudioTranscriptionError>) -> Void)?

    init(processManager: any PythonProcessManaging = PythonProcessManager(), keepProcessAlive: Bool = false) {
        self.processManager = processManager
        self.keepProcessAlive = keepProcessAlive
        processManager.outputReceived = { [weak self] output in
            self?.handleOutput(output)
        }
        processManager.processTerminated = { [weak self] status in
            self?.handleTermination(status: status)
        }
    }

    func configure(scriptPath: String) {
        lock.lock()
        self.scriptPath = scriptPath
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let completion = pendingCompletion
        pendingCompletion = nil
        lock.unlock()

        completion?(.failure(.processUnavailable))
        processManager.stop()
    }

    func transcribe(fileURL: URL, settings: AppSettings, completion: @escaping (Result<String, ImportedAudioTranscriptionError>) -> Void) {
        lock.lock()
        if pendingCompletion != nil {
            lock.unlock()
            completion(.failure(.managerBusy))
            return
        }

        let currentScriptPath = scriptPath
        pendingCompletion = completion
        lock.unlock()

        guard !currentScriptPath.isEmpty else {
            finish(with: .failure(.scriptPathNotConfigured))
            return
        }

        if !processManager.isRunning() {
            processManager.startPython(scriptPath: currentScriptPath)
        }

        if !processManager.isRunning() {
            finish(with: .failure(.processUnavailable))
            return
        }

        let succeeded = processManager.sendInput(
            fileURL.path,
            language: settings.language,
            autoPunctuation: settings.autoPunctuation,
            qualityPreset: settings.transcriptionQualityPreset,
            gpuAccelerationEnabled: settings.gpuAccelerationEnabled,
            screenshotContext: nil
        )

        if !succeeded {
            finish(with: .failure(.sendFailed))
        }
    }

    private func handleOutput(_ output: String) {
        if let status = PythonProcessManager.parseBackendStatus(from: output) {
            TranscriptionBackendStatusStore.publishFromAnyThread(status)
            return
        }
        finish(with: .success(output))
    }

    private func handleTermination(status: Int32) {
        finish(with: .failure(.processTerminated(status: status)))
    }

    private func finish(with result: Result<String, ImportedAudioTranscriptionError>) {
        lock.lock()
        let completion = pendingCompletion
        pendingCompletion = nil
        lock.unlock()

        if !keepProcessAlive {
            processManager.stop()
        }

        guard let completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
