import AppKit
import SwiftUI

enum PromptReviewAction {
    case insert(String)
    case copy(String)
    case cancel
}

struct PromptReviewView: View {
    let rawTranscript: String
    @State private var promptMarkdown: String
    let usedFallback: Bool
    let onAction: (PromptReviewAction) -> Void

    init(
        rawTranscript: String,
        promptMarkdown: String,
        usedFallback: Bool,
        onAction: @escaping (PromptReviewAction) -> Void
    ) {
        self.rawTranscript = rawTranscript
        self._promptMarkdown = State(initialValue: promptMarkdown)
        self.usedFallback = usedFallback
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Markdown prompt")
                        .font(.title3.weight(.semibold))
                    Text("Review and edit before inserting. KotoType never submits this to another service automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if usedFallback {
                Label(
                    "AI conversion was unavailable. The raw transcript is shown as the editable draft.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundColor(.orange)
            }

            GroupBox("Raw transcript (preserved)") {
                TextEditor(text: .constant(rawTranscript))
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
                    .disabled(true)
                    .accessibilityLabel("Raw transcript")
            }

            GroupBox("Prompt draft (Markdown)") {
                TextEditor(text: $promptMarkdown)
                    .font(.body.monospaced())
                    .frame(minHeight: 190)
                    .accessibilityLabel("Prompt draft")
            }

            HStack {
                Button("Cancel") {
                    onAction(.cancel)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Copy") {
                    onAction(.copy(promptMarkdown))
                }

                Button("Insert") {
                    onAction(.insert(promptMarkdown))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(promptMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 560)
    }
}

@MainActor
final class PromptReviewWindow: NSPanel, NSWindowDelegate {
    private var hostingController: NSHostingController<PromptReviewView>?
    private var completion: ((PromptReviewAction) -> Void)?
    private var didComplete = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "Review AI Markdown Prompt"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
    }

    func present(
        rawTranscript: String,
        promptMarkdown: String,
        usedFallback: Bool,
        completion: @escaping @MainActor (PromptReviewAction) -> Void
    ) {
        didComplete = false
        self.completion = completion
        let view = PromptReviewView(
            rawTranscript: rawTranscript,
            promptMarkdown: promptMarkdown,
            usedFallback: usedFallback,
            onAction: { [weak self] action in
                self?.complete(action)
            }
        )
        hostingController = NSHostingController(rootView: view)
        contentView = hostingController?.view
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        complete(.cancel)
        return true
    }

    private func complete(_ action: PromptReviewAction) {
        guard !didComplete else { return }
        didComplete = true
        let callback = completion
        completion = nil
        orderOut(nil)
        callback?(action)
    }
}
