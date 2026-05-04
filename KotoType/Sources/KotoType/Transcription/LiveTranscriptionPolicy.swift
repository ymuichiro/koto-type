import Foundation

struct LiveTranscriptionPolicy: Equatable {
    enum Mode: String, Equatable {
        case cpuSafe = "cpu-safe"
        case mlxConfirmed = "mlx-confirmed"
    }

    static let cpuSafeRecordingMaxDuration: TimeInterval = 60
    static let mlxRecordingMaxDuration: TimeInterval = 600
    static let cpuSafeProcessingTimeout: TimeInterval = 600
    static let mlxProcessingTimeout: TimeInterval = 3_600

    let mode: Mode
    let recordingMaxDuration: TimeInterval
    let processingTimeout: TimeInterval
    let finalizationTimeout: TimeInterval
    let effectiveBackend: EffectiveTranscriptionBackend
    let logReason: String

    var autoStopMessage: String {
        switch mode {
        case .cpuSafe:
            return "CPU transcription is limited to 1 minute."
        case .mlxConfirmed:
            return "MLX transcription is limited to 10 minutes."
        }
    }

    static func resolve(
        settings: AppSettings,
        latestStatus: TranscriptionBackendStatus?
    ) -> LiveTranscriptionPolicy {
        if settings.gpuAccelerationEnabled,
           let latestStatus,
           latestStatus.gpuRequested == settings.gpuAccelerationEnabled,
           latestStatus.effectiveBackend == .mlx,
           latestStatus.gpuAvailable,
           latestStatus.fallbackReason == nil {
            return LiveTranscriptionPolicy(
                mode: .mlxConfirmed,
                recordingMaxDuration: mlxRecordingMaxDuration,
                processingTimeout: mlxProcessingTimeout,
                finalizationTimeout: min(
                    max(settings.recordingCompletionTimeout, mlxProcessingTimeout),
                    AppSettings.maximumRecordingCompletionTimeout
                ),
                effectiveBackend: .mlx,
                logReason: "confirmed_mlx"
            )
        }

        let logReason: String
        if !settings.gpuAccelerationEnabled {
            logReason = "gpu_disabled_in_settings"
        } else if let latestStatus {
            if latestStatus.gpuRequested != settings.gpuAccelerationEnabled {
                logReason = "backend_status_stale"
            } else if let fallbackReason = latestStatus.fallbackReason {
                logReason = fallbackReason
            } else if !latestStatus.gpuAvailable {
                logReason = "gpu_unavailable"
            } else {
                logReason = "cpu_backend_selected"
            }
        } else {
            logReason = "backend_status_unknown"
        }

        return LiveTranscriptionPolicy(
            mode: .cpuSafe,
            recordingMaxDuration: cpuSafeRecordingMaxDuration,
            processingTimeout: cpuSafeProcessingTimeout,
            finalizationTimeout: min(
                max(settings.recordingCompletionTimeout, cpuSafeProcessingTimeout),
                AppSettings.maximumRecordingCompletionTimeout
            ),
            effectiveBackend: .cpu,
            logReason: logReason
        )
    }
}
