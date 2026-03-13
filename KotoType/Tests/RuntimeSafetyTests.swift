import XCTest
@testable import KotoType

final class RuntimeSafetyTests: XCTestCase {
    func testResolvedWorkerCountClampsToOneForAppBundle() {
        XCTAssertEqual(
            AppDelegate.resolvedWorkerCount(
                requested: 4,
                bundlePath: "/Applications/KotoType.app"
            ),
            1
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

    func testBackendServerLimitsClampToOneForAppBundle() {
        let limits = AppDelegate.backendServerLimits(
            requestedWorkers: 4,
            bundlePath: "/Applications/KotoType.app"
        )
        XCTAssertEqual(limits.maxActiveServers, 1)
        XCTAssertEqual(limits.maxParallelModelLoads, 1)
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
}
