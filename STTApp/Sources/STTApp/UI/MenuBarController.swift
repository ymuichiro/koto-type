import AppKit
import os.log

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    var showSettings: (() -> Void)?
    
    override init() {
        super.init()
        NSLog("MenuBarController: init called")
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NSLog("MenuBarController: statusItem created: \(statusItem != nil)")
        NSLog("MenuBarController: statusItem visible: \(statusItem?.isVisible ?? false)")
        NSLog("MenuBarController: statusItem button: \(statusItem?.button != nil)")
        statusItem?.isVisible = true
        statusItem?.button?.title = "STT"
        NSLog("MenuBarController: title set to '\(statusItem?.button?.title ?? "nil")'")
        
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        NSLog("MenuBarController: menu created and assigned")
        NSLog("MenuBarController: statusItem.autosaveName: \(statusItem?.autosaveName ?? "nil")")
    }
    
    @objc private func showSettingsMenu() {
        showSettings?()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateStatus(_ status: String) {
        statusItem?.button?.title = status
    }
}
