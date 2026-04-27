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
        
        let currentModifiers = HotkeyConfiguration.relevantModifiers(from: modifiers)
        let modifiersMatch = currentConfig.matches(modifierFlags: currentModifiers)

        if currentConfig.keyCode == 0 {
            if event.type == .flagsChanged {
                let prevModifiers = HotkeyConfiguration.relevantModifiers(from: _previousModifiers)
                
                if modifiersMatch && !currentConfig.matches(modifierFlags: prevModifiers) {
                    _isHotkeyPressed = true
                    DispatchQueue.main.async { [weak self] in
                        self?.hotkeyKeyDown?()
                    }
                } else if currentConfig.matches(modifierFlags: prevModifiers) && !modifiersMatch && _isHotkeyPressed {
                    _isHotkeyPressed = false
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
                    DispatchQueue.main.async { [weak self] in
                        self?.hotkeyKeyDown?()
                    }
                }
            } else if event.type == .keyUp && _isHotkeyPressed {
                _isHotkeyPressed = false
                _isProcessingHotkey = false
                DispatchQueue.main.async { [weak self] in
                    self?.hotkeyKeyUp?()
                }
            }
        } else if event.type == .flagsChanged {
            let prevModifiers = HotkeyConfiguration.relevantModifiers(from: _previousModifiers)
            
            if _isHotkeyPressed && currentConfig.matches(modifierFlags: prevModifiers) && !modifiersMatch {
                _isHotkeyPressed = false
                _isProcessingHotkey = false
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
