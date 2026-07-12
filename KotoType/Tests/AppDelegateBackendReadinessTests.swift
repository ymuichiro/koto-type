import XCTest
@testable import KotoType

final class AppDelegateBackendReadinessTests: XCTestCase {
    func testBackendPreparationIndicatorMessageUsesProgressTitle() {
        let message = AppDelegate.backendPreparationIndicatorMessage(
            progress: BackendPreparationProgress(step: .importingMLXRuntime)
        )

        XCTAssertEqual(message, "Loading Apple GPU runtime")
    }
}
