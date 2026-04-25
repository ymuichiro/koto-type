import AppKit
import SwiftUI
import Foundation

class SettingsWindowController: NSWindowController {
    private static let minimumContentSize = NSSize(width: 600, height: 600)
    private static let initialContentSize = NSSize(width: 640, height: 640)

    private var settingsView: SettingsView?
    private var hostingController: NSHostingController<SettingsView>?
    
    var onSettingsChanged: (() -> Void)?
    var onImportAudioRequested: (() -> Void)?
    var onShowHistoryRequested: (() -> Void)?
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.initialContentSize.width,
                height: Self.initialContentSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = Self.minimumContentSize
        
        super.init(window: window)
        
        setupSettingsView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func makeIsPresentedBinding(for window: NSWindow) -> Binding<Bool> {
        Binding<Bool>(
            get: { false },
            set: { if !$0 { window.close() } }
        )
    }

    private func makeSettingsView(for window: NSWindow) -> SettingsView {
        SettingsView(
            isPresented: makeIsPresentedBinding(for: window),
            onHotkeyChanged: { config in
                Logger.shared.log("SettingsWindowController: Posting hotkeyConfigurationChanged notification: \(config.description)")
                NotificationCenter.default.post(
                    name: .hotkeyConfigurationChanged,
                    object: config
                )
            },
            onSettingsChanged: { [weak self] in
                Logger.shared.log("SettingsWindowController: onSettingsChanged called")
                self?.onSettingsChanged?()
            },
            onImportAudioRequested: { [weak self] in
                self?.onImportAudioRequested?()
            },
            onShowHistoryRequested: { [weak self] in
                self?.onShowHistoryRequested?()
            }
        )
    }

    private func ensureMinimumContentSize(for window: NSWindow) {
        let currentContentSize = window.contentRect(forFrameRect: window.frame).size
        let targetSize = NSSize(
            width: max(currentContentSize.width, Self.minimumContentSize.width),
            height: max(currentContentSize.height, Self.minimumContentSize.height)
        )
        guard targetSize != currentContentSize else { return }
        window.setContentSize(targetSize)
    }

    private func setupSettingsView() {
        guard let window = window else { return }

        ensureMinimumContentSize(for: window)
        settingsView = makeSettingsView(for: window)
        hostingController = NSHostingController(rootView: settingsView!)
        window.contentView = hostingController?.view
    }
    
    func showSettings() {
        guard let window = window else { return }

        ensureMinimumContentSize(for: window)
        settingsView = makeSettingsView(for: window)
        hostingController = NSHostingController(rootView: settingsView!)
        window.contentView = hostingController?.view
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let hotkeyConfigurationChanged = Notification.Name("hotkeyConfigurationChanged")
}
