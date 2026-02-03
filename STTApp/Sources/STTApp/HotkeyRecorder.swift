import AppKit
import SwiftUI

final class HotkeyRecorder: NSView {
    private var onChange: ((HotkeyConfiguration) -> Void)?
    var currentConfig: HotkeyConfiguration = HotkeyConfiguration()
    private var modifiers: NSEvent.ModifierFlags = []
    private var pressedKeyCode: UInt32 = 0
    private var regularKeyPressed = false
    
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
        let previousModifiers = modifiers
        modifiers = event.modifierFlags
        
        let previousHasModifiers = previousModifiers.contains(.command) ||
                                  previousModifiers.contains(.option) ||
                                  previousModifiers.contains(.control) ||
                                  previousModifiers.contains(.shift)
        
        let currentHasModifiers = modifiers.contains(.command) ||
                                 modifiers.contains(.option) ||
                                 modifiers.contains(.control) ||
                                 modifiers.contains(.shift)
        
        if !regularKeyPressed && currentHasModifiers {
            updateConfig()
        }
        
        if regularKeyPressed && previousHasModifiers && !currentHasModifiers {
            regularKeyPressed = false
        }
    }
    
    private func updateConfig() {
        var config = HotkeyConfiguration()
        
        if modifiers.contains(.command) { config.useCommand = true }
        if modifiers.contains(.option) { config.useOption = true }
        if modifiers.contains(.control) { config.useControl = true }
        if modifiers.contains(.shift) { config.useShift = true }
        
        if pressedKeyCode > 0 {
            config.keyCode = pressedKeyCode
        }
        
        if config != currentConfig {
            currentConfig = config
            onChange?(config)
            needsDisplay = true
        }
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
        
        let text = currentConfig.description.isEmpty ? "ホットキーを入力..." : currentConfig.description
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
