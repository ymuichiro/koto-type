import AppKit
import SwiftUI

@MainActor
final class PromptAuthoringViewModel: ObservableObject {
    @Published private(set) var state: PromptAuthoringState
    @Published private(set) var isRecording = false
    @Published private(set) var statusMessage = "Opt-in local prompt authoring prototype"

    var onToggleRecording: (() -> Void)?
    var onEndSession: (() -> Void)?
    var onConfirmAndPaste: (() -> Void)?

    init(state: PromptAuthoringState = .initial()) {
        self.state = state
    }

    func setState(_ state: PromptAuthoringState) {
        self.state = state
    }

    func setRecording(_ isRecording: Bool) {
        self.isRecording = isRecording
        if isRecording {
            statusMessage = "Recording a turn..."
        }
    }

    func setStatus(_ message: String) {
        statusMessage = message
    }

    func updateDraft(_ draft: String) {
        state.draft = draft
    }

    func changeFormat(_ format: PromptDraftFormat) {
        state = PromptAuthoringEngine.changingFormat(format, for: state)
    }

    func undoLastTurn() {
        state = PromptAuthoringEngine.undoLastTurn(from: state)
        statusMessage = state.rawTranscripts.isEmpty ? "No turns yet" : "Last turn removed"
    }

    func reset() {
        state = .initial(format: state.format)
        statusMessage = "Session reset. Raw transcripts remain only in this session."
    }
}

@MainActor
final class PromptAuthoringWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: PromptAuthoringViewModel
    private let speechSynthesizer = NSSpeechSynthesizer()
    private var hostingController: NSHostingController<PromptAuthoringView>?
    private var focusTarget: WindowFocusTarget?
    private var suppressCloseCallback = false

    var onToggleRecording: (() -> Void)? {
        didSet { viewModel.onToggleRecording = onToggleRecording }
    }
    var onEndSession: (() -> Void)? {
        didSet { viewModel.onEndSession = onEndSession }
    }
    var onConfirmAndPaste: (() -> Void)? {
        didSet { viewModel.onConfirmAndPaste = onConfirmAndPaste }
    }

    init() {
        viewModel = PromptAuthoringViewModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voice Prompt Authoring (Opt-in Prototype)"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPromptAuthoring(focusTarget: WindowFocusTarget?) {
        self.focusTarget = focusTarget
        setupView()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateRecordingState(_ isRecording: Bool) {
        viewModel.setRecording(isRecording)
    }

    func appendTranscript(_ transcript: String) {
        let result = PromptAuthoringEngine.applyTurn(to: viewModel.state, transcript: transcript)
        viewModel.setState(result.state)
        if result.acceptedTranscript == nil {
            viewModel.setStatus("No usable transcript was received. The raw turn was not changed.")
            return
        }
        guard result.validationPassed else {
            viewModel.setStatus("Draft validation failed. Raw transcript is retained; review before copying.")
            return
        }
        viewModel.setStatus("Draft updated. Review it before confirming.")
        speechSynthesizer.stopSpeaking()
        _ = speechSynthesizer.startSpeaking(result.state.assistantResponse)
    }

    func setStatus(_ message: String) {
        viewModel.setStatus(message)
    }

    func resetSession() {
        speechSynthesizer.stopSpeaking()
        viewModel.reset()
    }

    func closeWithoutEndingSession() {
        suppressCloseCallback = true
        window?.close()
    }

    func confirmAndPaste() {
        guard PromptAuthoringEngine.validate(viewModel.state) else {
            viewModel.setStatus("The draft is not ready to paste. Raw transcripts are preserved.")
            return
        }
        guard let focusTarget else {
            viewModel.setStatus("No original target window was captured. Copy the draft instead.")
            return
        }
        let result = WindowFocusRestorer.restoreIfNeeded(focusTarget)
        guard result != .unavailable else {
            viewModel.setStatus("Could not restore the original target window. Copy the draft instead.")
            return
        }
        KeystrokeSimulator.typeText(viewModel.state.draft)
        viewModel.setStatus("Draft pasted. No submit or voice shortcut was executed.")
    }

    func windowWillClose(_ notification: Notification) {
        speechSynthesizer.stopSpeaking()
        if suppressCloseCallback {
            suppressCloseCallback = false
            return
        }
        onEndSession?()
    }

    private func setupView() {
        guard let window else { return }
        let view = PromptAuthoringView(viewModel: viewModel)
        hostingController = NSHostingController(rootView: view)
        window.contentView = hostingController?.view
    }
}

private struct PromptAuthoringView: View {
    @ObservedObject var viewModel: PromptAuthoringViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice Prompt Authoring")
                        .font(.title2)
                    Text("Developer-only, local-first, turn-based. Raw transcript and draft stay separate.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("End Session") {
                    viewModel.onEndSession?()
                }
            }

            HStack {
                Picker("Draft format", selection: Binding(
                    get: { viewModel.state.format },
                    set: { viewModel.changeFormat($0) }
                )) {
                    ForEach(PromptDraftFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()
                Button(viewModel.isRecording ? "Stop Turn" : "Record Turn") {
                    viewModel.onToggleRecording?()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.state.rawTranscripts.count >= 50 && !viewModel.isRecording)
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 12) {
                panel(title: "Raw Transcript") {
                    if viewModel.state.rawTranscripts.isEmpty {
                        Text("No turns yet")
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            Text(viewModel.state.rawTranscripts.enumerated().map { "Turn \($0.offset + 1): \($0.element)" }.joined(separator: "\n\n"))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                panel(title: "Assistant (spoken after each turn)") {
                    Text(viewModel.state.assistantResponse)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !viewModel.state.pendingQuestion.isEmpty {
                        Text("Next: \(viewModel.state.pendingQuestion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(minHeight: 160)

            panel(title: "Prompt Draft — review before confirmation") {
                TextEditor(text: Binding(
                    get: { viewModel.state.draft },
                    set: { viewModel.updateDraft($0) }
                ))
                .font(.body)
                .frame(minHeight: 260)
                .border(Color.gray.opacity(0.25))
            }

            if !viewModel.state.dialogue.isEmpty {
                DisclosureGroup("Dialogue history (\(viewModel.state.dialogue.count) turns)") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.state.dialogue) { turn in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("You: \(turn.rawTranscript)")
                                    Text("Assistant: \(turn.assistantResponse)")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 130)
                }
            }

            HStack {
                Button("Undo Last Turn") {
                    viewModel.undoLastTurn()
                }
                .disabled(viewModel.state.rawTranscripts.isEmpty || viewModel.isRecording)

                Button("Reset") {
                    viewModel.reset()
                }
                .disabled(viewModel.isRecording)

                Spacer()

                Button("Copy Draft") {
                    copyDraft()
                }
                .disabled(!PromptAuthoringEngine.validate(viewModel.state))

                Button("Confirm & Paste") {
                    viewModel.onConfirmAndPaste?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!PromptAuthoringEngine.validate(viewModel.state) || viewModel.isRecording)
            }

            Text("The assistant only helps author the prompt. It does not answer the prompt, submit it, or run voice shortcuts. Unknown fields remain explicit.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(minWidth: 860, minHeight: 700)
    }

    @ViewBuilder
    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    private func copyDraft() {
        guard PromptAuthoringEngine.validate(viewModel.state) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.state.draft, forType: .string)
        viewModel.setStatus("Draft copied. Nothing was submitted automatically.")
    }
}
