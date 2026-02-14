import AppKit
import SwiftUI

final class InitialSetupWindowController: NSWindowController {
    convenience init(
        diagnosticsService: InitialSetupDiagnosticsService = InitialSetupDiagnosticsService(),
        onComplete: @escaping () -> Void
    ) {
        let content = InitialSetupView(
            diagnosticsService: diagnosticsService,
            onComplete: onComplete
        )
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Initial Setup"
        window.minSize = NSSize(width: 700, height: 620)
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

struct InitialSetupView: View {
    private static let accessibilityResetCommand = "tccutil reset Accessibility com.ymuichiro.kototype"
    private let diagnosticsService: InitialSetupDiagnosticsService
    private let onComplete: () -> Void
    private let bannerImage: NSImage?

    @State private var report = InitialSetupReport(items: [])
    @State private var isRequestingMicrophone = false
    @State private var isWaitingForAccessibilityUpdate = false
    @State private var shouldShowAccessibilityRestartHint = false
    @State private var hasCopiedAccessibilityResetCommand = false
    @State private var accessibilityRefreshTask: Task<Void, Never>?

    init(
        diagnosticsService: InitialSetupDiagnosticsService,
        onComplete: @escaping () -> Void
    ) {
        self.diagnosticsService = diagnosticsService
        self.onComplete = onComplete
        self.bannerImage = Self.loadBannerImage()
        _report = State(initialValue: diagnosticsService.evaluate())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let bannerImage {
                HStack {
                    Spacer()
                    Image(nsImage: bannerImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 520)
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("KotoType Initial Setup")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Before you start, confirm required permissions and FFmpeg availability.")
                    .foregroundColor(.secondary)
            }

            List(report.items, id: \.id) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.status == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(item.status == .passed ? .green : .red)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title)
                                .font(.headline)
                            if item.required {
                                Text("Required")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 320)

            HStack(spacing: 10) {
                Button("Grant Accessibility") {
                    diagnosticsService.requestAccessibilityPermission()
                    openAccessibilitySettings()
                    startAccessibilityPolling()
                }
                Button("Grant Microphone") {
                    isRequestingMicrophone = true
                    diagnosticsService.requestMicrophonePermission { _ in
                        Task { @MainActor in
                            isRequestingMicrophone = false
                            refreshChecks()
                        }
                    }
                }
                .disabled(isRequestingMicrophone)
                Button("Open System Settings") {
                    openAccessibilitySettings()
                }
                Spacer()
                Button("Re-check") {
                    refreshChecks()
                    shouldShowAccessibilityRestartHint = !isAccessibilityGranted
                }
                if !isAccessibilityGranted {
                    Button("Restart App") {
                        restartApp()
                    }
                }
            }

            if isWaitingForAccessibilityUpdate {
                Text("Checking whether accessibility permission changes have taken effect...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if shouldShowAccessibilityRestartHint && !isAccessibilityGranted {
                Text("Accessibility permission changes may take a few seconds to apply or may require a restart. After granting permission, click "Restart App".")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if !isAccessibilityGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accessibility Permission Troubleshooting")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("If permission changes do not apply, reset KotoType accessibility permission with the command below, then restart the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Self.accessibilityResetCommand)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)

                    HStack(spacing: 10) {
                        Button("Copy command") {
                            copyAccessibilityResetCommand()
                        }
                        .buttonStyle(.bordered)

                        if hasCopiedAccessibilityResetCommand {
                            Text("Copied. Run it in Terminal.")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("This app does not bundle FFmpeg. Install it with `brew install ffmpeg`, then run Re-check. The Python backend and dependencies are prepared automatically on first launch in development, or bundled in release builds.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Finish setup and start") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!report.canStartApplication)
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 620, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshChecks()
        }
        .onDisappear {
            accessibilityRefreshTask?.cancel()
            accessibilityRefreshTask = nil
        }
    }

    private var isAccessibilityGranted: Bool {
        report.items.first(where: { $0.id == "accessibility" })?.status == .passed
    }

    private func refreshChecks() {
        report = diagnosticsService.evaluate()
        if isAccessibilityGranted {
            isWaitingForAccessibilityUpdate = false
            shouldShowAccessibilityRestartHint = false
            accessibilityRefreshTask?.cancel()
            accessibilityRefreshTask = nil
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        accessibilityRefreshTask?.cancel()
        shouldShowAccessibilityRestartHint = false
        isWaitingForAccessibilityUpdate = true

        accessibilityRefreshTask = Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                refreshChecks()
                if isAccessibilityGranted {
                    return
                }
            }

            isWaitingForAccessibilityUpdate = false
            shouldShowAccessibilityRestartHint = !isAccessibilityGranted
            accessibilityRefreshTask = nil
        }
    }

    private func restartApp() {
        guard AppRelauncher.relaunchCurrentApp() else { return }
        NSApp.terminate(nil)
    }

    private func copyAccessibilityResetCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.accessibilityResetCommand, forType: .string)
        hasCopiedAccessibilityResetCommand = true
    }

    private static func loadBannerImage() -> NSImage? {
        AppImageLoader.loadPNG(named: "koto-tyoe_banner_transparent")
    }
}
