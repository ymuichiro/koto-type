import Foundation

final class BackendPreparationService: @unchecked Sendable {
    private let processManager: any PythonProcessManaging
    private let lock = NSLock()

    private var scriptPath: String = ""
    private var pendingCompletion: ((TranscriptionBackendStatus?) -> Void)?

    init(processManager: any PythonProcessManaging = PythonProcessManager()) {
        self.processManager = processManager
        processManager.outputReceived = { [weak self] output in
            self?.handleOutput(output)
        }
        processManager.processTerminated = { [weak self] _ in
            self?.finish(with: nil)
        }
    }

    func configure(scriptPath: String) {
        lock.lock()
        self.scriptPath = scriptPath
        lock.unlock()
    }

    func prepare(
        settings: AppSettings,
        preloadModel: Bool,
        timeout: TimeInterval
    ) async -> TranscriptionBackendStatus? {
        let (currentScriptPath, hasPendingCompletion) = lock.withLock {
            (scriptPath, pendingCompletion != nil)
        }

        guard !currentScriptPath.isEmpty, !hasPendingCompletion else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            pendingCompletion = { status in
                continuation.resume(returning: status)
            }
            lock.unlock()

            if !processManager.isRunning() {
                processManager.startPython(scriptPath: currentScriptPath)
            }
            guard processManager.isRunning() else {
                finish(with: nil)
                return
            }

            let sent = processManager.sendBackendProbe(
                gpuAccelerationEnabled: settings.gpuAccelerationEnabled,
                preloadModel: preloadModel
            )
            guard sent else {
                finish(with: nil)
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    private func handleOutput(_ output: String) {
        guard let status = PythonProcessManager.parseBackendStatus(from: output) else {
            return
        }
        TranscriptionBackendStatusStore.publishFromAnyThread(status)
        finish(with: status)
    }

    private func finish(with status: TranscriptionBackendStatus?) {
        let completion: ((TranscriptionBackendStatus?) -> Void)?
        lock.lock()
        completion = pendingCompletion
        pendingCompletion = nil
        lock.unlock()

        processManager.stop()
        completion?(status)
    }
}
