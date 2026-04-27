import AppKit
import Foundation
import IOKit.hidsystem

enum ModifierSide: String, Codable, CaseIterable, Hashable {
    case either
    case left
    case right

    fileprivate func token(for symbol: String) -> String {
        switch self {
        case .either:
            return symbol
        case .left:
            return "L\(symbol)"
        case .right:
            return "R\(symbol)"
        }
    }
}

enum HotkeyModifierKey: CaseIterable {
    case command
    case option
    case control
    case shift
}

struct HotkeyConfiguration: Codable, Equatable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case useCommand
        case useOption
        case useControl
        case useShift
        case commandSide
        case optionSide
        case controlSide
        case shiftSide
        case keyCode
    }

    var useCommand: Bool = true
    var useOption: Bool = true
    var useControl: Bool = false
    var useShift: Bool = false
    var commandSide: ModifierSide = .either
    var optionSide: ModifierSide = .either
    var controlSide: ModifierSide = .either
    var shiftSide: ModifierSide = .either
    var keyCode: UInt32 = 0

    static let `default` = HotkeyConfiguration()

    init(
        useCommand: Bool = true,
        useOption: Bool = true,
        useControl: Bool = false,
        useShift: Bool = false,
        commandSide: ModifierSide = .either,
        optionSide: ModifierSide = .either,
        controlSide: ModifierSide = .either,
        shiftSide: ModifierSide = .either,
        keyCode: UInt32 = 0
    ) {
        self.useCommand = useCommand
        self.useOption = useOption
        self.useControl = useControl
        self.useShift = useShift
        self.commandSide = commandSide
        self.optionSide = optionSide
        self.controlSide = controlSide
        self.shiftSide = shiftSide
        self.keyCode = keyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useCommand = try container.decodeIfPresent(Bool.self, forKey: .useCommand) ?? true
        useOption = try container.decodeIfPresent(Bool.self, forKey: .useOption) ?? true
        useControl = try container.decodeIfPresent(Bool.self, forKey: .useControl) ?? false
        useShift = try container.decodeIfPresent(Bool.self, forKey: .useShift) ?? false
        commandSide = try container.decodeIfPresent(ModifierSide.self, forKey: .commandSide) ?? .either
        optionSide = try container.decodeIfPresent(ModifierSide.self, forKey: .optionSide) ?? .either
        controlSide = try container.decodeIfPresent(ModifierSide.self, forKey: .controlSide) ?? .either
        shiftSide = try container.decodeIfPresent(ModifierSide.self, forKey: .shiftSide) ?? .either
        keyCode = try container.decodeIfPresent(UInt32.self, forKey: .keyCode) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useCommand, forKey: .useCommand)
        try container.encode(useOption, forKey: .useOption)
        try container.encode(useControl, forKey: .useControl)
        try container.encode(useShift, forKey: .useShift)
        try container.encode(commandSide, forKey: .commandSide)
        try container.encode(optionSide, forKey: .optionSide)
        try container.encode(controlSide, forKey: .controlSide)
        try container.encode(shiftSide, forKey: .shiftSide)
        try container.encode(keyCode, forKey: .keyCode)
    }

    var description: String {
        var parts: [String] = []
        if useControl { parts.append(controlSide.token(for: "⌃")) }
        if useOption { parts.append(optionSide.token(for: "⌥")) }
        if useShift { parts.append(shiftSide.token(for: "⇧")) }
        if useCommand { parts.append(commandSide.token(for: "⌘")) }
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

    func matches(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let relevantFlags = Self.relevantModifiers(from: modifierFlags)
        return Self.matches(
            useModifier: useCommand,
            side: commandSide,
            key: .command,
            in: relevantFlags
        ) && Self.matches(
            useModifier: useOption,
            side: optionSide,
            key: .option,
            in: relevantFlags
        ) && Self.matches(
            useModifier: useControl,
            side: controlSide,
            key: .control,
            in: relevantFlags
        ) && Self.matches(
            useModifier: useShift,
            side: shiftSide,
            key: .shift,
            in: relevantFlags
        )
    }

    static func relevantModifiers(from modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers.rawValue & relevantModifierMask)
    }

    static func side(for key: HotkeyModifierKey, in modifiers: NSEvent.ModifierFlags) -> ModifierSide? {
        let relevantFlags = relevantModifiers(from: modifiers)
        let left = isLeftActive(key, in: relevantFlags)
        let right = isRightActive(key, in: relevantFlags)

        if left && !right {
            return .left
        }

        if right && !left {
            return .right
        }

        if relevantFlags.contains(genericFlag(for: key)) || left || right {
            return .either
        }

        return nil
    }

    static func modifierCount(_ modifiers: NSEvent.ModifierFlags) -> Int {
        HotkeyModifierKey.allCases.reduce(into: 0) { count, key in
            if isActive(key, in: modifiers) {
                count += 1
            }
        }
    }

    private static let relevantModifierMask: NSEvent.ModifierFlags.RawValue =
        NSEvent.ModifierFlags.command.rawValue
        | NSEvent.ModifierFlags.option.rawValue
        | NSEvent.ModifierFlags.control.rawValue
        | NSEvent.ModifierFlags.shift.rawValue
        | Self.leftCommandMask
        | Self.rightCommandMask
        | Self.leftOptionMask
        | Self.rightOptionMask
        | Self.leftControlMask
        | Self.rightControlMask
        | Self.leftShiftMask
        | Self.rightShiftMask

    private static let leftControlMask = NSEvent.ModifierFlags.RawValue(NX_DEVICELCTLKEYMASK)
    private static let rightControlMask = NSEvent.ModifierFlags.RawValue(NX_DEVICERCTLKEYMASK)
    private static let leftShiftMask = NSEvent.ModifierFlags.RawValue(NX_DEVICELSHIFTKEYMASK)
    private static let rightShiftMask = NSEvent.ModifierFlags.RawValue(NX_DEVICERSHIFTKEYMASK)
    private static let leftCommandMask = NSEvent.ModifierFlags.RawValue(NX_DEVICELCMDKEYMASK)
    private static let rightCommandMask = NSEvent.ModifierFlags.RawValue(NX_DEVICERCMDKEYMASK)
    private static let leftOptionMask = NSEvent.ModifierFlags.RawValue(NX_DEVICELALTKEYMASK)
    private static let rightOptionMask = NSEvent.ModifierFlags.RawValue(NX_DEVICERALTKEYMASK)

    private static func matches(
        useModifier: Bool,
        side: ModifierSide,
        key: HotkeyModifierKey,
        in modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let active = isActive(key, in: modifiers)
        guard useModifier else {
            return !active
        }

        switch side {
        case .either:
            return active
        case .left:
            return isLeftActive(key, in: modifiers) && !isRightActive(key, in: modifiers)
        case .right:
            return isRightActive(key, in: modifiers) && !isLeftActive(key, in: modifiers)
        }
    }

    private static func isActive(_ key: HotkeyModifierKey, in modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(genericFlag(for: key))
            || isLeftActive(key, in: modifiers)
            || isRightActive(key, in: modifiers)
    }

    private static func isLeftActive(_ key: HotkeyModifierKey, in modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.rawValue & leftMask(for: key) != 0
    }

    private static func isRightActive(_ key: HotkeyModifierKey, in modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.rawValue & rightMask(for: key) != 0
    }

    private static func genericFlag(for key: HotkeyModifierKey) -> NSEvent.ModifierFlags {
        switch key {
        case .command:
            return .command
        case .option:
            return .option
        case .control:
            return .control
        case .shift:
            return .shift
        }
    }

    private static func leftMask(for key: HotkeyModifierKey) -> NSEvent.ModifierFlags.RawValue {
        switch key {
        case .command:
            return leftCommandMask
        case .option:
            return leftOptionMask
        case .control:
            return leftControlMask
        case .shift:
            return leftShiftMask
        }
    }

    private static func rightMask(for key: HotkeyModifierKey) -> NSEvent.ModifierFlags.RawValue {
        switch key {
        case .command:
            return rightCommandMask
        case .option:
            return rightOptionMask
        case .control:
            return rightControlMask
        case .shift:
            return rightShiftMask
        }
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
        case 0x0A: return "Kana"
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
