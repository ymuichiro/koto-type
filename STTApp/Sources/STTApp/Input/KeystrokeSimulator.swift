import AppKit
import ScriptingBridge

final class KeystrokeSimulator {
    
    static func typeText(_ text: String) {
        Logger.shared.log("KeystrokeSimulator: typeText called with text length: \(text.count)", level: .debug)
        Logger.shared.log("KeystrokeSimulator: text content: \(text)", level: .debug)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Logger.shared.log("KeystrokeSimulator: text set to pasteboard", level: .debug)

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
        
        Logger.shared.log("KeystrokeSimulator: Cmd+V executed via CGEvent", level: .info)
    }
}
