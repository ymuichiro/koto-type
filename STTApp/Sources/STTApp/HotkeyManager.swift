import AppKit

final class HotkeyManager: NSObject, @unchecked Sendable {
    private var monitor: Any?
    var hotkeyKeyDown: (() -> Void)?
    var hotkeyKeyUp: (() -> Void)?
    private var configuration = HotkeyConfiguration.default
    private let lock = NSLock()
    private var _previousModifiers: NSEvent.ModifierFlags = []
    private var _isHotkeyPressed = false
    private var _isProcessingHotkey = false
    
    override init() {
        super.init()
        Logger.shared.log("HotkeyManager: initializing", level: .debug)
        let settings = SettingsManager.shared.load()
        configuration = settings.hotkeyConfig
        setupGlobalMonitor()
        setupNotificationObserver()
        Logger.shared.log("HotkeyManager: initialized with config: \(configuration.description)", level: .info)
    }
    
    private func setupGlobalMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .hotkeyConfigurationChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let config = notification.object as? HotkeyConfiguration else { return }
            Logger.shared.log("HotkeyManager: Received hotkeyConfigurationChanged notification: \(config.description)")
            self.lock.lock()
            self.configuration = config
            self.lock.unlock()
            Logger.shared.log("HotkeyManager: Updated configuration to: \(config.description)")
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags
        let keyCode = event.keyCode
        
        lock.lock()
        let currentConfig = configuration
        lock.unlock()
        
        let currentModifiers = modifiers.intersection([.command, .option, .control, .shift])
        let targetModifiers = NSEvent.ModifierFlags(rawValue: currentConfig.modifiers)
        let modifiersMatch = currentModifiers == targetModifiers
        
        Logger.shared.log("HotkeyManager: event type=\(event.type), keyCode=\(keyCode), currentConfig.keyCode=\(currentConfig.keyCode), modifiersMatch=\(modifiersMatch), currentModifiers=\(currentModifiers.rawValue), target=\(targetModifiers.rawValue), _isHotkeyPressed=\(_isHotkeyPressed)")
        
        if currentConfig.keyCode == 0 {
            if event.type == .flagsChanged {
                let prevModifiers = _previousModifiers.intersection([.command, .option, .control, .shift])
                
                if currentModifiers == targetModifiers && prevModifiers != targetModifiers {
                    _isHotkeyPressed = true
                    Logger.shared.log("HotkeyManager: modifier-only hotkey key down", level: .debug)
                    DispatchQueue.main.async { [weak self] in
                        self?.hotkeyKeyDown?()
                    }
                } else if prevModifiers == targetModifiers && currentModifiers != targetModifiers && _isHotkeyPressed {
                    _isHotkeyPressed = false
                    Logger.shared.log("HotkeyManager: modifier-only hotkey key up", level: .debug)
                    DispatchQueue.main.async { [weak self] in
                        self?.hotkeyKeyUp?()
                    }
                }
                
                _previousModifiers = modifiers
            }
        } else if modifiersMatch && keyCode == currentConfig.keyCode {
            if event.type == .keyDown {
                if !_isHotkeyPressed && !_isProcessingHotkey {
                    _isHotkeyPressed = true
                    _isProcessingHotkey = true
                    Logger.shared.log("HotkeyManager: hotkey key down", level: .debug)
                    DispatchQueue.main.async { [weak self] in
                        self?.hotkeyKeyDown?()
                    }
                }
            } else if event.type == .keyUp && _isHotkeyPressed {
                _isHotkeyPressed = false
                _isProcessingHotkey = false
                Logger.shared.log("HotkeyManager: hotkey key up", level: .debug)
                DispatchQueue.main.async { [weak self] in
                    self?.hotkeyKeyUp?()
                }
            }
        } else if event.type == .flagsChanged {
            let prevModifiers = _previousModifiers.intersection([.command, .option, .control, .shift])
            
            if _isHotkeyPressed && prevModifiers == targetModifiers && currentModifiers != targetModifiers {
                _isHotkeyPressed = false
                _isProcessingHotkey = false
                Logger.shared.log("HotkeyManager: hotkey key up (modifiers changed)", level: .debug)
                DispatchQueue.main.async { [weak self] in
                    self?.hotkeyKeyUp?()
                }
            }
            
            _previousModifiers = modifiers
        }
    }
    
    func cleanup() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
}
