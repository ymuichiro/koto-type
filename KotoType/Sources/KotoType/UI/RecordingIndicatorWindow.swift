import AppKit
import SwiftUI

class RecordingIndicatorWindow: NSPanel {
    private var hostingController: NSHostingController<RecordingIndicatorView>?
    private var currentState: IndicatorState = .recording
    private var currentProgressText: String?
    
    init() {
        let initialSize = RecordingIndicatorView.preferredContentSize(for: .recording, progressText: nil)
        let contentRect = NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)
        
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
        let view = RecordingIndicatorView(state: currentState, progressText: currentProgressText)
        hostingController = NSHostingController(rootView: view)
        self.contentView = hostingController?.view
        updatePanelSize(state: currentState, progressText: currentProgressText)
    }
    
    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowWidth = self.contentRect(forFrameRect: self.frame).width
        let windowHeight = self.contentRect(forFrameRect: self.frame).height
        let margin: CGFloat = 50
        
        let x = screenFrame.origin.x + ((screenFrame.width - windowWidth) / 2)
        let y = screenFrame.origin.y + margin
        
        self.setFrame(
            NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            display: true
        )
    }
    
    private func updatePanelSize(state: IndicatorState, progressText: String?) {
        let size = RecordingIndicatorView.preferredContentSize(for: state, progressText: progressText)
        if contentRect(forFrameRect: frame).size != size {
            setContentSize(size)
            positionWindow()
        }
    }

    private func render(state: IndicatorState, progressText: String?, ensureVisible: Bool) {
        currentState = state
        currentProgressText = progressText
        hostingController?.rootView = RecordingIndicatorView(state: state, progressText: progressText)
        updatePanelSize(state: state, progressText: progressText)
        if ensureVisible {
            orderFrontRegardless()
            alphaValue = 1.0
        }
    }

    func showRecording(progressText: String? = nil) {
        DispatchQueue.main.async {
            let shouldAnimate = !self.isVisible || self.alphaValue < 0.99
            self.render(state: .recording, progressText: progressText, ensureVisible: true)

            if shouldAnimate {
                self.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    self.animator().alphaValue = 1.0
                }
            }
        }
    }
    
    func showProcessing(progressText: String? = nil) {
        DispatchQueue.main.async {
            self.render(state: .processing, progressText: progressText, ensureVisible: true)
        }
    }

    func showCompleted(success: Bool) {
        DispatchQueue.main.async {
            self.render(state: success ? .completed : .attention, progressText: nil, ensureVisible: true)
        }
    }
    
    func show() {
        showRecording(progressText: nil)
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
