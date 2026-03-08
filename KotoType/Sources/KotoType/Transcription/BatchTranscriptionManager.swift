import Foundation

final class BatchTranscriptionManager: @unchecked Sendable {
    private var pendingSegments: [Segment] = []
    private var completedSegments: [Segment?] = []
    private var lock = NSLock()
    
    func addSegment(url: URL, index: Int) {
        Logger.shared.log("BatchTranscriptionManager: addSegment called - url=\(url.path), index=\(index)", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        let segment = Segment(url: url, index: index)
        pendingSegments.append(segment)
        
        ensureArrayCapacity(index: index)
        
        Logger.shared.log("BatchTranscriptionManager: segment added - pending=\(pendingSegments.count)", level: .debug)
    }
    
    func completeSegment(index: Int, text: String) {
        Logger.shared.log("BatchTranscriptionManager: completeSegment called - index=\(index), text='\(text)'", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        ensureArrayCapacity(index: index)
        completedSegments[index] = Segment(url: URL(fileURLWithPath: ""), index: index, text: text)
        Logger.shared.log("BatchTranscriptionManager: segment completed - index=\(index)", level: .debug)
    }
    
    func finalize() -> String? {
        Logger.shared.log("BatchTranscriptionManager: finalize called", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        let combined = combineSegments()
        
        if !combined.isEmpty {
            Logger.shared.log("BatchTranscriptionManager: final transcription: '\(combined)'", level: .info)
            return combined
        } else {
            Logger.shared.log("BatchTranscriptionManager: no transcriptions to finalize", level: .warning)
            return nil
        }
    }
    
    private func ensureArrayCapacity(index: Int) {
        if index >= completedSegments.count {
            completedSegments.append(contentsOf: repeatElement(nil, count: index - completedSegments.count + 1))
        }
    }
    
    private func combineSegments() -> String {
        let segments = completedSegments.enumerated().compactMap { entry -> (Int, String)? in
            guard let segment = entry.element, let text = segment.text else {
                return nil
            }
            return (entry.offset, text)
        }
        let combined = segments.map { $0.1 }.joined(separator: "")
        Logger.shared.log("BatchTranscriptionManager: combining \(segments.count) segments", level: .debug)
        return combined
    }
    
    func isComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return pendingSegments.allSatisfy { pending in
            pending.index < completedSegments.count &&
                completedSegments[pending.index]?.text != nil
        }
    }
    
    func reset() {
        Logger.shared.log("BatchTranscriptionManager: reset called", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        pendingSegments.removeAll()
        completedSegments.removeAll()
    }
}

struct Segment {
    let url: URL
    let index: Int
    var text: String?
}
