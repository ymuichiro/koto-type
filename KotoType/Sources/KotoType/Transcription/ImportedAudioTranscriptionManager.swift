import Foundation

enum ImportedAudioTranscriptionError: Error, Equatable {
    case managerBusy
    case processUnavailable
    case scriptPathNotConfigured
    case sendFailed
    case processTerminated(status: Int32)
    case backendError(String)
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
        screenshotContext: String?,
        requestID: String
    ) -> Bool
    func sendBackendProbe(gpuAccelerationEnabled: Bool, preloadModel: Bool) -> Bool
    func isRunning() -> Bool
    func stop()
}

extension PythonProcessManager: PythonProcessManaging {}

final class ImportedAudioTranscriptionManager: @unchecked Sendable {
    private let processManager: any PythonProcessManaging
    private let lock = NSLock()

    private var scriptPath: String = ""
    private var pendingCompletion: ((Result<String, ImportedAudioTranscriptionError>) -> Void)?
    private var pendingRequestID: String?

    init(processManager: any PythonProcessManaging = PythonProcessManager()) {
        self.processManager = processManager
        processManager.outputReceived = { [weak self] output in
            self?.handleOutput(output)
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
        pendingRequestID = nil
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
        let requestID = UUID().uuidString
        pendingRequestID = requestID
        pendingCompletion = completion
        lock.unlock()

        processManager.processTerminated = { [weak self] status in
            self?.finish(with: .failure(.processTerminated(status: status)), requestID: requestID)
        }

        guard !currentScriptPath.isEmpty else {
            finish(with: .failure(.scriptPathNotConfigured), requestID: requestID)
            return
        }

        if !processManager.isRunning() {
            processManager.startPython(scriptPath: currentScriptPath)
        }

        if !processManager.isRunning() {
            finish(with: .failure(.processUnavailable), requestID: requestID)
            return
        }

        let succeeded = processManager.sendInput(
            fileURL.path,
            language: settings.language,
            autoPunctuation: settings.autoPunctuation,
            qualityPreset: settings.transcriptionQualityPreset,
            gpuAccelerationEnabled: settings.gpuAccelerationEnabled,
            screenshotContext: nil,
            requestID: requestID
        )

        if !succeeded {
            finish(with: .failure(.sendFailed), requestID: requestID)
        }
    }

    private func handleOutput(_ output: String) {
        if let status = PythonProcessManager.parseBackendStatus(from: output) {
            TranscriptionBackendStatusStore.publishFromAnyThread(status)
            return
        }
        guard let response = TranscriptionResponse.parse(output) else { return }
        let result: Result<String, ImportedAudioTranscriptionError> = response.text.map { .success($0) }
            ?? .failure(.backendError(response.error!))
        finish(with: result, requestID: response.request_id)
    }

    private func finish(with result: Result<String, ImportedAudioTranscriptionError>, requestID: String) {
        lock.lock()
        if pendingRequestID != requestID {
            lock.unlock()
            return
        }
        let completion = pendingCompletion
        pendingCompletion = nil
        pendingRequestID = nil
        lock.unlock()

        processManager.stop()

        guard let completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
