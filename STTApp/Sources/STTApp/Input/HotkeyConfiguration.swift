import Foundation
import AppKit

struct HotkeyConfiguration: Codable, Equatable, Hashable {
    var useCommand: Bool = true
    var useOption: Bool = true
    var useControl: Bool = false
    var useShift: Bool = false
    var keyCode: UInt32 = 0
    
    static let `default` = HotkeyConfiguration()
    
    var description: String {
        var parts: [String] = []
        if useControl { parts.append("⌃") }
        if useOption { parts.append("⌥") }
        if useShift { parts.append("⇧") }
        if useCommand { parts.append("⌘") }
        if keyCode > 0 {
            parts.append(keyCodeToString(keyCode))
        }
        return parts.joined()
    }
    
    var modifiers: NSEvent.ModifierFlags.RawValue {
        var flags: NSEvent.ModifierFlags = []
        if useCommand { flags.insert(.command) }
        if useOption { flags.insert(.option) }
        if useControl { flags.insert(.control) }
        if useShift { flags.insert(.shift) }
        return flags.rawValue
    }
    
    private func keyCodeToString(_ code: UInt32) -> String {
        switch code {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0A: return "日本語"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x24: return "Enter"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x32: return "Backspace"
        case 0x33: return "Delete"
        case 0x34: return "Escape"
        case 0x35: return "Command"
        case 0x36: return "Command"
        case 0x37: return "Command"
        case 0x38: return "Shift"
        case 0x39: return "Caps Lock"
        case 0x3A: return "Option"
        case 0x3B: return "Option"
        case 0x3C: return "Control"
        case 0x3D: return "Shift"
        case 0x3E: return "Control"
        case 0x3F: return "Fn"
        default: return ""
        }
    }
}
