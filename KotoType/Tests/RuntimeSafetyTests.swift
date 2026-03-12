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
