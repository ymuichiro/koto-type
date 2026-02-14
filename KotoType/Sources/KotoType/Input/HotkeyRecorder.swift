import AppKit
import SwiftUI

final class HotkeyRecorder: NSView {
    enum ModifierCaptureDecision: Equatable {
        case none
        case updateCurrent
        case commitPreviousAndLock
        case resetLock
    }

    private var onChange: ((HotkeyConfiguration) -> Void)?
    var currentConfig: HotkeyConfiguration = HotkeyConfiguration()
    private var modifiers: NSEvent.ModifierFlags = []
    private var pressedKeyCode: UInt32 = 0
    private var regularKeyPressed = false
    private var modifierReleaseCommitted = false
    
    init(initialConfig: HotkeyConfiguration = HotkeyConfiguration(), onChange: @escaping (HotkeyConfiguration) -> Void) {
        self.currentConfig = initialConfig
        self.onChange = onChange
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
    
    func setConfig(_ config: HotkeyConfiguration) {
        currentConfig = config
        pressedKeyCode = 0
        modifiers = []
        regularKeyPressed = false
        modifierReleaseCommitted = false
        needsDisplay = true
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
    
    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        if keyCode > 0 && isValidKeyCode(UInt32(keyCode)) {
            modifiers = event.modifierFlags
            pressedKeyCode = UInt32(keyCode)
            regularKeyPressed = true
            modifierReleaseCommitted = false
            updateConfig()
        }
    }
    
    override func keyUp(with event: NSEvent) {
        let keyCode = event.keyCode
        if keyCode > 0 && UInt32(keyCode) == pressedKeyCode {
            pressedKeyCode = 0
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        let previousModifiers = Self.relevantModifiers(from: modifiers)
        modifiers = event.modifierFlags
        let currentModifiers = Self.relevantModifiers(from: modifiers)

        switch Self.modifierCaptureDecision(
            previous: previousModifiers,
            current: currentModifiers,
            regularKeyPressed: regularKeyPressed,
            modifierReleaseCommitted: modifierReleaseCommitted
        ) {
        case .updateCurrent:
            applyConfig(Self.configuration(from: currentModifiers, keyCode: pressedKeyCode))
        case .commitPreviousAndLock:
            applyConfig(Self.configuration(from: previousModifiers, keyCode: pressedKeyCode))
            modifierReleaseCommitted = true
        case .resetLock:
            modifierReleaseCommitted = false
        case .none:
            break
        }

        if regularKeyPressed && !previousModifiers.isEmpty && currentModifiers.isEmpty {
            regularKeyPressed = false
        }
    }
    
    private func updateConfig() {
        let config = Self.configuration(from: Self.relevantModifiers(from: modifiers), keyCode: pressedKeyCode)
        applyConfig(config)
    }

    private func applyConfig(_ config: HotkeyConfiguration) {
        if config != currentConfig {
            currentConfig = config
            onChange?(config)
            needsDisplay = true
        }
    }

    static func configuration(from modifiers: NSEvent.ModifierFlags, keyCode: UInt32) -> HotkeyConfiguration {
        var config = HotkeyConfiguration(
            useCommand: false,
            useOption: false,
            useControl: false,
            useShift: false,
            keyCode: 0
        )

        if modifiers.contains(.command) { config.useCommand = true }
        if modifiers.contains(.option) { config.useOption = true }
        if modifiers.contains(.control) { config.useControl = true }
        if modifiers.contains(.shift) { config.useShift = true }

        if keyCode > 0 {
            config.keyCode = keyCode
        }

        return config
    }

    static func modifierCaptureDecision(
        previous: NSEvent.ModifierFlags,
        current: NSEvent.ModifierFlags,
        regularKeyPressed: Bool,
        modifierReleaseCommitted: Bool
    ) -> ModifierCaptureDecision {
        if regularKeyPressed {
            if !previous.isEmpty && current.isEmpty {
                return .resetLock
            }
            return .none
        }

        if current.isEmpty {
            return .resetLock
        }

        if modifierReleaseCommitted {
            return .none
        }

        if modifierCount(current) < modifierCount(previous) {
            return .commitPreviousAndLock
        }

        return .updateCurrent
    }

    static func relevantModifiers(from modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    static func modifierCount(_ modifiers: NSEvent.ModifierFlags) -> Int {
        var count = 0
        if modifiers.contains(.command) { count += 1 }
        if modifiers.contains(.option) { count += 1 }
        if modifiers.contains(.control) { count += 1 }
        if modifiers.contains(.shift) { count += 1 }
        return count
    }
    
    private func isValidKeyCode(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case 0x00...0x0F, 0x10...0x2F, 0x31:
            return true
        default:
            return false
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let text = currentConfig.description.isEmpty ? "Press hotkey..." : currentConfig.description
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: currentConfig.description.isEmpty ? NSColor.placeholderTextColor : NSColor.labelColor
        ]
        
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }
}
