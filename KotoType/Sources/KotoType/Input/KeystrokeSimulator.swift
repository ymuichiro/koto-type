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

    static func executeKeyCommand(_ command: HotkeyConfiguration) {
        guard command.keyCode > 0 else {
            Logger.shared.log(
                "KeystrokeSimulator: executeKeyCommand skipped because keyCode is missing",
                level: .warning
            )
            return
        }

        Logger.shared.log(
            "KeystrokeSimulator: executeKeyCommand called with keyCode=\(command.keyCode)",
            level: .debug
        )

        let source = CGEventSource(stateID: .combinedSessionState)
        let modifierSequence = orderedModifierSequence(for: command)
        var activeFlags: CGEventFlags = []

        for modifier in modifierSequence {
            guard let modifierDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: modifier.keyCode,
                keyDown: true
            ) else {
                continue
            }

            activeFlags.formUnion(modifier.flag)
            modifierDown.flags = activeFlags
            modifierDown.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.005)
        }

        let keyCode = CGKeyCode(command.keyCode)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = activeFlags
        keyDown?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = activeFlags
        keyUp?.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.005)

        for modifier in modifierSequence.reversed() {
            guard let modifierUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: modifier.keyCode,
                keyDown: false
            ) else {
                continue
            }

            modifierUp.flags = activeFlags
            modifierUp.post(tap: .cgSessionEventTap)
            activeFlags.remove(modifier.flag)
            Thread.sleep(forTimeInterval: 0.005)
        }

        Logger.shared.log(
            "KeystrokeSimulator: key command executed for keyCode=\(command.keyCode)",
            level: .info
        )
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

    static func orderedModifierSequence(
        for command: HotkeyConfiguration
    ) -> [(keyCode: CGKeyCode, flag: CGEventFlags)] {
        var sequence: [(CGKeyCode, CGEventFlags)] = []

        if command.useControl {
            sequence.append((modifierKeyCode(for: .control, side: command.controlSide), .maskControl))
        }
        if command.useOption {
            sequence.append((modifierKeyCode(for: .option, side: command.optionSide), .maskAlternate))
        }
        if command.useShift {
            sequence.append((modifierKeyCode(for: .shift, side: command.shiftSide), .maskShift))
        }
        if command.useCommand {
            sequence.append((modifierKeyCode(for: .command, side: command.commandSide), .maskCommand))
        }

        return sequence
    }

    private static func modifierKeyCode(
        for modifier: HotkeyModifierKey,
        side: ModifierSide
    ) -> CGKeyCode {
        switch (modifier, side) {
        case (.control, .right):
            return 0x3E
        case (.control, _):
            return 0x3B
        case (.option, .right):
            return 0x3D
        case (.option, _):
            return 0x3A
        case (.shift, .right):
            return 0x3C
        case (.shift, _):
            return 0x38
        case (.command, .right):
            return 0x36
        case (.command, _):
            return 0x37
        }
    }
}
