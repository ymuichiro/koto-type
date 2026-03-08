import Foundation

struct RecordingSegmentRoute: Equatable {
    let sessionID: Int
    let localIndex: Int
}

struct RecordingSegmentRouter {
    private(set) var nextGlobalIndex = 0
    private var routeByGlobalIndex: [Int: RecordingSegmentRoute] = [:]

    mutating func register(sessionID: Int, localIndex: Int) -> Int {
        let globalIndex = nextGlobalIndex
        nextGlobalIndex += 1
        routeByGlobalIndex[globalIndex] = RecordingSegmentRoute(sessionID: sessionID, localIndex: localIndex)
        return globalIndex
    }

    mutating func consume(globalIndex: Int) -> RecordingSegmentRoute? {
        routeByGlobalIndex.removeValue(forKey: globalIndex)
    }

    mutating func removeAll(forSessionID sessionID: Int) -> [Int] {
        let indices = routeByGlobalIndex.compactMap { globalIndex, route in
            route.sessionID == sessionID ? globalIndex : nil
        }.sorted()

        for globalIndex in indices {
            routeByGlobalIndex.removeValue(forKey: globalIndex)
        }

        return indices
    }

    mutating func reset() {
        routeByGlobalIndex.removeAll()
        nextGlobalIndex = 0
    }
}

private struct RecordingFinalizationStatus {
    var isReady = false
    var hasTimedOut = false
}

struct RecordingFinalizationQueue {
    private var pendingSessionIDs: [Int] = []
    private var statusBySessionID: [Int: RecordingFinalizationStatus] = [:]

    var nextPendingSessionID: Int? {
        pendingSessionIDs.first
    }

    var isEmpty: Bool {
        pendingSessionIDs.isEmpty
    }

    var liveIndicatorFallbackSessionID: Int? {
        pendingSessionIDs.last
    }

    mutating func enqueue(sessionID: Int) {
        if !pendingSessionIDs.contains(sessionID) {
            pendingSessionIDs.append(sessionID)
        }
        statusBySessionID[sessionID] = RecordingFinalizationStatus()
    }

    mutating func markReady(sessionID: Int) {
        guard var status = statusBySessionID[sessionID] else {
            return
        }
        status.isReady = true
        statusBySessionID[sessionID] = status
    }

    mutating func markTimedOut(sessionID: Int) {
        guard var status = statusBySessionID[sessionID] else {
            return
        }
        status.hasTimedOut = true
        statusBySessionID[sessionID] = status
    }

    func canFinalize(sessionID: Int, isComplete: Bool) -> Bool {
        guard let status = statusBySessionID[sessionID] else {
            return false
        }

        return (status.isReady && isComplete) || status.hasTimedOut
    }

    mutating func remove(sessionID: Int) {
        pendingSessionIDs.removeAll { $0 == sessionID }
        statusBySessionID.removeValue(forKey: sessionID)
    }

    mutating func reset() {
        pendingSessionIDs.removeAll()
        statusBySessionID.removeAll()
    }
}

struct IndicatorPresentationState {
    private(set) var currentLiveSessionID: Int?
    private(set) var generation = 0

    @discardableResult
    mutating func beginLiveSession(_ sessionID: Int) -> Int {
        generation += 1
        currentLiveSessionID = sessionID
        return generation
    }

    @discardableResult
    mutating func beginNonLivePresentation() -> Int {
        generation += 1
        currentLiveSessionID = nil
        return generation
    }

    mutating func setFallbackLiveSession(_ sessionID: Int?) {
        currentLiveSessionID = sessionID
    }

    func canHideCompletedSession(
        sessionID: Int,
        token: Int,
        isRecording: Bool,
        isImportingAudio: Bool
    ) -> Bool {
        token == generation &&
            currentLiveSessionID == sessionID &&
            !isRecording &&
            !isImportingAudio
    }

    mutating func didHideCompletedSession(sessionID: Int, fallbackSessionID: Int?) {
        guard currentLiveSessionID == sessionID else {
            return
        }
        currentLiveSessionID = fallbackSessionID
    }

    mutating func reset() {
        generation += 1
        currentLiveSessionID = nil
    }
}
