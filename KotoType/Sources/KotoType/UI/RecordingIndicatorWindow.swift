import AppKit
import SwiftUI

class RecordingIndicatorWindow: NSPanel {
    private var hostingController: NSHostingController<RecordingIndicatorView>?
    private var currentState: IndicatorState = .recording
    private var currentAttentionMessage: String?
    private var currentProcessingMessage: String?
    private var currentRecordingLevel: CGFloat = 0
    private var currentRecordingInputDeviceName: String?
    private let onCancelTapped: () -> Void
    private var visibilityToken: Int = 0
    
    init(onCancelTapped: @escaping () -> Void = {}) {
        self.onCancelTapped = onCancelTapped
        let initialSize = RecordingIndicatorView.preferredContentSize(
            for: .recording,
            attentionMessage: nil
        )
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
        self.hasShadow = false
        self.backgroundColor = .clear
        self.isOpaque = false
        
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        positionWindow()
    }
    
    private func setupContent() {
        let view = RecordingIndicatorView(
            state: currentState,
            attentionMessage: currentAttentionMessage,
            processingMessage: currentProcessingMessage,
            recordingLevel: currentRecordingLevel,
            recordingInputDeviceName: currentRecordingInputDeviceName,
            onCancelTapped: onCancelTapped
        )
        hostingController = NSHostingController(rootView: view)
        self.contentView = hostingController?.view
        updatePanelSize(
            state: currentState,
            attentionMessage: currentAttentionMessage,
            processingMessage: currentProcessingMessage,
            recordingInputDeviceName: currentRecordingInputDeviceName
        )
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
    
    private func updatePanelSize(
        state: IndicatorState,
        attentionMessage: String?,
        processingMessage: String?,
        recordingInputDeviceName: String?
    ) {
        let size = RecordingIndicatorView.preferredContentSize(
            for: state,
            attentionMessage: attentionMessage,
            processingMessage: processingMessage,
            recordingInputDeviceName: recordingInputDeviceName
        )
        if contentRect(forFrameRect: frame).size != size {
            setContentSize(size)
            positionWindow()
        }
    }

    private func render(
        state: IndicatorState,
        attentionMessage: String?,
        processingMessage: String?,
        ensureVisible: Bool
    ) {
        currentState = state
        currentAttentionMessage = attentionMessage
        currentProcessingMessage = processingMessage
        if state != .recording {
            currentRecordingLevel = 0
            currentRecordingInputDeviceName = nil
        }
        hostingController?.rootView = RecordingIndicatorView(
            state: state,
            attentionMessage: attentionMessage,
            processingMessage: processingMessage,
            recordingLevel: currentRecordingLevel,
            recordingInputDeviceName: currentRecordingInputDeviceName,
            onCancelTapped: onCancelTapped
        )
        updatePanelSize(
            state: state,
            attentionMessage: attentionMessage,
            processingMessage: processingMessage,
            recordingInputDeviceName: currentRecordingInputDeviceName
        )
        if ensureVisible {
            visibilityToken += 1
            contentView?.alphaValue = 1.0
            orderFrontRegardless()
            alphaValue = 1.0
        }
    }

    func showRecording() {
        DispatchQueue.main.async {
            let shouldAnimate = !self.isVisible || self.alphaValue < 0.99
            self.render(state: .recording, attentionMessage: nil, processingMessage: nil, ensureVisible: true)

            if shouldAnimate {
                self.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    self.animator().alphaValue = 1.0
                }
            }
        }
    }
    
    func showProcessing(message: String? = nil) {
        DispatchQueue.main.async {
            self.render(state: .processing, attentionMessage: nil, processingMessage: message, ensureVisible: true)
        }
    }

    func showCompleted(success: Bool) {
        DispatchQueue.main.async {
            self.render(
                state: success ? .completed : .attention,
                attentionMessage: nil,
                processingMessage: nil,
                ensureVisible: true
            )
        }
    }

    func showAttention(message: String) {
        DispatchQueue.main.async {
            self.render(state: .attention, attentionMessage: message, processingMessage: nil, ensureVisible: true)
        }
    }

    func updateRecordingLevel(_ level: CGFloat) {
        DispatchQueue.main.async {
            let clamped = max(0, min(level, 1))
            guard abs(clamped - self.currentRecordingLevel) >= 0.01 else {
                return
            }
            self.currentRecordingLevel = clamped
            guard self.currentState == .recording else {
                return
            }
            self.render(state: .recording, attentionMessage: nil, processingMessage: nil, ensureVisible: false)
        }
    }

    func updateRecordingInputDeviceName(_ name: String?) {
        DispatchQueue.main.async {
            guard self.currentRecordingInputDeviceName != name else {
                return
            }

            self.currentRecordingInputDeviceName = name
            guard self.currentState == .recording else {
                return
            }

            self.render(state: .recording, attentionMessage: nil, processingMessage: nil, ensureVisible: false)
        }
    }
    
    func show() {
        showRecording()
    }
    
    func hide() {
        DispatchQueue.main.async {
            self.visibilityToken += 1
            let hideToken = self.visibilityToken

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.contentView?.animator().alphaValue = 0
            }, completionHandler: {
                DispatchQueue.main.async {
                    guard self.visibilityToken == hideToken else { return }
                    self.orderOut(nil)
                    self.contentView?.alphaValue = 1.0
                }
            })
        }
    }
}
