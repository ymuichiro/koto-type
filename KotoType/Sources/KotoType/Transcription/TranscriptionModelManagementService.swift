import Foundation

protocol PythonModelManaging: AnyObject {
    var outputReceived: ((String) -> Void)? { get set }
    var processTerminated: ((Int32) -> Void)? { get set }

    func startPython(scriptPath: String)
    func sendModelManagement(
        action: ManagedTranscriptionModelAction,
        modelKind: ManagedTranscriptionModelKind?
    ) -> Bool
    func isRunning() -> Bool
    func stop()
}

extension PythonProcessManager: PythonModelManaging {}

final class TranscriptionModelManagementService: @unchecked Sendable {
    private enum PendingRequest {
        case models(([ManagedTranscriptionModelStatus]) -> Void)
        case model((ManagedTranscriptionModelStatus?) -> Void)
    }

    private let processManager: any PythonModelManaging
    private let lock = NSLock()

    private var scriptPath: String = ""
    private var pendingRequest: PendingRequest?

    init(processManager: any PythonModelManaging = PythonProcessManager()) {
        self.processManager = processManager
        processManager.outputReceived = { [weak self] output in
            self?.handleOutput(output)
        }
        processManager.processTerminated = { [weak self] _ in
            self?.finishModels([])
            self?.finishModel(nil)
        }
    }

    func configure(scriptPath: String) {
        lock.withLock {
            self.scriptPath = scriptPath
        }
    }

    func fetchStatuses(timeout: TimeInterval = 30) async -> [ManagedTranscriptionModelStatus] {
        let response = await execute(
            action: .statusAll,
            modelKind: nil,
            timeout: timeout,
            pending: .models
        )
        switch response {
        case let .models(models):
            return models
        case .model, .none:
            return []
        }
    }

    func downloadModel(
        _ kind: ManagedTranscriptionModelKind,
        timeout: TimeInterval = 600
    ) async -> ManagedTranscriptionModelStatus? {
        let response = await execute(
            action: .download,
            modelKind: kind,
            timeout: timeout,
            pending: .model
        )
        switch response {
        case let .model(model):
            return model
        case .models, .none:
            return nil
        }
    }

    func deleteModel(
        _ kind: ManagedTranscriptionModelKind,
        timeout: TimeInterval = 120
    ) async -> ManagedTranscriptionModelStatus? {
        let response = await execute(
            action: .delete,
            modelKind: kind,
            timeout: timeout,
            pending: .model
        )
        switch response {
        case let .model(model):
            return model
        case .models, .none:
            return nil
        }
    }

    private enum Response {
        case models([ManagedTranscriptionModelStatus])
        case model(ManagedTranscriptionModelStatus?)
    }

    private enum PendingKind {
        case models
        case model
    }

    private func execute(
        action: ManagedTranscriptionModelAction,
        modelKind: ManagedTranscriptionModelKind?,
        timeout: TimeInterval,
        pending: PendingKind
    ) async -> Response? {
        let (currentScriptPath, hasPendingRequest) = lock.withLock {
            (scriptPath, pendingRequest != nil)
        }

        guard !currentScriptPath.isEmpty, !hasPendingRequest else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            lock.withLock {
                switch pending {
                case .models:
                    pendingRequest = .models { models in
                        continuation.resume(returning: .models(models))
                    }
                case .model:
                    pendingRequest = .model { model in
                        continuation.resume(returning: .model(model))
                    }
                }
            }

            if !processManager.isRunning() {
                processManager.startPython(scriptPath: currentScriptPath)
            }
            guard processManager.isRunning() else {
                switch pending {
                case .models:
                    finishModels([])
                case .model:
                    finishModel(nil)
                }
                return
            }

            let sent = processManager.sendModelManagement(
                action: action,
                modelKind: modelKind
            )
            guard sent else {
                switch pending {
                case .models:
                    finishModels([])
                case .model:
                    finishModel(nil)
                }
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                switch pending {
                case .models:
                    self.finishModels([])
                case .model:
                    self.finishModel(nil)
                }
            }
        }
    }

    private func handleOutput(_ output: String) {
        if let response = PythonProcessManager.parseManagedModelsResponse(from: output),
           response.type == "managed_models" {
            finishModels(response.models)
            return
        }

        if let response = PythonProcessManager.parseManagedModelResponse(from: output),
           response.type == "managed_model" {
            finishModel(response.model)
        }
    }

    private func finishModels(_ models: [ManagedTranscriptionModelStatus]) {
        let request = lock.withLock {
            let current = pendingRequest
            if case .models = current {
                pendingRequest = nil
            }
            return current
        }

        guard let request else { return }
        processManager.stop()
        if case let .models(completion) = request {
            completion(models)
        }
    }

    private func finishModel(_ model: ManagedTranscriptionModelStatus?) {
        let request = lock.withLock {
            let current = pendingRequest
            if case .model = current {
                pendingRequest = nil
            }
            return current
        }

        guard let request else { return }
        processManager.stop()
        if case let .model(completion) = request {
            completion(model)
        }
    }
}
