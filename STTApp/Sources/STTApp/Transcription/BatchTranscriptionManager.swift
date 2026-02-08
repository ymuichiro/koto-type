import Foundation

final class BatchTranscriptionManager: @unchecked Sendable {
    private var pendingSegments: [Segment] = []
    private var completedSegments: [Segment?] = []
    private var nextIndex = 0
    private var lock = NSLock()
    
    var onTranscriptionComplete: ((String) -> Void)?
    
    func addSegment(url: URL, index: Int) {
        Logger.shared.log("BatchTranscriptionManager: addSegment called - url=\(url.path), index=\(index)", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        let segment = Segment(url: url, index: index)
        pendingSegments.append(segment)
        
        ensureArrayCapacity(index: index)
        
        Logger.shared.log("BatchTranscriptionManager: segment added - pending=\(pendingSegments.count), nextIndex=\(nextIndex)", level: .debug)
    }
    
    func completeSegment(index: Int, text: String) {
        Logger.shared.log("BatchTranscriptionManager: completeSegment called - index=\(index), text='\(text)'", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        ensureArrayCapacity(index: index)
        completedSegments[index] = Segment(url: URL(fileURLWithPath: ""), index: index, text: text)
        
        if index == nextIndex {
            flushCompletedSegments()
        }
        
        Logger.shared.log("BatchTranscriptionManager: segment completed - index=\(index), nextIndex=\(nextIndex)", level: .debug)
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
    
    private func flushCompletedSegments() {
        var segmentsToCombine: [Segment] = []
        
        while nextIndex < completedSegments.count {
            if let segment = completedSegments[nextIndex] {
                segmentsToCombine.append(segment)
                nextIndex += 1
            } else {
                break
            }
        }
        
        if !segmentsToCombine.isEmpty {
            let combined = segmentsToCombine.compactMap { $0.text }.joined(separator: "")
            Logger.shared.log("BatchTranscriptionManager: flushing \(segmentsToCombine.count) segments: '\(combined)'", level: .info)
            
            DispatchQueue.main.async { [weak self] in
                self?.onTranscriptionComplete?(combined)
            }
        }
    }
    
    private func combineSegments() -> String {
        let segments = completedSegments.compactMap { $0 }
        let combined = segments.compactMap { $0.text }.joined(separator: "")
        Logger.shared.log("BatchTranscriptionManager: combining \(segments.count) segments", level: .debug)
        return combined
    }
    
    func isComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let allPendingCompleted = pendingSegments.allSatisfy { pending in
            completedIndices().contains(pending.index)
        }
        
        return allPendingCompleted && nextIndex == completedSegments.count
    }
    
    private func completedIndices() -> Set<Int> {
        var indices: Set<Int> = []
        for (i, segment) in completedSegments.enumerated() {
            if segment != nil && segment!.text != nil {
                indices.insert(i)
            }
        }
        return indices
    }
    
    func reset() {
        Logger.shared.log("BatchTranscriptionManager: reset called", level: .info)
        lock.lock()
        defer { lock.unlock() }
        
        pendingSegments.removeAll()
        completedSegments.removeAll()
        nextIndex = 0
    }
}

struct Segment {
    let url: URL
    let index: Int
    var text: String?
}
