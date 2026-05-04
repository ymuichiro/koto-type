import XCTest
@testable import KotoType

@MainActor
final class RecordingIndicatorViewTests: XCTestCase {
    func testRecordingPreferredWidthExpandedForVisibility() {
        let size = RecordingIndicatorView.preferredContentSize(for: .recording, attentionMessage: nil)
        XCTAssertEqual(size.width, 380, accuracy: 0.001)
    }

    func testRecordingWithInputDeviceNameUsesTallerLayout() {
        let unnamedSize = RecordingIndicatorView.preferredContentSize(for: .recording, attentionMessage: nil)
        let namedSize = RecordingIndicatorView.preferredContentSize(
            for: .recording,
            attentionMessage: nil,
            processingMessage: nil,
            recordingInputDeviceName: "MacBook Pro Microphone"
        )

        XCTAssertEqual(namedSize.width, unnamedSize.width)
        XCTAssertEqual(namedSize.height, unnamedSize.height)
        XCTAssertGreaterThan(
            unnamedSize.height,
            RecordingIndicatorView.preferredContentSize(for: .completed, attentionMessage: nil).height
        )
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

    func testProcessingWithMessageUsesCompactStatusWidth() {
        let defaultSize = RecordingIndicatorView.preferredContentSize(for: .processing, attentionMessage: nil)
        let waitingSize = RecordingIndicatorView.preferredContentSize(
            for: .processing,
            attentionMessage: nil,
            processingMessage: "Preparing backend..."
        )

        XCTAssertLessThan(waitingSize.width, defaultSize.width)
        XCTAssertEqual(waitingSize.height, defaultSize.height)
    }
}
