import AppKit
import SwiftUI

class RecordingIndicatorWindow: NSPanel {
    private var hostingController: NSHostingController<RecordingIndicatorView>?
    
    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 60, height: 60)
        
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupContent()
    }
    
    private func setupWindow() {
        self.level = .floating
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        positionWindow()
    }
    
    private func setupContent() {
        let view = RecordingIndicatorView(state: .recording)
        hostingController = NSHostingController(rootView: view)
        
        self.contentView = hostingController?.view
    }
    
    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowWidth = self.contentRect(forFrameRect: self.frame).width
        let windowHeight = self.contentRect(forFrameRect: self.frame).height
        let margin: CGFloat = 50
        
        let x = (screenFrame.width - windowWidth) / 2
        let y = margin
        
        self.setFrame(
            NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            display: true
        )
    }
    
    func showRecording() {
        DispatchQueue.main.async {
            self.orderFrontRegardless()
            self.alphaValue = 0
            
            let view = RecordingIndicatorView(state: .recording)
            self.hostingController = NSHostingController(rootView: view)
            self.contentView = self.hostingController?.view
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.animator().alphaValue = 1.0
            }
        }
    }
    
    func showProcessing() {
        DispatchQueue.main.async {
            let view = RecordingIndicatorView(state: .processing)
            self.hostingController = NSHostingController(rootView: view)
            self.contentView = self.hostingController?.view
        }
    }
    
    func show() {
        showRecording()
    }
    
    func hide() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.completionHandler = {
                    self.orderOut(nil)
                }
                self.animator().alphaValue = 0
            }
        }
    }
}
