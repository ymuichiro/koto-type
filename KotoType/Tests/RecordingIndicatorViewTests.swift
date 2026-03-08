import XCTest
@testable import KotoType

final class RecordingIndicatorViewTests: XCTestCase {
    func testAttentionWithMessageUsesWiderSize() {
        let defaultSize = RecordingIndicatorView.preferredContentSize(for: .attention, attentionMessage: nil)
        let warningSize = RecordingIndicatorView.preferredContentSize(
            for: .attention,
            attentionMessage: "Microphone not detected"
        )

        XCTAssertGreaterThan(warningSize.width, defaultSize.width)
        XCTAssertEqual(warningSize.height, defaultSize.height)
    }
}
