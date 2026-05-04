@testable import KotoType
import XCTest

final class LiveTranscriptionPolicyTests: XCTestCase {
    func testConfirmedMLXUsesExtendedLimits() {
        let policy = LiveTranscriptionPolicy.resolve(
            settings: AppSettings(gpuAccelerationEnabled: true, recordingCompletionTimeout: 600),
            latestStatus: TranscriptionBackendStatus(
                effectiveBackend: .mlx,
                gpuRequested: true,
                gpuAvailable: true,
                fallbackReason: nil
            )
        )

        XCTAssertEqual(policy.mode, .mlxConfirmed)
        XCTAssertEqual(policy.recordingMaxDuration, 600)
        XCTAssertEqual(policy.processingTimeout, 3_600)
        XCTAssertEqual(policy.finalizationTimeout, 3_600)
    }

    func testGPUOffUsesCPUSafeLimits() {
        let policy = LiveTranscriptionPolicy.resolve(
            settings: AppSettings(gpuAccelerationEnabled: false, recordingCompletionTimeout: 600),
            latestStatus: TranscriptionBackendStatus(
                effectiveBackend: .cpu,
                gpuRequested: false,
                gpuAvailable: true,
                fallbackReason: "gpu_disabled_in_settings"
            )
        )

        XCTAssertEqual(policy.mode, .cpuSafe)
        XCTAssertEqual(policy.recordingMaxDuration, 60)
        XCTAssertEqual(policy.processingTimeout, 600)
        XCTAssertEqual(policy.finalizationTimeout, 600)
        XCTAssertEqual(policy.logReason, "gpu_disabled_in_settings")
    }

    func testUnavailableMLXUsesCPUSafeLimits() {
        let policy = LiveTranscriptionPolicy.resolve(
            settings: AppSettings(gpuAccelerationEnabled: true, recordingCompletionTimeout: 600),
            latestStatus: TranscriptionBackendStatus(
                effectiveBackend: .cpu,
                gpuRequested: true,
                gpuAvailable: false,
                fallbackReason: "mlx_runtime_import_failed"
            )
        )

        XCTAssertEqual(policy.mode, .cpuSafe)
        XCTAssertEqual(policy.recordingMaxDuration, 60)
        XCTAssertEqual(policy.processingTimeout, 600)
        XCTAssertEqual(policy.logReason, "mlx_runtime_import_failed")
    }

    func testUnknownBackendUsesCPUSafeLimits() {
        let policy = LiveTranscriptionPolicy.resolve(
            settings: AppSettings(gpuAccelerationEnabled: true, recordingCompletionTimeout: 600),
            latestStatus: nil
        )

        XCTAssertEqual(policy.mode, .cpuSafe)
        XCTAssertEqual(policy.recordingMaxDuration, 60)
        XCTAssertEqual(policy.processingTimeout, 600)
        XCTAssertEqual(policy.logReason, "backend_status_unknown")
    }

    func testFallbackStatusUsesCPUSafeLimits() {
        let policy = LiveTranscriptionPolicy.resolve(
            settings: AppSettings(gpuAccelerationEnabled: true, recordingCompletionTimeout: 600),
            latestStatus: TranscriptionBackendStatus(
                effectiveBackend: .cpu,
                gpuRequested: true,
                gpuAvailable: false,
                fallbackReason: "mlx_disabled_for_session"
            )
        )

        XCTAssertEqual(policy.mode, .cpuSafe)
        XCTAssertEqual(policy.recordingMaxDuration, 60)
        XCTAssertEqual(policy.processingTimeout, 600)
        XCTAssertEqual(policy.finalizationTimeout, 600)
        XCTAssertEqual(policy.logReason, "mlx_disabled_for_session")
    }

    func testUserConfiguredTimeoutCanExtendCPUFinalizationTimeout() {
        let policy = LiveTranscriptionPolicy.resolve(
            settings: AppSettings(gpuAccelerationEnabled: false, recordingCompletionTimeout: 1_800),
            latestStatus: nil
        )

        XCTAssertEqual(policy.mode, .cpuSafe)
        XCTAssertEqual(policy.processingTimeout, 600)
        XCTAssertEqual(policy.finalizationTimeout, 1_800)
    }
}
