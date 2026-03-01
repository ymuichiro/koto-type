import Foundation

struct RecordingProgressState {
    private(set) var combinedText: String = ""
    private(set) var lastEmitAt: Date?

    let maxDisplayLength: Int
    let throttleInterval: TimeInterval

    init(maxDisplayLength: Int = 120, throttleInterval: TimeInterval = 0.3) {
        self.maxDisplayLength = max(1, maxDisplayLength)
        self.throttleInterval = max(0, throttleInterval)
    }

    mutating func reset() {
        combinedText = ""
        lastEmitAt = nil
    }

    mutating func append(chunk: String) -> Bool {
        guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        combinedText.append(chunk)
        return true
    }

    mutating func shouldEmit(now: Date = Date()) -> Bool {
        guard displayText != nil else {
            return false
        }

        if let lastEmitAt, now.timeIntervalSince(lastEmitAt) < throttleInterval {
            return false
        }

        self.lastEmitAt = now
        return true
    }

    func nextDelay(now: Date = Date()) -> TimeInterval {
        guard let lastEmitAt else {
            return 0
        }

        return max(0, throttleInterval - now.timeIntervalSince(lastEmitAt))
    }

    var displayText: String? {
        let normalized = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        guard normalized.count > maxDisplayLength else {
            return normalized
        }

        return String(normalized.suffix(maxDisplayLength))
    }
}
