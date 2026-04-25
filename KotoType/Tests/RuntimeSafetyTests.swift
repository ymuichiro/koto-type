import Dispatch
import XCTest
@testable import KotoType

final class RuntimeSafetyTests: XCTestCase {
    func testResolvedWorkerCountKeepsRequestedForAppBundle() {
        XCTAssertEqual(
            AppDelegate.resolvedWorkerCount(
                requested: 4,
                bundlePath: "/Applications/KotoType.app"
            ),
            4
        )
    }

    func testResolvedWorkerCountKeepsRequestedForDevelopmentRuntime() {
        XCTAssertEqual(
            AppDelegate.resolvedWorkerCount(
                requested: 3,
                bundlePath: "/tmp/koto-type/.build/debug/KotoType"
            ),
            3
        )
    }

    func testResolvedWorkerCountHasMinimumOfOne() {
        XCTAssertEqual(
            AppDelegate.resolvedWorkerCount(
                requested: 0,
                bundlePath: "/tmp/koto-type/.build/debug/KotoType"
            ),
            1
        )
    }

    func testBackendServerLimitsFollowDevelopmentWorkerCount() {
        let limits = AppDelegate.backendServerLimits(
            requestedWorkers: 3,
            bundlePath: "/tmp/koto-type/.build/debug/KotoType"
        )
        XCTAssertEqual(limits.maxActiveServers, 3)
        XCTAssertEqual(limits.maxParallelModelLoads, 1)
    }

    func testBackendServerLimitsMatchRequestedWorkersForAppBundle() {
        let limits = AppDelegate.backendServerLimits(
            requestedWorkers: 4,
            bundlePath: "/Applications/KotoType.app"
        )
        XCTAssertEqual(limits.maxActiveServers, 4)
        XCTAssertEqual(limits.maxParallelModelLoads, 1)
    }

    func testEffectiveBackendDefaultWorkerCountsMatchPresetStrategy() {
        XCTAssertEqual(EffectiveTranscriptionBackend.cpu.defaultWorkerCount, 2)
        XCTAssertEqual(EffectiveTranscriptionBackend.mlx.defaultWorkerCount, 1)
    }

    func testSupportsGPUAccelerationRequiresAppleSiliconAndMetal() {
        XCTAssertTrue(
            TranscriptionRuntimeSupport.supportsGPUAcceleration(
                isAppleSilicon: true,
                hasMetalDevice: true
            )
        )
        XCTAssertFalse(
            TranscriptionRuntimeSupport.supportsGPUAcceleration(
                isAppleSilicon: false,
                hasMetalDevice: true
            )
        )
        XCTAssertFalse(
            TranscriptionRuntimeSupport.supportsGPUAcceleration(
                isAppleSilicon: true,
                hasMetalDevice: false
            )
        )
    }

    func testPreferredBackendUsesLatestStatusWhenToggleMatches() {
        let settings = AppSettings(gpuAccelerationEnabled: true)
        let latestStatus = TranscriptionBackendStatus(
            effectiveBackend: .cpu,
            gpuRequested: true,
            gpuAvailable: false,
            fallbackReason: "mlx_runtime_import_failed"
        )

        XCTAssertEqual(
            TranscriptionRuntimeSupport.preferredBackend(
                settings: settings,
                latestStatus: latestStatus
            ),
            .cpu
        )
    }

    func testPreferredBackendReturnsCPUWhenGPUIsDisabled() {
        XCTAssertEqual(
            TranscriptionRuntimeSupport.preferredBackend(
                settings: AppSettings(gpuAccelerationEnabled: false),
                latestStatus: nil
            ),
            .cpu
        )
    }

    func testLaunchAtLoginManagementAllowsInstalledApplicationsBundle() {
        XCTAssertTrue(
            LaunchAtLoginManager.canManageLaunchAtLogin(
                bundlePath: "/Applications/KotoType.app"
            )
        )
    }

    func testLaunchAtLoginManagementAllowsInstalledApplicationsExecutablePath() {
        XCTAssertTrue(
            LaunchAtLoginManager.canManageLaunchAtLogin(
                bundlePath: "/Applications/KotoType.app/Contents/MacOS/KotoType"
            )
        )
    }

    func testLaunchAtLoginManagementAllowsUserApplicationsBundle() {
        XCTAssertTrue(
            LaunchAtLoginManager.canManageLaunchAtLogin(
                bundlePath: "\(NSHomeDirectory())/Applications/KotoType.app"
            )
        )
    }

    func testLaunchAtLoginManagementRejectsRepositoryBundle() {
        XCTAssertFalse(
            LaunchAtLoginManager.canManageLaunchAtLogin(
                bundlePath: "/Users/example/src/koto-type/KotoType/KotoType.app"
            )
        )
    }

    func testLaunchAtLoginManagementRejectsRepositoryBundleExecutablePath() {
        XCTAssertFalse(
            LaunchAtLoginManager.canManageLaunchAtLogin(
                bundlePath: "/Users/example/src/koto-type/KotoType/KotoType.app/Contents/MacOS/KotoType"
            )
        )
    }

    func testLaunchAtLoginManagementRejectsDevelopmentExecutable() {
        XCTAssertFalse(
            LaunchAtLoginManager.canManageLaunchAtLogin(
                bundlePath: "/tmp/koto-type/.build/debug/KotoType"
            )
        )
    }

    func testShouldAutoRecoverIdleTerminationDisablesSigKill() {
        XCTAssertFalse(MultiProcessManager.shouldAutoRecoverIdleTermination(status: 9))
    }

    func testShouldAutoRecoverIdleTerminationDisablesStatus0() {
        XCTAssertFalse(MultiProcessManager.shouldAutoRecoverIdleTermination(status: 0))
    }

    func testShouldAutoRecoverIdleTerminationAllowsRecoverableStatuses() {
        XCTAssertTrue(MultiProcessManager.shouldAutoRecoverIdleTermination(status: 1))
        XCTAssertTrue(MultiProcessManager.shouldAutoRecoverIdleTermination(status: 15))
    }

    @MainActor
    func testMainActorDispatchHandlerCapturesQueueStateBeforeHoppingToMainActor() async {
        let expectation = expectation(description: "main actor handler executed")
        var captureWasOnMainThread: Bool?
        var operationWasOnMainThread = false

        let handler = AppDelegate.makeMainActorDispatchHandler(capture: {
            Thread.isMainThread
        }) { wasOnMainThread in
            captureWasOnMainThread = wasOnMainThread
            operationWasOnMainThread = Thread.isMainThread
            expectation.fulfill()
        }

        DispatchQueue.global(qos: .utility).async(execute: handler)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(captureWasOnMainThread, false)
        XCTAssertTrue(operationWasOnMainThread)
    }
}
