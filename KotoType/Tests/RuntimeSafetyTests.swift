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

    func testShouldAutoRecoverIdleTerminationDisablesSigKill() {
        XCTAssertFalse(MultiProcessManager.shouldAutoRecoverIdleTermination(status: 9))
    }

    func testShouldAutoRecoverIdleTerminationAllowsOtherStatuses() {
        XCTAssertTrue(MultiProcessManager.shouldAutoRecoverIdleTermination(status: 1))
        XCTAssertTrue(MultiProcessManager.shouldAutoRecoverIdleTermination(status: 15))
    }
}
