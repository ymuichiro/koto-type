@testable import KotoType
import XCTest

final class PermissionResetStateManagerTests: XCTestCase {
    func testMarkResetAttemptPersistsTokenAndCommand() {
        let defaults = UserDefaults(suiteName: "PermissionResetStateManagerTests-\(UUID().uuidString)")!
        let manager = PermissionResetStateManager(defaults: defaults)

        manager.markResetAttempt(
            for: "installation-token",
            command: "/usr/bin/tccutil reset All com.ymuichiro.kototype"
        )

        XCTAssertTrue(manager.hasAttemptedReset(for: "installation-token"))
        XCTAssertEqual(manager.lastResetCommand, "/usr/bin/tccutil reset All com.ymuichiro.kototype")
    }

    func testClearResetAttemptRemovesStoredState() {
        let defaults = UserDefaults(suiteName: "PermissionResetStateManagerTests-\(UUID().uuidString)")!
        let manager = PermissionResetStateManager(defaults: defaults)

        manager.markResetAttempt(
            for: "installation-token",
            command: "/usr/bin/tccutil reset All com.ymuichiro.kototype"
        )
        manager.clearResetAttempt()

        XCTAssertFalse(manager.hasAttemptedReset(for: "installation-token"))
        XCTAssertNil(manager.lastResetCommand)
    }
}
