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
        window.title = "初期セットアップ"
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
                Text("KotoType 初期セットアップ")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("利用開始前に必要な権限とFFmpegの有無を確認します。")
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
                                Text("必須")
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
                Button("アクセシビリティを許可") {
                    diagnosticsService.requestAccessibilityPermission()
                    openAccessibilitySettings()
                    startAccessibilityPolling()
                }
                Button("マイクを許可") {
                    isRequestingMicrophone = true
                    diagnosticsService.requestMicrophonePermission { _ in
                        Task { @MainActor in
                            isRequestingMicrophone = false
                            refreshChecks()
                        }
                    }
                }
                .disabled(isRequestingMicrophone)
                Button("システム設定を開く") {
                    openAccessibilitySettings()
                }
                Spacer()
                Button("再チェック") {
                    refreshChecks()
                    shouldShowAccessibilityRestartHint = !isAccessibilityGranted
                }
                if !isAccessibilityGranted {
                    Button("アプリを再起動") {
                        restartApp()
                    }
                }
            }

            if isWaitingForAccessibilityUpdate {
                Text("アクセシビリティ権限の反映を確認中です...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if shouldShowAccessibilityRestartHint && !isAccessibilityGranted {
                Text("アクセシビリティ権限は反映まで数秒かかるか、再起動が必要な場合があります。許可後に「アプリを再起動」を実行してください。")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if !isAccessibilityGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("アクセシビリティ権限のトラブルシューティング")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("権限が反映されない場合は、以下のコマンドで KotoType のアクセシビリティ権限をリセットしてから再起動してください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Self.accessibilityResetCommand)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)

                    HStack(spacing: 10) {
                        Button("コマンドをコピー") {
                            copyAccessibilityResetCommand()
                        }
                        .buttonStyle(.bordered)

                        if hasCopiedAccessibilityResetCommand {
                            Text("コピーしました。ターミナルで実行してください。")
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
                Text("補足")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("このアプリは FFmpeg を同梱しません。`brew install ffmpeg` 後に再チェックしてください。Pythonバックエンドや依存関係は初回起動時に自動準備されるか、リリース版では同梱されます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("セットアップ完了して開始") {
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
