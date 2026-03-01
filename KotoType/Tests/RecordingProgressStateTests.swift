import XCTest
@testable import KotoType

final class RecordingProgressStateTests: XCTestCase {
    func testAppendIgnoresEmptyOrWhitespaceChunk() {
        var state = RecordingProgressState()

        XCTAssertFalse(state.append(chunk: ""))
        XCTAssertFalse(state.append(chunk: "   \n\t"))
        XCTAssertNil(state.displayText)
    }

    func testAppendUpdatesDisplayText() {
        var state = RecordingProgressState()

        XCTAssertTrue(state.append(chunk: "hello"))
        XCTAssertTrue(state.append(chunk: " world"))

        XCTAssertEqual(state.displayText, "hello world")
    }

    func testDisplayTextUsesTrailingSegmentWhenOverLimit() {
        var state = RecordingProgressState(maxDisplayLength: 5)
        XCTAssertTrue(state.append(chunk: "123456789"))

        XCTAssertEqual(state.displayText, "56789")
    }

    func testShouldEmitHonorsThrottleInterval() {
        var state = RecordingProgressState(throttleInterval: 0.3)
        XCTAssertTrue(state.append(chunk: "partial text"))

        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(state.shouldEmit(now: start))
        XCTAssertFalse(state.shouldEmit(now: start.addingTimeInterval(0.2)))
        XCTAssertEqual(state.nextDelay(now: start.addingTimeInterval(0.2)), 0.1, accuracy: 0.000_1)
        XCTAssertTrue(state.shouldEmit(now: start.addingTimeInterval(0.31)))
    }

    func testResetClearsState() {
        var state = RecordingProgressState()
        XCTAssertTrue(state.append(chunk: "something"))
        XCTAssertTrue(state.shouldEmit(now: Date(timeIntervalSince1970: 1)))

        state.reset()

        XCTAssertNil(state.displayText)
        XCTAssertEqual(state.nextDelay(now: Date(timeIntervalSince1970: 2)), 0)
        XCTAssertFalse(state.shouldEmit(now: Date(timeIntervalSince1970: 2)))
    }
}
