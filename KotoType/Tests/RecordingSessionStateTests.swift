import XCTest
@testable import KotoType

final class RecordingSessionStateTests: XCTestCase {
    func testSegmentRouterRemovesDestroyedSessionRoutes() {
        var router = RecordingSegmentRouter()

        let first = router.register(sessionID: 1, localIndex: 0)
        let second = router.register(sessionID: 1, localIndex: 1)
        let third = router.register(sessionID: 2, localIndex: 0)

        XCTAssertEqual(router.removeAll(forSessionID: 1), [first, second])
        XCTAssertNil(router.consume(globalIndex: first))
        XCTAssertNil(router.consume(globalIndex: second))
        XCTAssertEqual(
            router.consume(globalIndex: third),
            RecordingSegmentRoute(sessionID: 2, localIndex: 0)
        )
    }

    func testFinalizationQueueKeepsStopOrderUntilHeadSessionIsReady() {
        var queue = RecordingFinalizationQueue()

        queue.enqueue(sessionID: 1)
        queue.enqueue(sessionID: 2)
        queue.markReady(sessionID: 2)

        XCTAssertEqual(queue.nextPendingSessionID, 1)
        XCTAssertFalse(queue.canFinalize(sessionID: 1, isComplete: true))

        queue.markReady(sessionID: 1)

        XCTAssertTrue(queue.canFinalize(sessionID: 1, isComplete: true))
        queue.remove(sessionID: 1)
        XCTAssertEqual(queue.nextPendingSessionID, 2)
        XCTAssertTrue(queue.canFinalize(sessionID: 2, isComplete: true))
    }

    func testFinalizationQueueAllowsTimeoutFallback() {
        var queue = RecordingFinalizationQueue()

        queue.enqueue(sessionID: 3)
        queue.markTimedOut(sessionID: 3)

        XCTAssertTrue(queue.canFinalize(sessionID: 3, isComplete: false))
    }

    func testIndicatorPresentationInvalidatesOldHideTokenForNonLivePresentation() {
        var state = IndicatorPresentationState()
        let liveToken = state.beginLiveSession(7)

        state.beginNonLivePresentation()

        XCTAssertFalse(
            state.canHideCompletedSession(
                sessionID: 7,
                token: liveToken,
                isRecording: false,
                isImportingAudio: false
            )
        )
    }

    func testIndicatorPresentationTracksNewestLiveSession() {
        var state = IndicatorPresentationState()
        let staleToken = state.beginLiveSession(1)
        let currentToken = state.beginLiveSession(2)

        XCTAssertFalse(
            state.canHideCompletedSession(
                sessionID: 1,
                token: staleToken,
                isRecording: false,
                isImportingAudio: false
            )
        )
        XCTAssertTrue(
            state.canHideCompletedSession(
                sessionID: 2,
                token: currentToken,
                isRecording: false,
                isImportingAudio: false
            )
        )
    }
}
