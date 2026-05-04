import AppKit
import Foundation
import SwiftUI

@MainActor
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    typealias UnsavedChangesPresenter = @MainActor (NSWindow) -> SettingsCloseConfirmationChoice

    private static let minimumContentSize = NSSize(width: 600, height: 600)
    private static let initialContentSize = NSSize(width: 640, height: 640)

    private let draftBridge: SettingsDraftBridge
    private let unsavedChangesPresenter: UnsavedChangesPresenter
    private let resetDraftBridgeOnViewLoad: Bool
    private var settingsView: SettingsView?
    private var hostingController: NSHostingController<SettingsView>?
    
    var onSettingsChanged: (() -> Void)?
    var onImportAudioRequested: (() -> Void)?
    var onShowHistoryRequested: (() -> Void)?
    
    init(
        draftBridge: SettingsDraftBridge = SettingsDraftBridge(initialSnapshot: SettingsDraft().snapshot),
        unsavedChangesPresenter: UnsavedChangesPresenter? = nil,
        resetDraftBridgeOnViewLoad: Bool = true
    ) {
        self.draftBridge = draftBridge
        self.unsavedChangesPresenter = unsavedChangesPresenter ?? { window in
            Self.presentUnsavedChangesConfirmation(window: window)
        }
        self.resetDraftBridgeOnViewLoad = resetDraftBridgeOnViewLoad
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
        window.delegate = nil
        
        super.init(window: window)
        window.delegate = self
        
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
        if resetDraftBridgeOnViewLoad {
            syncDraftBridgeToSavedState()
        }
        return SettingsView(
            isPresented: makeIsPresentedBinding(for: window),
            draftBridge: draftBridge,
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

    private func syncDraftBridgeToSavedState() {
        draftBridge.markSaved(snapshot: SettingsDraft().snapshot)
        draftBridge.applyChanges = nil
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldAllowWindowClose(for: sender)
    }

    func shouldAllowWindowClose(for window: NSWindow) -> Bool {
        guard draftBridge.hasUnsavedChanges else {
            return true
        }

        switch unsavedChangesPresenter(window) {
        case .save:
            guard let applyChanges = draftBridge.applyChanges else {
                Logger.shared.log(
                    "SettingsWindowController: save requested during close, but no apply handler is available",
                    level: .warning
                )
                return false
            }
            applyChanges()
            return true
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private static func presentUnsavedChangesConfirmation(window: NSWindow) -> SettingsCloseConfirmationChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "If you close now, your unsaved Settings changes will be lost."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}

extension Notification.Name {
    static let hotkeyConfigurationChanged = Notification.Name("hotkeyConfigurationChanged")
}
