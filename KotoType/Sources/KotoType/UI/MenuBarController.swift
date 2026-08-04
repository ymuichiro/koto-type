import AppKit
import Foundation
import os.log

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var checkForUpdatesItem: NSMenuItem?
    var showSettings: (() -> Void)?
    var showHistory: (() -> Void)?
    var showPromptAuthoring: (() -> Void)?
    var importAudioFile: (() -> Void)?
    var checkForUpdates: (() -> Void)?
    
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

        let promptAuthoringItem = NSMenuItem(
            title: "Voice Prompt Authoring (Prototype)...",
            action: #selector(showPromptAuthoringMenu),
            keyEquivalent: "p"
        )
        promptAuthoringItem.target = self
        menu.addItem(promptAuthoringItem)

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesMenu),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        self.checkForUpdatesItem = checkForUpdatesItem
        
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

    @objc private func showPromptAuthoringMenu() {
        showPromptAuthoring?()
    }

    @objc private func importAudioFileMenu() {
        importAudioFile?()
    }

    @objc private func checkForUpdatesMenu() {
        checkForUpdates?()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func setCheckForUpdatesEnabled(_ isEnabled: Bool) {
        checkForUpdatesItem?.isEnabled = isEnabled
    }
    
    private func loadMenuBarIconImage() -> NSImage? {
        let imageName = isDarkMode ? "koto-type_logo_mini_light" : "koto-type_logo_mini_dark"
        guard let image = loadPNG(named: imageName) else { return nil }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private func loadPNG(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let resourcePath = Bundle.main.resourcePath {
            let filePath = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("\(name).png")
                .path
            if let image = NSImage(contentsOfFile: filePath) {
                return image
            }
        }

        let cwd = FileManager.default.currentDirectoryPath
        for path in [
            "\(cwd)/Sources/KotoType/Resources/\(name).png",
            "\(cwd)/.build/arm64-apple-macosx/debug/KotoType_KotoType.bundle/\(name).png",
            "\(cwd)/.build/arm64-apple-macosx/release/KotoType_KotoType.bundle/\(name).png",
        ] {
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        return nil
    }

    private var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
