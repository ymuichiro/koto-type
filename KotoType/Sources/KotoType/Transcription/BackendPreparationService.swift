import Combine
import Foundation

struct BackendPreparationProgress: Codable, Equatable, Sendable {
    enum Step: String, Codable, Sendable {
        case starting
        case probingGPU = "probing_gpu"
        case importingMLXRuntime = "importing_mlx_runtime"
        case preparingMLXModel = "preparing_mlx_model"
        case checkingMLXModelAssets = "checking_mlx_model_assets"
        case downloadingMLXModel = "downloading_mlx_model"
        case loadingMLXModel = "loading_mlx_model"
        case fallbackToCPU = "fallback_to_cpu"
        case preparingCPUModel = "preparing_cpu_model"
        case checkingCPUModelAssets = "checking_cpu_model_assets"
        case downloadingCPUModel = "downloading_cpu_model"
        case loadingCPUModel = "loading_cpu_model"
    }

    let type: String
    let step: Step
    let detail: String?

    init(
        step: Step,
        detail: String? = nil,
        type: String = "backend_preparation_progress"
    ) {
        self.type = type
        self.step = step
        self.detail = detail
    }

    var displayTitle: String {
        switch step {
        case .starting:
            return "Starting transcription backend"
        case .probingGPU:
            return "Checking GPU support"
        case .importingMLXRuntime:
            return "Loading Apple GPU runtime"
        case .preparingMLXModel:
            return "Preparing Apple GPU model"
        case .checkingMLXModelAssets:
            return "Checking Apple GPU model files"
        case .downloadingMLXModel:
            return "Downloading Apple GPU model"
        case .loadingMLXModel:
            return "Loading Apple GPU model"
        case .fallbackToCPU:
            return "Switching to CPU model"
        case .preparingCPUModel:
            return "Preparing CPU model"
        case .checkingCPUModelAssets:
            return "Checking CPU model files"
        case .downloadingCPUModel:
            return "Downloading CPU model"
        case .loadingCPUModel:
            return "Loading CPU model"
        }
    }

    var displayMessage: String {
        if let detail, !detail.isEmpty {
            return detail
        }

        switch step {
        case .starting:
            return "Launching the transcription backend for first-time setup."
        case .probingGPU:
            return "Detecting whether Apple GPU acceleration is available on this Mac."
        case .importingMLXRuntime:
            return "Loading the MLX runtime components needed to use Apple GPU transcription."
        case .preparingMLXModel:
            return "Getting the Apple GPU transcription model ready."
        case .checkingMLXModelAssets:
            return "Looking for the local Apple GPU model so it does not need to be downloaded again."
        case .downloadingMLXModel:
            return "Downloading the Apple GPU transcription model. This can take a while on first launch."
        case .loadingMLXModel:
            return "Loading the Apple GPU model into memory."
        case .fallbackToCPU:
            return "Apple GPU preparation failed, so KotoType is falling back to the CPU model."
        case .preparingCPUModel:
            return "Getting the CPU transcription model ready."
        case .checkingCPUModelAssets:
            return "Looking for the local CPU model so it does not need to be downloaded again."
        case .downloadingCPUModel:
            return "Downloading the CPU transcription model. This can take a while on first launch."
        case .loadingCPUModel:
            return "Loading the CPU model into memory."
        }
    }
}

@MainActor
final class BackendPreparationProgressStore: ObservableObject {
    static let shared = BackendPreparationProgressStore()

    @Published private(set) var currentProgress = BackendPreparationProgress(step: .starting)

    private init() {}

    func reset() {
        currentProgress = BackendPreparationProgress(step: .starting)
    }

    nonisolated static func publishFromAnyThread(_ progress: BackendPreparationProgress) {
        Task { @MainActor in
            shared.currentProgress = progress
        }
    }
}

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
        if let progress = PythonProcessManager.parseBackendPreparationProgress(from: output) {
            BackendPreparationProgressStore.publishFromAnyThread(progress)
            return
        }
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
