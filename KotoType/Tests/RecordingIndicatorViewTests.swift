import XCTest
@testable import KotoType

@MainActor
final class RecordingIndicatorViewTests: XCTestCase {
    func testRecordingPreferredWidthExpandedForVisibility() {
        let size = RecordingIndicatorView.preferredContentSize(for: .recording, attentionMessage: nil)
        XCTAssertEqual(size.width, 380, accuracy: 0.001)
    }

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
