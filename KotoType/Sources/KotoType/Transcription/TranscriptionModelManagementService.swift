import Foundation

protocol PythonModelManaging: AnyObject {
    var outputReceived: ((String) -> Void)? { get set }
    var processTerminated: ((Int32) -> Void)? { get set }

    func startPython(scriptPath: String)
    func sendModelManagement(
        action: ManagedTranscriptionModelAction,
        modelKind: ManagedTranscriptionModelKind?,
        requestID: UInt64
    ) -> Bool
    func isRunning() -> Bool
    func stop()
}

extension PythonProcessManager: PythonModelManaging {}

final class TranscriptionModelManagementService: @unchecked Sendable {
    private enum PendingRequest {
        case models(id: UInt64, completion: ([ManagedTranscriptionModelStatus]) -> Void)
        case model(id: UInt64, completion: (ManagedTranscriptionModelStatus?) -> Void)
    }

    private let processManager: any PythonModelManaging
    private let scheduleTimeout: (TimeInterval, @escaping @Sendable () -> Void) -> Void
    private let lock = NSLock()

    private var scriptPath: String = ""
    private var pendingRequest: PendingRequest?
    private var nextRequestID: UInt64 = 0

    init(
        processManager: any PythonModelManaging = PythonProcessManager(),
        scheduleTimeout: @escaping (TimeInterval, @escaping @Sendable () -> Void) -> Void = { timeout, operation in
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + timeout,
                execute: operation
            )
        }
    ) {
        self.processManager = processManager
        self.scheduleTimeout = scheduleTimeout
        processManager.outputReceived = { [weak self] output in
            self?.handleOutput(output)
        }
        processManager.processTerminated = { [weak self] _ in
            self?.finishPendingRequest()
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
        let currentScriptPath = lock.withLock {
            scriptPath
        }

        guard !currentScriptPath.isEmpty else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let requestID = lock.withLock { () -> UInt64? in
                guard pendingRequest == nil else {
                    return nil
                }

                nextRequestID &+= 1
                let requestID = nextRequestID
                switch pending {
                case .models:
                    pendingRequest = .models(id: requestID) { models in
                        continuation.resume(returning: .models(models))
                    }
                case .model:
                    pendingRequest = .model(id: requestID) { model in
                        continuation.resume(returning: .model(model))
                    }
                }
                return requestID
            }

            guard let requestID else {
                continuation.resume(returning: nil)
                return
            }

            if !processManager.isRunning() {
                processManager.startPython(scriptPath: currentScriptPath)
            }
            guard processManager.isRunning() else {
                switch pending {
                case .models:
                    finishModels([], requestID: requestID)
                case .model:
                    finishModel(nil, requestID: requestID)
                }
                return
            }

            let sent = processManager.sendModelManagement(
                action: action,
                modelKind: modelKind,
                requestID: requestID
            )
            guard sent else {
                switch pending {
                case .models:
                    finishModels([], requestID: requestID)
                case .model:
                    finishModel(nil, requestID: requestID)
                }
                return
            }

            scheduleTimeout(timeout) { [weak self] in
                guard let self else { return }
                switch pending {
                case .models:
                    self.finishModels([], requestID: requestID)
                case .model:
                    self.finishModel(nil, requestID: requestID)
                }
            }
        }
    }

    private func handleOutput(_ output: String) {
        if let response = PythonProcessManager.parseManagedModelsResponse(from: output),
           response.type == "managed_models" {
            guard let requestID = response.requestID else {
                Logger.shared.log(
                    "Ignoring model list response without request_id",
                    level: .warning
                )
                return
            }
            finishModels(response.models, requestID: requestID)
            return
        }

        if let response = PythonProcessManager.parseManagedModelResponse(from: output),
           response.type == "managed_model" {
            guard let requestID = response.requestID else {
                Logger.shared.log(
                    "Ignoring model response without request_id",
                    level: .warning
                )
                return
            }
            finishModel(response.model, requestID: requestID)
        }
    }

    private func finishPendingRequest() {
        let request = lock.withLock {
            let current = pendingRequest
            pendingRequest = nil
            return current
        }

        guard let request else { return }
        switch request {
        case let .models(_, completion):
            completion([])
        case let .model(_, completion):
            completion(nil)
        }
    }

    private func finishModels(
        _ models: [ManagedTranscriptionModelStatus],
        requestID: UInt64
    ) {
        let request = lock.withLock {
            let current = pendingRequest
            if case let .models(id, _) = current,
               requestID == id {
                pendingRequest = nil
                return current
            }
            return nil
        }

        guard let request else { return }
        processManager.stop()
        if case let .models(_, completion) = request {
            completion(models)
        }
    }

    private func finishModel(
        _ model: ManagedTranscriptionModelStatus?,
        requestID: UInt64
    ) {
        let request = lock.withLock {
            let current = pendingRequest
            if case let .model(id, _) = current,
               requestID == id {
                pendingRequest = nil
                return current
            }
            return nil
        }

        guard let request else { return }
        processManager.stop()
        if case let .model(_, completion) = request {
            completion(model)
        }
    }
}
