@testable import STTApp
import XCTest

final class InitialSetupStateManagerTests: XCTestCase {
    func testMarkCompletedPersistsFlag() {
        let defaults = UserDefaults(suiteName: "InitialSetupStateManagerTests-\(UUID().uuidString)")!
        let manager = InitialSetupStateManager(defaults: defaults)

        XCTAssertFalse(manager.hasCompletedInitialSetup)
        manager.markCompleted()
        XCTAssertTrue(manager.hasCompletedInitialSetup)
    }
}
