import AppKit
import os.log

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    var showSettings: (() -> Void)?
    var showHistory: (() -> Void)?
    var importAudioFile: (() -> Void)?
    
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
        let button = statusItem?.button
        button?.title = ""
        button?.image = loadMenuBarIconImage()
        button?.imagePosition = .imageOnly
        NSLog("MenuBarController: icon image set")
        
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let importAudioItem = NSMenuItem(title: "Import Audio File...", action: #selector(importAudioFileMenu), keyEquivalent: "i")
        importAudioItem.target = self
        menu.addItem(importAudioItem)

        let historyItem = NSMenuItem(title: "History...", action: #selector(showHistoryMenu), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)
        
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

    @objc private func showHistoryMenu() {
        showHistory?()
    }

    @objc private func importAudioFileMenu() {
        importAudioFile?()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    private func loadMenuBarIconImage() -> NSImage? {
        let imageName = isDarkMode ? "koto-type_logo_mini_light" : "koto-type_logo_mini_dark"
        guard let image = AppImageLoader.loadPNG(named: imageName) else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
