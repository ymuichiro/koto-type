import AppKit
import Foundation
import SwiftUI

class HistoryWindowController: NSWindowController {
    private var hostingController: NSHostingController<HistoryView>?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcription History"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupHistoryView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupHistoryView() {
        guard let window = window else { return }

        let view = HistoryView(onClose: {
            window.close()
        })

        hostingController = NSHostingController(rootView: view)
        window.contentView = hostingController?.view
    }

    func showHistory() {
        setupHistoryView()
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
