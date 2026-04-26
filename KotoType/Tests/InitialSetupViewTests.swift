@testable import KotoType
import XCTest

final class InitialSetupViewTests: XCTestCase {
    func testGuidedActionTitleAlwaysUsesGrantAccessibility() {
        XCTAssertEqual(InitialSetupView.guidedActionTitle(for: "accessibility"), "Grant Accessibility")
        XCTAssertEqual(InitialSetupView.guidedActionTitle(for: "microphone"), "Grant Accessibility")
        XCTAssertEqual(InitialSetupView.guidedActionTitle(for: "screenRecording"), "Grant Accessibility")
        XCTAssertEqual(InitialSetupView.guidedActionTitle(for: "ffmpeg"), "Grant Accessibility")
    }

    func testBackendPreparationProgressProvidesFriendlyFallbackCopy() {
        let progress = BackendPreparationProgress(step: .fallbackToCPU)

        XCTAssertEqual(progress.displayTitle, "Switching to CPU model")
        XCTAssertTrue(progress.displayMessage.contains("falling back to the CPU model"))
    }
}
