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
        
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if NSAppleScript(source: script)!.executeAndReturnError(&error).stringValue == nil {
            if let error = error {
                Logger.shared.log("KeystrokeSimulator: AppleScript error: \(error)", level: .error)
            }
        } else {
            Logger.shared.log("KeystrokeSimulator: Cmd+V executed successfully", level: .info)
        }
    }
}
