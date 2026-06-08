import AppKit

final class HotkeyManager: NSObject, @unchecked Sendable {
    private var monitor: Any?
    private var settingsObserver: NSObjectProtocol?
    var hotkeyKeyDown: ((RecordingRequestMode) -> Void)?
    var hotkeyKeyUp: ((RecordingRequestMode) -> Void)?
    private var hotkeyStateByMode: [RecordingRequestMode: HotkeyState] = [:]
    private let lock = NSLock()
    private var _previousModifiers: NSEvent.ModifierFlags = []

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
        let translationHotkeyConfig =
            settings.translationHotkeyConfig.isSet && settings.translationHotkeyConfig == settings.hotkeyConfig
            ? .unset
            : settings.translationHotkeyConfig

        var releasedModes: [RecordingRequestMode] = []
        lock.lock()
        for mode in RecordingRequestMode.allCases {
            if hotkeyStateByMode[mode]?.isPressed == true {
                releasedModes.append(mode)
            }
        }
        hotkeyStateByMode = [
            .transcribe: HotkeyState(configuration: settings.hotkeyConfig),
            .translate: HotkeyState(configuration: translationHotkeyConfig),
        ]
        _previousModifiers = []
        lock.unlock()

        Logger.shared.log(
            "HotkeyManager: Updated configurations - transcription=\(settings.hotkeyConfig.description), translation=\(translationHotkeyConfig.description)",
            level: .info
        )

        for mode in releasedModes {
            DispatchQueue.main.async { [weak self] in
                self?.hotkeyKeyUp?(mode)
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let currentModifiers = HotkeyConfiguration.relevantModifiers(from: event.modifierFlags)

        lock.lock()
        let previousModifiers = HotkeyConfiguration.relevantModifiers(from: _previousModifiers)
        var hotkeyStateByMode = self.hotkeyStateByMode
        var actions: [HotkeyEventAction] = []

        for mode in RecordingRequestMode.allCases {
            var state = hotkeyStateByMode[mode] ?? HotkeyState(configuration: .unset)
            let config = state.configuration

            guard config.isSet else {
                if state.isPressed {
                    state.isPressed = false
                    actions.append(.released(mode))
                }
                hotkeyStateByMode[mode] = state
                continue
            }

            let currentModifiersMatch = config.matches(modifierFlags: currentModifiers)
            let previousModifiersMatch = config.matches(modifierFlags: previousModifiers)

            if config.keyCode == 0 {
                guard event.type == .flagsChanged else {
                    hotkeyStateByMode[mode] = state
                    continue
                }

                if currentModifiersMatch && !previousModifiersMatch && !state.isPressed {
                    state.isPressed = true
                    actions.append(.pressed(mode))
                } else if previousModifiersMatch && !currentModifiersMatch && state.isPressed {
                    state.isPressed = false
                    actions.append(.released(mode))
                }

                hotkeyStateByMode[mode] = state
                continue
            }

            if event.type == .keyDown, currentModifiersMatch, event.keyCode == config.keyCode, !state.isPressed {
                state.isPressed = true
                actions.append(.pressed(mode))
            } else if event.type == .keyUp, event.keyCode == config.keyCode, state.isPressed {
                state.isPressed = false
                actions.append(.released(mode))
            } else if event.type == .flagsChanged, previousModifiersMatch, !currentModifiersMatch, state.isPressed {
                state.isPressed = false
                actions.append(.released(mode))
            }

            hotkeyStateByMode[mode] = state
        }

        self.hotkeyStateByMode = hotkeyStateByMode
        _previousModifiers = event.modifierFlags
        lock.unlock()

        for action in actions {
            DispatchQueue.main.async { [weak self] in
                switch action {
                case let .pressed(mode):
                    self?.hotkeyKeyDown?(mode)
                case let .released(mode):
                    self?.hotkeyKeyUp?(mode)
                }
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

private struct HotkeyState {
    let configuration: HotkeyConfiguration
    var isPressed = false
}

private enum HotkeyEventAction {
    case pressed(RecordingRequestMode)
    case released(RecordingRequestMode)
}
