import Combine
import Foundation
import Metal
import Darwin

enum EffectiveTranscriptionBackend: String, Codable, Sendable {
    case cpu
    case mlx

    var displayName: String {
        switch self {
        case .cpu:
            return "CPU"
        case .mlx:
            return "Apple GPU (MLX)"
        }
    }

    var defaultWorkerCount: Int {
        switch self {
        case .cpu:
            return 2
        case .mlx:
            return 1
        }
    }
}

struct TranscriptionBackendStatus: Codable, Equatable, Sendable {
    let effectiveBackend: EffectiveTranscriptionBackend
    let gpuRequested: Bool
    let gpuAvailable: Bool
    let fallbackReason: String?
}

extension TranscriptionBackendStatus {
    var summaryText: String {
        if effectiveBackend == .mlx {
            return "Current backend: \(effectiveBackend.displayName)"
        }
        if let fallbackReason {
            return "Current backend: \(effectiveBackend.displayName) (\(fallbackReasonDescription(for: fallbackReason)))"
        }
        return "Current backend: \(effectiveBackend.displayName)"
    }

    var detailText: String? {
        guard let fallbackReason else {
            return gpuRequested
                ? nil
                : "GPU acceleration is turned off in Settings."
        }
        return fallbackDetail(for: fallbackReason)
    }

    private func fallbackReasonDescription(for reason: String) -> String {
        switch reason {
        case "gpu_disabled_in_settings":
            return "GPU off"
        case "gpu_not_supported_on_host":
            return "GPU unavailable"
        case "mlx_runtime_import_failed":
            return "MLX runtime unavailable"
        case "mlx_model_load_failed":
            return "MLX model load failed"
        case "mlx_transcription_failed":
            return "MLX transcription failed"
        case "mlx_disabled_for_session":
            return "MLX disabled for this session"
        default:
            return reason.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func fallbackDetail(for reason: String) -> String? {
        switch reason {
        case "gpu_disabled_in_settings":
            return "GPU acceleration is turned off in Settings."
        case "gpu_not_supported_on_host":
            return "This Mac does not support MLX acceleration."
        case "mlx_runtime_import_failed":
            return "The bundled MLX runtime is unavailable, so KotoType is using the CPU."
        case "mlx_model_load_failed":
            return "The MLX model could not be loaded, so KotoType is using the CPU for this app session."
        case "mlx_transcription_failed":
            return "MLX transcription failed once and was disabled for the rest of this app session."
        case "mlx_disabled_for_session":
            return "MLX was disabled after a previous failure in this app session."
        default:
            return nil
        }
    }
}

@MainActor
final class TranscriptionBackendStatusStore: ObservableObject {
    static let shared = TranscriptionBackendStatusStore()

    @Published private(set) var currentStatus: TranscriptionBackendStatus?

    private init() {}

    nonisolated static func publishFromAnyThread(_ status: TranscriptionBackendStatus) {
        Task { @MainActor in
            shared.currentStatus = status
            NotificationCenter.default.post(
                name: .transcriptionBackendStatusChanged,
                object: status
            )
        }
    }

    nonisolated func publish(_ status: TranscriptionBackendStatus) {
        Task { @MainActor in
            self.currentStatus = status
            NotificationCenter.default.post(
                name: .transcriptionBackendStatusChanged,
                object: status
            )
        }
    }
}

enum TranscriptionRuntimeSupport {
    static func supportsGPUAcceleration(
        isAppleSilicon: Bool = isRunningOnAppleSilicon(),
        hasMetalDevice: Bool = MTLCreateSystemDefaultDevice() != nil
    ) -> Bool {
        isAppleSilicon && hasMetalDevice
    }

    static func preferredBackend(
        settings: AppSettings,
        latestStatus: TranscriptionBackendStatus?
    ) -> EffectiveTranscriptionBackend {
        if let latestStatus, latestStatus.gpuRequested == settings.gpuAccelerationEnabled {
            return latestStatus.effectiveBackend
        }
        if settings.gpuAccelerationEnabled && supportsGPUAcceleration() {
            return .mlx
        }
        return .cpu
    }

    private static func isRunningOnAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}

extension Notification.Name {
    static let transcriptionBackendStatusChanged = Notification.Name(
        "transcriptionBackendStatusChanged"
    )
}
