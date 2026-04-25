import AppKit
import ScriptingBridge

final class KeystrokeSimulator {
    private struct PendingPasteboardRestore {
        let generation: UInt64
        let snapshot: PasteboardSnapshot
        let expectedChangeCount: Int
    }

    private static let pasteboardRestoreDelay: TimeInterval = 0.15
    private static let pasteboardRestoreLock = NSLock()
    nonisolated(unsafe) private static var pendingPasteboardRestore: PendingPasteboardRestore?
    nonisolated(unsafe) private static var nextPasteboardRestoreGeneration: UInt64 = 0

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
            let serializedItems = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { partialResult, type in
                    guard let data = item.data(forType: type) else {
                        return
                    }
                    partialResult[type] = data
                }
            }
            return PasteboardSnapshot(items: serializedItems)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else {
                return
            }
            let restoredItems = items.map { serializedItem -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in serializedItem {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.writeObjects(restoredItems)
        }
    }
    
    static func typeText(_ text: String) {
        Logger.shared.log("KeystrokeSimulator: typeText called with text length: \(text.count)", level: .debug)

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotForNextPasteboardOperation(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let transientChangeCount = pasteboard.changeCount
        Logger.shared.log("KeystrokeSimulator: text set to pasteboard", level: .debug)
        let restoreGeneration = registerPendingPasteboardRestore(
            snapshot: snapshot,
            expectedChangeCount: transientChangeCount
        )

        let source = CGEventSource(stateID: .combinedSessionState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        
        cmdDown?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        vDown?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        vUp?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        cmdUp?.post(tap: .cgSessionEventTap)
        schedulePasteboardRestore(generation: restoreGeneration)

        Logger.shared.log("KeystrokeSimulator: Cmd+V executed via CGEvent", level: .info)
    }

    private static func snapshotForNextPasteboardOperation(
        from pasteboard: NSPasteboard
    ) -> PasteboardSnapshot {
        pasteboardRestoreLock.lock()
        if let pendingPasteboardRestore,
           pasteboard.changeCount == pendingPasteboardRestore.expectedChangeCount {
            let snapshot = pendingPasteboardRestore.snapshot
            pasteboardRestoreLock.unlock()
            return snapshot
        }
        pendingPasteboardRestore = nil
        pasteboardRestoreLock.unlock()
        return PasteboardSnapshot.capture(from: pasteboard)
    }

    private static func registerPendingPasteboardRestore(
        snapshot: PasteboardSnapshot,
        expectedChangeCount: Int
    ) -> UInt64 {
        pasteboardRestoreLock.lock()
        nextPasteboardRestoreGeneration += 1
        let generation = nextPasteboardRestoreGeneration
        pendingPasteboardRestore = PendingPasteboardRestore(
            generation: generation,
            snapshot: snapshot,
            expectedChangeCount: expectedChangeCount
        )
        pasteboardRestoreLock.unlock()
        return generation
    }

    private static func schedulePasteboardRestore(
        generation: UInt64
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteboardRestoreDelay) {
            restorePasteboardIfNeeded(generation: generation)
        }
    }

    private static func restorePasteboardIfNeeded(
        generation: UInt64
    ) {
        pasteboardRestoreLock.lock()
        guard let pendingPasteboardRestore,
              pendingPasteboardRestore.generation == generation else {
            pasteboardRestoreLock.unlock()
            return
        }
        self.pendingPasteboardRestore = nil
        pasteboardRestoreLock.unlock()

        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == pendingPasteboardRestore.expectedChangeCount {
            pendingPasteboardRestore.snapshot.restore(to: pasteboard)
            Logger.shared.log("KeystrokeSimulator: restored previous pasteboard contents", level: .debug)
        } else {
            Logger.shared.log(
                "KeystrokeSimulator: pasteboard changed externally before restore; leaving current contents intact",
                level: .debug
            )
        }
    }
}
