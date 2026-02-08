import AppKit
import SwiftUI
import Foundation

class SettingsWindowController: NSWindowController {
    private var settingsView: SettingsView?
    private var hostingController: NSHostingController<SettingsView>?
    
    var onSettingsChanged: (() -> Void)?
    var onImportAudioRequested: (() -> Void)?
    var onShowHistoryRequested: (() -> Void)?
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        
        setupSettingsView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSettingsView() {
        guard let window = window else { return }
        
        let isPresented = Binding<Bool>(
            get: { false },
            set: { if !$0 { window.close() } }
        )
        
        settingsView = SettingsView(
            isPresented: isPresented,
            onHotkeyChanged: { config in
                Logger.shared.log("SettingsWindowController: Posting hotkeyConfigurationChanged notification: \(config.description)")
                NotificationCenter.default.post(
                    name: .hotkeyConfigurationChanged,
                    object: config
                )
            },
            onSettingsChanged: {
                Logger.shared.log("SettingsWindowController: onSettingsChanged called")
            },
            onImportAudioRequested: { [weak self] in
                self?.onImportAudioRequested?()
            },
            onShowHistoryRequested: { [weak self] in
                self?.onShowHistoryRequested?()
            }
        )
        
        hostingController = NSHostingController(rootView: settingsView!)
        window.contentView = hostingController?.view
    }
    
    func showSettings() {
        guard let window = window else { return }
        
        settingsView = SettingsView(
            isPresented: Binding<Bool>(
                get: { false },
                set: { if !$0 { window.close() } }
            ),
            onHotkeyChanged: { config in
                Logger.shared.log("SettingsWindowController: Posting hotkeyConfigurationChanged notification: \(config.description)")
                NotificationCenter.default.post(
                    name: .hotkeyConfigurationChanged,
                    object: config
                )
            },
            onSettingsChanged: {
                Logger.shared.log("SettingsWindowController: onSettingsChanged called")
            },
            onImportAudioRequested: { [weak self] in
                self?.onImportAudioRequested?()
            },
            onShowHistoryRequested: { [weak self] in
                self?.onShowHistoryRequested?()
            }
        )
        
        hostingController = NSHostingController(rootView: settingsView!)
        window.contentView = hostingController?.view
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let hotkeyConfigurationChanged = Notification.Name("hotkeyConfigurationChanged")
}
