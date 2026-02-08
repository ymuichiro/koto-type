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
    private let diagnosticsService: InitialSetupDiagnosticsService
    private let onComplete: () -> Void

    @State private var report = InitialSetupReport(items: [])
    @State private var isRequestingMicrophone = false

    init(
        diagnosticsService: InitialSetupDiagnosticsService,
        onComplete: @escaping () -> Void
    ) {
        self.diagnosticsService = diagnosticsService
        self.onComplete = onComplete
        _report = State(initialValue: diagnosticsService.evaluate())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STT Simple 初期セットアップ")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("利用開始前に必要な権限と依存関係を確認します。")
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.items, id: \.id) { item in
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
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(height: 320)

            HStack(spacing: 10) {
                Button("アクセシビリティを許可") {
                    diagnosticsService.requestAccessibilityPermission()
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
                    openSystemSettings()
                }
                Spacer()
                Button("再チェック") {
                    refreshChecks()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("依存関係不足時の対応")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("このアプリは FFmpeg を同梱しません。`brew install ffmpeg` を実行し、必要に応じて `make install-deps` / `make build-server` 後に再チェックしてください。")
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
    }

    private func refreshChecks() {
        report = diagnosticsService.evaluate()
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
