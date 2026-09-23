import AppKit

final class HotkeyManager: NSObject, @unchecked Sendable {
    private var monitor: Any?
    private var settingsObserver: NSObjectProtocol?
    var hotkeyKeyDown: (() -> Void)?
    var hotkeyKeyUp: (() -> Void)?
    private var state = HotkeyState(configuration: .unset)
    private let lock = NSLock()

    override init() {
        super.init()
        Logger.shared.log("HotkeyManager: initializing", level: .debug)
        applySettings(SettingsManager.shared.load())
        setupGlobalMonitor()
        setupNotificationObserver()
        Logger.shared.log("HotkeyManager: initialized", level: .info)
    }

    private func setupGlobalMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    private func setupNotificationObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .hotkeySettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let settings = notification.object as? AppSettings ?? SettingsManager.shared.load()
            self.applySettings(settings)
        }
    }

    private func applySettings(_ settings: AppSettings) {
        lock.lock()
        let wasPressed = state.configure(settings.hotkeyConfig)
        lock.unlock()

        Logger.shared.log(
            "HotkeyManager: Updated configuration - transcription=\(settings.hotkeyConfig.description)",
            level: .info
        )

        if wasPressed {
            DispatchQueue.main.async { [weak self] in
                self?.hotkeyKeyUp?()
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        lock.lock()
        let transition = state.handle(
            type: event.type,
            keyCode: event.keyCode,
            modifiers: HotkeyConfiguration.relevantModifiers(from: event.modifierFlags)
        )
        lock.unlock()
        guard let isPressed = transition else { return }
        DispatchQueue.main.async { [weak self] in
            if isPressed {
                self?.hotkeyKeyDown?()
            } else {
                self?.hotkeyKeyUp?()
            }
        }
    }

    func cleanup() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }
}

struct HotkeyState {
    private let configuration: HotkeyConfiguration
    private(set) var isPressed = false
    private var previousModifiers: NSEvent.ModifierFlags = []

    init(configuration: HotkeyConfiguration) {
        self.configuration = configuration
    }

    mutating func configure(_ configuration: HotkeyConfiguration) -> Bool {
        let wasPressed = isPressed
        self = Self(configuration: configuration)
        return wasPressed
    }

    // nil means no transition; true/false mean press/release respectively.
    mutating func handle(type: NSEvent.EventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool? {
        defer { previousModifiers = modifiers }
        guard configuration.isSet else { return nil }
        let matches = configuration.matches(modifierFlags: modifiers)
        let previouslyMatched = configuration.matches(modifierFlags: previousModifiers)
        let wasPressed = isPressed
        if configuration.keyCode == 0 {
            guard type == .flagsChanged else { return nil }
            if matches && !previouslyMatched { isPressed = true }
            else if previouslyMatched && !matches { isPressed = false }
        } else if type == .keyDown && matches && keyCode == configuration.keyCode {
            isPressed = true
        } else if (type == .keyUp && keyCode == configuration.keyCode)
                    || (type == .flagsChanged && previouslyMatched && !matches) {
            isPressed = false
        }
        return isPressed == wasPressed ? nil : isPressed
    }
}
